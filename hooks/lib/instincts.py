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

import sqlite3
import sys

from instinct_skills import approve, global_candidates, promote

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
    ignored INTEGER NOT NULL DEFAULT 0,
    confidence REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'candidate'
        CHECK (status IN ('candidate', 'approved', 'rejected')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    reviewed_at TEXT,
    UNIQUE(project_hash, rule)
)
"""

# Fixes AND rejections, per rule. The first version counted fixes alone, so a
# rule could become a candidate on its fixes while being rejected far more
# often: PHP003 was one, on 105 fixes against 167 suppressions, and promoting
# it would have taught the model a pattern users reject two times out of
# three (#45). A rule rejected as often as it is applied is not a lesson to
# teach, it is a rule to relax (#44), so the bar is strict: more fixes than
# rejections. `ignored` and `scoped` are both rejections of the finding, the
# second the deliberate kind (the rule is wrong in that context); `overridden`
# and `open` say nothing about whether the developer agreed.
# What "across files" counts. `file_path` is the exact file, `file_pattern` a
# directory glob (src/Domain/**/*.php) the trends group by. ADR-0020 says
# files, and counting the glob made MIN_DISTINCT_FILES a count of DIRECTORIES:
# a rule fixed in twenty files of one directory counted as one and could never
# become a candidate. Measured on a real database, 23 PHP001 fixes under one
# glob, zero candidates. A database written before the exact file was recorded
# has no `file_path` column at all, and a crash here would read as "no
# candidate" through session-start.sh, so the column is detected rather than
# assumed; rows with a NULL value fall back to the glob they have always
# counted.
_FILES_COUNTED = "COALESCE(NULLIF(file_path, ''), file_pattern)"
_FILES_COUNTED_LEGACY = "file_pattern"

CANDIDATE_QUERY = """
SELECT rule,
       SUM(CASE WHEN action = 'fixed' THEN 1 ELSE 0 END) AS occurrences,
       COUNT(DISTINCT CASE WHEN action = 'fixed' THEN {files} END) AS distinct_files,
       SUM(CASE WHEN action IN ('ignored', 'scoped') THEN 1 ELSE 0 END) AS ignored,
       MAX(CASE WHEN action = 'fixed' THEN COALESCE(context, '') END) AS sample_context
