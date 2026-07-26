#!/usr/bin/env python3
"""Instinct pipeline (ADR-0020): corrections -> candidates -> human review -> learned skills.

Subcommands:
  candidates <db> <project_hash>            refresh + list candidate instincts
  list <db> <project_hash> [status]         list instincts (default: all)
  pending-count <db> <project_hash>         print number of candidates awaiting review
  approve <db> <id> <skills_dir>            generate learned skill, mark approved
  reject <db> <id>                          mark rejected (re-proposed only on new evidence)

Promotion is never automatic: `candidates` only records what a human may
approve. Generated skills carry provenance and are plain files the user
can edit or delete.
"""
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

MIN_OCCURRENCES = 3
MIN_DISTINCT_FILES = 3
REPROPOSE_EVIDENCE_STEP = 3

SCHEMA = """
CREATE TABLE IF NOT EXISTS instincts (
    id INTEGER PRIMARY KEY,
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    pattern_summary TEXT,
    occurrences INTEGER NOT NULL DEFAULT 0,
    distinct_files INTEGER NOT NULL DEFAULT 0,
    confidence REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'candidate'
        CHECK (status IN ('candidate', 'approved', 'rejected')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    reviewed_at TEXT,
    UNIQUE(project_hash, rule)
)
"""

CANDIDATE_QUERY = """
SELECT rule, COUNT(*) AS occurrences,
       COUNT(DISTINCT file_pattern) AS distinct_files,
       MAX(COALESCE(context, '')) AS sample_context
FROM corrections
WHERE project_hash = ? AND action = 'fixed'
GROUP BY rule
HAVING occurrences >= ? AND distinct_files >= ?
"""


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute(SCHEMA)
    conn.commit()
    return conn


def _confidence(occurrences: int, distinct_files: int) -> float:
    return round(min(0.5 + 0.05 * occurrences + 0.03 * distinct_files, 0.95), 2)


def _upsert_candidate(conn: sqlite3.Connection, project_hash: str, row: tuple) -> None:
    rule, occurrences, distinct_files, sample_context = row
    confidence = _confidence(occurrences, distinct_files)
    summary = (sample_context or "").strip()[:200]
    existing = conn.execute(
        "SELECT id, status, occurrences FROM instincts WHERE project_hash = ? AND rule = ?",
        (project_hash, rule),
    ).fetchone()

    if existing is None:
        conn.execute(
            "INSERT INTO instincts (project_hash, rule, pattern_summary, occurrences,"
            " distinct_files, confidence) VALUES (?, ?, ?, ?, ?, ?)",
            (project_hash, rule, summary, occurrences, distinct_files, confidence),
        )
        return

    instinct_id, status, known_occurrences = existing
    revive = status == "rejected" and occurrences >= known_occurrences + REPROPOSE_EVIDENCE_STEP
    if status == "candidate" or revive:
        conn.execute(
            "UPDATE instincts SET status = 'candidate', occurrences = ?, distinct_files = ?,"
            " confidence = ?, pattern_summary = ?, reviewed_at = NULL WHERE id = ?",
            (occurrences, distinct_files, confidence, summary, instinct_id),
        )


def refresh_candidates(conn: sqlite3.Connection, project_hash: str) -> None:
    rows = conn.execute(
        CANDIDATE_QUERY, (project_hash, MIN_OCCURRENCES, MIN_DISTINCT_FILES)
    ).fetchall()
    for row in rows:
        _upsert_candidate(conn, project_hash, row)
    conn.commit()


def list_instincts(conn: sqlite3.Connection, project_hash: str, status: str | None) -> None:
    query = (
        "SELECT id, rule, occurrences, distinct_files, confidence, status, pattern_summary "
        "FROM instincts WHERE project_hash = ?"
    )
    params: list[str] = [project_hash]
    if status:
        query += " AND status = ?"
        params.append(status)
    rows = conn.execute(query + " ORDER BY confidence DESC, occurrences DESC", params).fetchall()
    if not rows:
        print("no instincts")
        return
    for iid, rule, occ, files, conf, st, summary in rows:
        line = f"#{iid} {rule} [{st}] confidence={conf} corrections={occ} files={files}"
        print(line + (f" context={summary[:80]}" if summary else ""))


def _slugify(rule: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in rule).strip("-")


SKILL_TEMPLATE = """---
description: Learned instinct for rule {rule}. This project corrected {rule} {occurrences} times across {distinct_files} files; apply the fix pattern proactively when writing matching code.
user-invocable: false
---

# Learned Instinct: {rule}

This project repeatedly corrects **{rule}**. Apply the correction proactively instead of waiting for the quality gate to flag it.

## Pattern

{pattern}

## Evidence

{evidence}

## Provenance

- Source: {occurrences} recorded corrections across {distinct_files} files (confidence {confidence})
- Approved by human review on {today} via /craftsman:metrics
- Delete this file or run /craftsman:metrics to retire the instinct
"""


