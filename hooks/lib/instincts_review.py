#!/usr/bin/env python3
"""The instinct review queue as JSON (ADR-0031).

Usage:
  instincts_review.py <db> <project_hash> [skills_dir]

skills_dir is where Approve would write, validated as approve validates it;
left out, the current host's (hooks/host-capabilities.json).

Refreshes the candidates the way `instincts.py candidates` does, then prints
{"candidates": [...], "approved": [...]} for one project. A program reads
this, never the prose `instincts.py list` prints for people, so a reworded
line cannot silently empty the cockpit pane. Kept out of instincts.py, which
owns extraction and codification; this module only presents.
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from instinct_skills import (_evidence_contexts, _resolve_skills_dir, _rule_info,  # noqa: E402
                             _skill_for, _slugify, _untrusted)
from instincts import _connect, refresh_candidates  # noqa: E402


def _refusals(conn: sqlite3.Connection, project_hash: str, rule: str) -> dict:
    ignored, scoped, last_fixed = conn.execute(
        "SELECT COALESCE(SUM(action = 'ignored'), 0), COALESCE(SUM(action = 'scoped'), 0),"
        " MAX(CASE WHEN action = 'fixed' THEN timestamp END)"
        " FROM corrections WHERE project_hash = ? AND rule = ?",
        (project_hash, rule),
    ).fetchone()
    return {"ignored": ignored, "scoped": scoped, "last_fixed": last_fixed or ""}


def _candidate_entry(conn: sqlite3.Connection, project_hash: str, row: tuple, skills_dir) -> dict:
    iid, rule, confidence, fixed, rejected, files, summary, _status = row
    entry = {"id": iid, "rule": _untrusted(rule, 40), "confidence": confidence, "fixed": fixed,
             "files": files, "rejected": rejected, "summary": _untrusted(summary)}
    entry.update(_rule_info(rule))
    entry.update(_refusals(conn, project_hash, rule))
    entry["evidence"] = [
        {"file": _untrusted(file_pattern, 120), "context": _untrusted(context, 120)}
        for context, file_pattern in _evidence_contexts(conn, project_hash, rule)
    ]
    entry["skill_path"] = str(skills_dir / f"learned-{_slugify(rule)}" / "SKILL.md")
    entry["skill_preview"] = _skill_for(conn, project_hash, (rule, summary, fixed, files, confidence))
    return entry


# The review queue for a program, not a person (ADR-0031): the cockpit mod
# draws its pane from this and never from the prose `list` prints, so a
# reworded line cannot silently empty the pane. Every text that came out of
# the audited repository goes through `_untrusted`, as it does into a skill.
def review_queue(conn: sqlite3.Connection, project_hash: str, skills_dir: str | None = None) -> dict:
    destination = _resolve_skills_dir(skills_dir)
    refresh_candidates(conn, project_hash)
    rows = conn.execute(
        "SELECT id, rule, confidence, occurrences, ignored, distinct_files, pattern_summary, status"
        " FROM instincts WHERE project_hash = ? AND status IN ('candidate', 'approved')"
        " ORDER BY confidence DESC, occurrences DESC",
        (project_hash,),
    ).fetchall()
    queue: dict = {"candidates": [], "approved": []}
    for row in rows:
        iid, rule, confidence, fixed, _rejected, files, _summary, status = row
        if status == "approved":
            queue["approved"].append({"id": iid, "rule": _untrusted(rule, 40), "confidence": confidence,
                                      "fixed": fixed, "files": files})
            continue
        queue["candidates"].append(_candidate_entry(conn, project_hash, row, destination))
    return queue


def main() -> None:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    conn = _connect(sys.argv[1])
    try:
        print(json.dumps(review_queue(conn, sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else None)))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