FROM corrections
WHERE project_hash = ? AND action IN ('fixed', 'ignored', 'scoped')
GROUP BY rule
HAVING occurrences >= ? AND distinct_files >= ? AND occurrences > ignored
"""


def _candidate_query(conn: sqlite3.Connection) -> str:
    try:
        columns = [row[1] for row in conn.execute("PRAGMA table_info(corrections)")]
    except sqlite3.Error:
        columns = []
    files = _FILES_COUNTED if "file_path" in columns else _FILES_COUNTED_LEGACY
    return CANDIDATE_QUERY.format(files=files)

# A column the first schema did not have, added in place on a database created
# before it. Guarded by the table's own catalogue, the way metrics-db.sh guards
# every ADD COLUMN, rather than by the wording of an error.
MIGRATIONS = (
    ("ignored", "ALTER TABLE instincts ADD COLUMN ignored INTEGER NOT NULL DEFAULT 0"),
)


def _has_column(conn: sqlite3.Connection, column: str) -> bool:
    return any(row[1] == column for row in conn.execute("PRAGMA table_info(instincts)"))


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute(SCHEMA)
    for column, statement in MIGRATIONS:
        if not _has_column(conn, column):
            conn.execute(statement)
    conn.commit()
    return conn


# Two statistics on purpose. The candidacy bar in CANDIDATE_QUERY is the point
# estimate (more fixes than rejections): it states what a candidate IS, and a
# human can check it by counting. The bound below states how much evidence
# sits behind it and is only an ORDER: it must not be read as a bar, because
# 50 fixed against 50 rejected has a bound of 0.40 and would pass any bar that
# lets 3 fixed against none (0.44) through.
def _confidence(occurrences: int, ignored: int) -> float:
    """A score that ranks: the lower bound of the acceptance rate, given the evidence.

    The first formula was 0.5 + 0.05 x occurrences + 0.03 x files, capped at
    0.95. It saturated at nine occurrences, so seven of eight candidates sat at
    exactly 0.95, one with 101 corrections and one with 18, and a reviewer
    opening the list had no order to work with (#45). This is the Wilson
    lower bound at 95% on fixed / (fixed + rejected): a rule fixed 101 times
    and never rejected scores 0.96, fixed 18 times 0.82, fixed 3 times 0.44,
    and a rule rejected as often as it is fixed cannot reach 0.5 however many
    rows it has. Nothing caps it and nothing reaches the cap.
    """
    total = occurrences + ignored
    if total == 0:
        return 0.0
    z = 1.96
    rate = occurrences / total
    centre = rate + z * z / (2 * total)
    spread = z * ((rate * (1 - rate) + z * z / (4 * total)) / total) ** 0.5
    return round((centre - spread) / (1 + z * z / total), 2)


def _upsert_candidate(conn: sqlite3.Connection, project_hash: str, row: tuple) -> None:
    rule, occurrences, distinct_files, ignored, sample_context = row
    confidence = _confidence(occurrences, ignored)
    summary = (sample_context or "").strip()[:200]
    existing = conn.execute(
        "SELECT id, status, occurrences FROM instincts WHERE project_hash = ? AND rule = ?",
        (project_hash, rule),
    ).fetchone()

    if existing is None:
        conn.execute(
            "INSERT INTO instincts (project_hash, rule, pattern_summary, occurrences,"
            " distinct_files, ignored, confidence) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (project_hash, rule, summary, occurrences, distinct_files, ignored, confidence),
        )
        return

    instinct_id, status, known_occurrences = existing
    revive = status == "rejected" and occurrences >= known_occurrences + REPROPOSE_EVIDENCE_STEP
    if status == "candidate" or revive:
        conn.execute(
            "UPDATE instincts SET status = 'candidate', occurrences = ?, distinct_files = ?,"
            " ignored = ?, confidence = ?, pattern_summary = ?, reviewed_at = NULL WHERE id = ?",
            (occurrences, distinct_files, ignored, confidence, summary, instinct_id),
        )


def _withdraw_lapsed(conn: sqlite3.Connection, project_hash: str, live: list) -> None:
    """A candidate the query no longer yields is withdrawn.

    Every criterion used to be monotonic on an append-only table (fixes and
    files only grow), so a candidate could never lapse and the upsert never
    had to remove one. The acceptance bar is the first criterion that can stop
    holding: a rule listed on three fixes and then rejected twelve times kept
    its row, its old score and `ignored=0`, stayed in the pending count and
    could be approved into a learned skill. A never-reviewed row carries no
    human decision, so dropping it loses nothing, and it returns when the
    evidence does. Approved and rejected rows are decisions and stay.
    """
    query = "DELETE FROM instincts WHERE project_hash = ? AND status = 'candidate'"
    params: list = [project_hash]
    if live:
        query += " AND rule NOT IN (%s)" % ",".join("?" * len(live))
        params.extend(live)
    conn.execute(query, params)


def refresh_candidates(conn: sqlite3.Connection, project_hash: str) -> None:
    rows = conn.execute(
        _candidate_query(conn), (project_hash, MIN_OCCURRENCES, MIN_DISTINCT_FILES)
    ).fetchall()
    for row in rows:
        _upsert_candidate(conn, project_hash, row)
    _withdraw_lapsed(conn, project_hash, [row[0] for row in rows])
    conn.commit()


def list_instincts(conn: sqlite3.Connection, project_hash: str, status: str | None) -> None:
    query = (
        "SELECT id, rule, occurrences, distinct_files, ignored, confidence, status, pattern_summary "
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
    for iid, rule, occ, files, ignored, conf, st, summary in rows:
        line = (f"#{iid} {rule} [{st}] confidence={conf} corrections={occ} "
                f"ignored={ignored} files={files}")
        print(line + (f" context={summary[:80]}" if summary else ""))


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


def _cmd_global_candidates(conn: sqlite3.Connection, _args: list[str]) -> None:
    rows = global_candidates(conn)
    if not rows:
        print("no global candidates")
        return
    for rule, projects, occurrences, _summary in rows:
        print(f"{rule} [global-candidate] projects={projects} corrections={occurrences}")


def _cmd_promote(conn: sqlite3.Connection, args: list[str]) -> None:
    promote(conn, args[0], args[1])


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
