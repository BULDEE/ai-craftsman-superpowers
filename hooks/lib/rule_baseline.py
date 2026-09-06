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
  rule_baseline.py counts <path> [--baseline FILE]         every count for one file, RULE=N
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


def _key_for(path: str):
    """The same key the structural ratchet uses, so one row carries both.

    None for a file outside the project. The docstring here used to say exactly
    that while the code fell back to the absolute path and `_merge_counts`
    wrote it: `craftsman-ci baseline ../shared` carved machine-specific
    directories into a committed artifact, which is the invariant
    `_photograph_into` skips a row to protect. A lookup for an outside file
    still answers "no mark", which is the right answer.
    """
    if _relative is not None:
        try:
            key = _relative(Path(path))
            if key:
                return key
        except (ValueError, OSError):
            pass
        return None
    return str(path)


def _anchor_for_file(path: str):
    """The project the FILE belongs to, not the one the shell happens to be in.

    A hook is fired with whatever working directory the editor has, and a
    pipeline may run from anywhere: anchoring on cwd made the same file answer
    differently from two places, and in a repository holding a submodule with
    its own mark the two answers were "blocked" and "clean". The file's own
    location is the one thing both callers agree on.
    """
    if project_root is None:
        return None
    try:
        return project_root(Path(path).resolve().parent)
    except (ValueError, OSError):
        return None


def recorded_count(entries: dict, path: str, rule: str) -> int:
    key = _key_for(path)
    if key is None:
        return 0
    entry = entries.get(key)
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
    if "--baseline" not in args:
        anchor = _anchor_for_file(args[0])
        if anchor is not None:
            set_project_root(anchor)
    entries = load_baseline(_baseline_path(args))
    print(recorded_count(entries, args[0], args[1]))
    return 0


_ADMITTED: list = []


def _merged_rules(recorded: dict, rules: dict, admit_new: bool) -> dict:
    """The lower of the two counts, never the newer.

    A mark that adopted the current count would absorb, as inherited, every
    violation added since it was taken: a second `craftsman-ci baseline` run, or
    the command wired into CI by mistake, would pardon new debt under a reason
    that says "the state this repository arrived in". A count that went down
    stays down, which is the ratchet direction.
    """
    merged = {}
    for rule, count in rules.items():
        previous = recorded.get(rule)
        if isinstance(previous, int) and previous >= 0:
            merged[rule] = min(previous, count)
        elif admit_new:
            # A rule nobody could have recorded, because it did not exist here
            # at the mark: a pack added later, a language newly declared.
            # Admitted only on a re-mark the user asked for by name.
            merged[rule] = count
    for rule, previous in recorded.items():
        # Fired at the mark, silent now: the debt was paid, and it is not
        # granted back.
        if rule not in merged and rule in rules:
            merged[rule] = previous
    return merged


# A row with no `rules` key, whether or not a structural row exists. The
# distinction matters because `ratchet.py init` runs first and creates a row for
# every file it measures, including files written after the mark: keying this
# test on the entry rather than on its `rules` key let every one of them
# through, which is the drift the guard exists to stop.
def _admits_unmarked(key: str, admit_new: bool, first_mark: bool) -> bool:
    if first_mark:
        return True
    _ADMITTED.append(key)
    return admit_new


def _merge_counts(entries: dict, counts: dict, admit_new: bool = False,
                  first_mark: bool = True) -> None:
    """Fold the counts into the existing rows, keeping the structural metrics.

    A structural row and a rule row for one path are the same row: a reviewer
    should see both move in one diff, and a save that replaced one with the
    other would erase a high-water mark nobody meant to move. A path outside
    the project is skipped, exactly as the structural half skips it rather than
    writing a local directory into a file the whole team clones.
    """
    for path, rules in counts.items():
        key = _key_for(path)
        if key is None:
            continue
        entry = entries.get(key)
        recorded = entry.get("rules") if isinstance(entry, dict) else None
        if isinstance(recorded, dict):
            entry["rules"] = _merged_rules(recorded, rules, admit_new)
        else:
            if not _admits_unmarked(key, admit_new, first_mark):
                continue
            entry = entry if isinstance(entry, dict) else {"path": key}
            entry["rules"] = rules
        entries[key] = entry


def _cmd_counts(args) -> int:
    """Every recorded count for one file, `RULE=N` per line.

    One interpreter start per file instead of one per finding. `get` reloads
    and re-parses the whole baseline for each violation, and a scan of a
    codebase where 98% of files carry PHP001 makes that thousands of process
    starts: several minutes added to a pipeline, to read the same JSON again.
    """
    if not args:
        return 1
    if "--baseline" not in args:
        anchor = _anchor_for_file(args[0])
        if anchor is not None:
            set_project_root(anchor)
    entries = load_baseline(_baseline_path(args))
    key = _key_for(args[0])
    entry = entries.get(key) if key is not None else None
    rules = entry.get("rules") if isinstance(entry, dict) else None
    if not isinstance(rules, dict):
        return 0
    for rule in sorted(rules):
        count = rules[rule]
        if isinstance(count, int) and count >= 0:
            print("%s=%d" % (rule, count))
    return 0


def _announce_admitted(args) -> None:
    """Said out loud, because this is the one path where a mark grows.

    A re-mark that absorbs forty files should not look like one that absorbs
    none.
    """
    if not _ADMITTED:
        return
    verb = "admitted" if "--re-baseline" in args else "left out"
    shown = ", ".join(sorted(_ADMITTED)[:5])
    if len(_ADMITTED) > 5:
        shown += ", ..."
    print("rule baseline: %d file(s) written since the mark, %s: %s"
          % (len(_ADMITTED), verb, shown))


def _load_report(path: str):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("rule_baseline: %s\n" % error)
        return None


# "First mark" means no rule row anywhere, not an empty file: a repository that
# used the structural ratchet before this feature existed has entries already,
# and its first rule mark is still a first mark.
def _already_marked(entries: dict) -> bool:
    return any(
        isinstance(entry, dict) and isinstance(entry.get("rules"), dict)
        for entry in entries.values()
    )


def _cmd_record(args) -> int:
    """`record <report.json> [--re-baseline]`.

    Without `--re-baseline`, an existing entry only ever goes down: this is the
    guard against the command being wired into CI, where every run would
    otherwise adopt the current state as inherited.
    """
    if not args:
        sys.stderr.write("rule_baseline: a craftsman-ci JSON report is required\n")
        return 1
    report = _load_report(args[0])
    if report is None:
        return 1

    baseline_file = _baseline_path(args)
    entries = load_baseline(baseline_file)
    counts = counts_from_report(report)
    _merge_counts(entries, counts, admit_new="--re-baseline" in args,
                  first_mark=not _already_marked(entries))
    save_baseline(baseline_file, entries)
    print("rule baseline: %d file(s) -> %s" % (len(counts), baseline_file))
    _announce_admitted(args)
    return 0


COMMANDS = {"get": _cmd_get, "counts": _cmd_counts, "record": _cmd_record}


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
