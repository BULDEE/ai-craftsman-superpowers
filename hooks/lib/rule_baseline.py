#!/usr/bin/env python3
"""Which rule violations a file already carried when its mark was taken.

The structural ratchet answers "is this file worse than it was" for complexity
and size. This answers the same question for rules, which is the half that was
missing and the reason the plugin is hard to adopt on an existing codebase:
measured on a real Symfony application, 98% of files have no
`declare(strict_types=1)` and 88% are not `final`, so under `strict` the first
edit to nearly every file is refused for code the user did not write.

The two live in one file, `.craftsman-baseline.json`, because they answer one
question and a reviewer should see both move in one diff. A structural row and
a rule row for the same path are merged, never one replacing the other.

  {"path": "src/Order.php", "complexity": 4, ..., "rules": {"PHP001": 1, "PHP002": 1}}

Usage:
  rule_baseline.py get <path> <rule> [--baseline FILE]     the recorded count, or 0
  rule_baseline.py record <report.json> [--baseline FILE]  fold a craftsman-ci report in
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from ratchet import (
        BASELINE_NAME,
        load_baseline,
        save_baseline,
        project_root,
        set_project_root,
        _relative,
    )
except ImportError:  # pragma: no cover - ratchet.py is a sibling, absence is a bug
    BASELINE_NAME = ".craftsman-baseline.json"
    load_baseline = save_baseline = project_root = _relative = None
    set_project_root = None


def _baseline_path(args) -> Path:
    if "--baseline" in args:
        explicit = Path(args[args.index("--baseline") + 1])
        # The mark file names the anchor, see ratchet.set_project_root.
        set_project_root(explicit.resolve().parent)
        return explicit
    # The same anchor the structural ratchet uses, so one row carries both even
    # when the command runs from a subdirectory.
    return project_root() / BASELINE_NAME


def _key_for(path: str) -> str:
    """The same key the structural ratchet uses, so one row carries both.

    `_relative` returns None for a file outside the project, which is never
    recorded: an absolute path in a committed baseline leaks local directory
    structure and adds rows no teammate can act on. Such a path falls back to
    itself here and simply never matches a recorded row, which is the right
    answer: an outside file has no mark.
    """
    if _relative is not None:
        try:
            key = _relative(Path(path))
            if key:
                return key
        except (ValueError, OSError):
            pass
    return str(path)


def recorded_count(entries: dict, path: str, rule: str) -> int:
    entry = entries.get(_key_for(path))
    if not isinstance(entry, dict):
        return 0
    rules = entry.get("rules")
    if not isinstance(rules, dict):
        return 0
    value = rules.get(rule, 0)
    return value if isinstance(value, int) and value >= 0 else 0


def counts_from_report(report: dict) -> dict:
    """Per file, how many times each rule fired, from a craftsman-ci JSON report.

    Warnings live in the same `violations` array with `severity: "warning"`, and
    they are counted too: a rule relaxed to advisory today can be promoted
    tomorrow, and the mark should already know what was there.
    """
    counts: dict = {}
    for issue in report.get("violations", []) or []:
        path = str(issue.get("file", ""))
        if not path:
            continue
        path = path[2:] if path.startswith("./") else path
        rule = str(issue.get("rule", ""))
        if not rule:
            continue
        counts.setdefault(path, {})
        counts[path][rule] = counts[path].get(rule, 0) + 1
    return counts


def _cmd_get(args) -> int:
    if len(args) < 2:
        print("0")
        return 1
    entries = load_baseline(_baseline_path(args))
    print(recorded_count(entries, args[0], args[1]))
    return 0


def _merge_counts(entries: dict, counts: dict) -> None:
    """Fold the counts into the existing rows, keeping the structural metrics.

    A structural row and a rule row for one path are the same row: a reviewer
    should see both move in one diff, and a save that replaced one with the
    other would erase a high-water mark nobody meant to move.
    """
    for path, rules in counts.items():
        key = _key_for(path)
        entry = entries.get(key)
        if not isinstance(entry, dict):
            entry = {"path": key}
        entry["rules"] = rules
        entries[key] = entry


def _cmd_record(args) -> int:
    if not args:
        sys.stderr.write("rule_baseline: a craftsman-ci JSON report is required\n")
        return 1
    try:
        with open(args[0], encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("rule_baseline: %s\n" % error)
        return 1

    baseline_file = _baseline_path(args)
    entries = load_baseline(baseline_file)
    counts = counts_from_report(report)
    _merge_counts(entries, counts)
    save_baseline(baseline_file, entries)
    print("rule baseline: %d file(s) -> %s" % (len(counts), baseline_file))
    return 0


COMMANDS = {"get": _cmd_get, "record": _cmd_record}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.stderr.write(__doc__ or "")
        return 1
    if load_baseline is None:
        sys.stderr.write("rule_baseline: ratchet.py could not be imported\n")
        return 1
    return COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
