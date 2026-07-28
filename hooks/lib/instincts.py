#!/usr/bin/env python3
"""Instinct pipeline (ADR-0020): corrections -> candidates -> human review -> learned skills.

Subcommands:
  candidates <db> <project_hash>            refresh + list candidate instincts
  list <db> <project_hash> [status]         list instincts (default: all)
  pending-count <db> <project_hash>         print number of candidates awaiting review
  approve <db> <id> <skills_dir>            generate learned skill, mark approved
  reject <db> <id>                          mark rejected (re-proposed only on new evidence)
  global-candidates <db>                    rules approved in 2+ projects (promotion candidates)
  promote <db> <rule> <skills_dir>          generate a global learned skill for a rule

Promotion is never automatic: `candidates` only records what a human may
approve. Generated skills carry provenance and are plain files the user
can edit or delete.
"""
# `str | None` in an annotation is PEP 604, evaluated at runtime from Python
# 3.10. /usr/bin/python3 on a Mac without homebrew is 3.9, where importing this
# module raised TypeError and the whole instinct pipeline was dead. Deferring
# annotation evaluation keeps the modern syntax and runs on 3.9.
from __future__ import annotations

import re
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
    return "".join(char.lower() if char.isalnum() else "-" for char in rule).strip("-")


# A generated skill is loaded into the model's context as background knowledge,
# so every field interpolated into it is an instruction channel. Two of them are
# not plugin-controlled: pattern_summary comes from a correction's context, and
# the evidence lines carry file_pattern, which is a path out of the audited
# repository. A newline in either one closes the markdown body and lets the rest
# of the string read as fresh instructions - or, at the top of the file, as more
# YAML frontmatter. Collapse to a single line, drop the characters that would
# terminate the inline-code fence, and cap the length.
_UNTRUSTED_MAX = 200


def _untrusted(text: str, limit: int = _UNTRUSTED_MAX) -> str:
    collapsed = " ".join(str(text or "").split())
    stripped = "".join(char for char in collapsed if char.isprintable() and char != "`")
    if len(stripped) > limit:
        stripped = stripped[:limit] + "..."
    return stripped


# metrics-db.sh validates a rule id before it writes one, but this module is a
# second front door: it reads rows a previous version wrote, and rows written by
# anything else pointed at the same database. Validating here keeps the
# guarantee local instead of borrowing it from a caller three files away.
_RULE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{1,39}$")


def _safe_rule(rule: str) -> str:
    if not _RULE_RE.match(str(rule or "")):
        print(f"error: refusing to generate a skill for malformed rule id: {rule!r}",
              file=sys.stderr)
        sys.exit(1)
    return rule


# skills_dir is raw argv. _slugify already prevents the rule from walking out of
# it, but nothing stopped the directory itself from pointing anywhere writable.
# A generated skill only means something inside the project or the user's own
# Claude configuration; anywhere else is a write primitive, not a feature.
def _resolve_skills_dir(skills_dir: str) -> Path:
    target = Path(skills_dir).expanduser().resolve()
    allowed = [Path.cwd().resolve()]
    home = Path.home().resolve()
    allowed.append(home / ".claude")
    for root in allowed:
        if target == root or root in target.parents:
            return target
    print(f"error: refusing to write skills outside the project or ~/.claude: {target}",
          file=sys.stderr)
    sys.exit(1)


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
    rule = _safe_rule(rule)
    evidence = "\n".join(
        f"- `{_untrusted(fp, 120)}`: {_untrusted(ctx, 120)}" if ctx
        else f"- `{_untrusted(fp, 120)}`"
        for ctx, fp in contexts
    ) or "- (contexts not recorded)"
    return SKILL_TEMPLATE.format(
        rule=rule,
        occurrences=occurrences,
        distinct_files=distinct_files,
        confidence=confidence,
        pattern=_untrusted(summary) or f"See the {rule} rule definition in the active pack validators.",
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
    skill_dir = _resolve_skills_dir(skills_dir) / f"learned-{_slugify(rule)}"
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


GLOBAL_TEMPLATE = """---
description: Cross-project learned instinct for rule {rule}. Confirmed in {project_count} independent projects; apply the fix pattern proactively when writing matching code.
user-invocable: false
---

# Global Learned Instinct: {rule}

This correction was approved independently in **{project_count} projects**, so it reflects how you work rather than one codebase's quirk. Apply it proactively.

## Pattern

{pattern}

## Provenance

- Confirmed in {project_count} projects ({occurrences} corrections total)
- Promoted from project scope by human review on {today} via /craftsman:metrics
- Delete this file to retire the instinct globally
"""


def global_candidates(conn: sqlite3.Connection) -> list[tuple]:
    """Rules approved in 2+ distinct projects and not yet promoted globally."""
    return conn.execute(
        "SELECT rule, COUNT(DISTINCT project_hash) AS projects, SUM(occurrences),"
        " MAX(COALESCE(pattern_summary, ''))"
        " FROM instincts WHERE status = 'approved'"
        " GROUP BY rule HAVING projects >= 2"
    ).fetchall()


def _cmd_global_candidates(conn: sqlite3.Connection, _args: list[str]) -> None:
    rows = global_candidates(conn)
    if not rows:
        print("no global candidates")
        return
    for rule, projects, occurrences, _summary in rows:
        print(f"{rule} [global-candidate] projects={projects} corrections={occurrences}")


def _cmd_promote(conn: sqlite3.Connection, args: list[str]) -> None:
    """Promote a rule to global scope. Human-invoked only, never automatic."""
    rule, skills_dir = args[0], args[1]
    match = [row for row in global_candidates(conn) if row[0] == rule]
    if not match:
        print(f"error: {rule} is not approved in 2+ projects", file=sys.stderr)
        sys.exit(1)
    _rule, projects, occurrences, summary = match[0]
    rule = _safe_rule(rule)
    skill_dir = _resolve_skills_dir(skills_dir) / f"learned-global-{_slugify(rule)}"
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(GLOBAL_TEMPLATE.format(
        rule=rule,
        project_count=projects,
        occurrences=occurrences,
        pattern=_untrusted(summary) or f"See the {rule} rule definition in the active pack validators.",
        today=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    ))
    print(f"promoted: {skill_dir / 'SKILL.md'}")


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
    "global-candidates": (_cmd_global_candidates, 0),
    "promote": (_cmd_promote, 2),
}


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] not in COMMANDS:
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