def _render_skill(rule: str, summary: str, occurrences: int, distinct_files: int,
                  confidence: float, contexts: list[tuple]) -> str:
    evidence = "\n".join(
        f"- `{fp}`: {ctx[:120]}" if ctx else f"- `{fp}`" for ctx, fp in contexts
    ) or "- (contexts not recorded)"
    return SKILL_TEMPLATE.format(
        rule=rule,
        occurrences=occurrences,
        distinct_files=distinct_files,
        confidence=confidence,
        pattern=summary or f"See the {rule} rule definition in the active pack validators.",
        evidence=evidence,
        today=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    )


def _load_candidate(conn: sqlite3.Connection, instinct_id: int) -> tuple:
    row = conn.execute(
        "SELECT project_hash, rule, pattern_summary, occurrences, distinct_files, confidence"
        " FROM instincts WHERE id = ? AND status = 'candidate'",
        (instinct_id,),
    ).fetchone()
    if row is None:
        print(f"error: no candidate instinct with id {instinct_id}", file=sys.stderr)
        sys.exit(1)
    return row


def _evidence_contexts(conn: sqlite3.Connection, project_hash: str, rule: str) -> list[tuple]:
    return conn.execute(
        "SELECT DISTINCT COALESCE(context, ''), file_pattern FROM corrections"
        " WHERE project_hash = ? AND rule = ? AND action = 'fixed'"
        " ORDER BY timestamp DESC LIMIT 3",
        (project_hash, rule),
    ).fetchall()


def approve(conn: sqlite3.Connection, instinct_id: int, skills_dir: str) -> None:
    project_hash, rule, summary, occurrences, distinct_files, confidence = _load_candidate(
        conn, instinct_id
    )
    contexts = _evidence_contexts(conn, project_hash, rule)
    skill_dir = Path(skills_dir) / f"learned-{_slugify(rule)}"
    skill_dir.mkdir(parents=True, exist_ok=True)
    content = _render_skill(rule, summary, occurrences, distinct_files, confidence, contexts)
    (skill_dir / "SKILL.md").write_text(content)
    conn.execute(
        "UPDATE instincts SET status = 'approved', reviewed_at = datetime('now') WHERE id = ?",
        (instinct_id,),
    )
    conn.commit()
    print(f"approved: {skill_dir / 'SKILL.md'}")


def reject(conn: sqlite3.Connection, instinct_id: int) -> None:
    changed = conn.execute(
        "UPDATE instincts SET status = 'rejected', reviewed_at = datetime('now')"
        " WHERE id = ? AND status = 'candidate'",
        (instinct_id,),
    ).rowcount
    conn.commit()
    if changed == 0:
        print(f"error: no candidate instinct with id {instinct_id}", file=sys.stderr)
        sys.exit(1)
    print(f"rejected: #{instinct_id}")


def _cmd_candidates(conn: sqlite3.Connection, args: list[str]) -> None:
    refresh_candidates(conn, args[0])
    list_instincts(conn, args[0], "candidate")


def _cmd_pending_count(conn: sqlite3.Connection, args: list[str]) -> None:
    refresh_candidates(conn, args[0])
    count = conn.execute(
        "SELECT COUNT(*) FROM instincts WHERE project_hash = ? AND status = 'candidate'",
        (args[0],),
    ).fetchone()[0]
    print(count)


def _cmd_list(conn: sqlite3.Connection, args: list[str]) -> None:
    list_instincts(conn, args[0], args[1] if len(args) > 1 else None)


def _cmd_approve(conn: sqlite3.Connection, args: list[str]) -> None:
    approve(conn, int(args[0]), args[1])


def _cmd_reject(conn: sqlite3.Connection, args: list[str]) -> None:
    reject(conn, int(args[0]))


COMMANDS = {
    "candidates": (_cmd_candidates, 1),
    "pending-count": (_cmd_pending_count, 1),
    "list": (_cmd_list, 1),
    "approve": (_cmd_approve, 2),
    "reject": (_cmd_reject, 1),
}


def main() -> None:
    if len(sys.argv) < 4 or sys.argv[1] not in COMMANDS:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    handler, min_args = COMMANDS[sys.argv[1]]
    args = sys.argv[3:]
    if len(args) < min_args:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    conn = _connect(sys.argv[2])
    try:
        handler(conn, args)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
