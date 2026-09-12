#!/usr/bin/env python3
"""Does a rule earn the severity it was given? The number nobody read (#44).

The correction loop records whether a user fixed a violation or suppressed it,
and until now nothing read that back. Measured on this repository's own
database over five months: PHP002 fixed 2 times and ignored 153, a 98.7%
rejection, while still blocking every write it fired on. A rule that is
always suppressed enforces nothing and still costs a round trip.

The other half is worse and this report states it too: 23 of the 36 rules that
ever fired there produced no correction at all, 81% of the volume with no
recorded outcome. Either those findings are never acted on or the loop does
not observe what happens to them, and the two cannot be told apart from here.

Written as a script rather than as rows for a model to add up, for the same
reason haiku_report.py is: this proposes a severity change, and a proposal that
relaxes a gate cannot depend on arithmetic done in prose.

Usage: acceptance_report.py <metrics.db> <project_hash> <days>
                            [--threshold PCT] [--min-occurrences N]

  acceptance = fixed / (fixed + ignored), per rule, over the window.
  A rule under --threshold (default 30) with at least --min-occurrences
  (default 20) outcomes is proposed for relaxation, with the line to write.
"""

import os
import sqlite3
import sys

DEFAULT_THRESHOLD = 30.0
DEFAULT_MIN_OCCURRENCES = 20


_OPTIONS = {
    "--threshold": ("threshold", float),
    "--min-occurrences": ("min", int),
}


def _parse(argv: list) -> tuple:
    if len(argv) < 4:
        sys.stderr.write("usage: acceptance_report.py <metrics.db> <project_hash> <days> "
                         "[--threshold PCT] [--min-occurrences N]\n")
        sys.exit(1)
    options = {"threshold": DEFAULT_THRESHOLD, "min": DEFAULT_MIN_OCCURRENCES}
    rest = argv[4:]
    while rest:
        flag = rest.pop(0)
        value = rest.pop(0) if rest else ""
        if flag not in _OPTIONS:
            sys.stderr.write("acceptance_report: unknown option %s\n" % flag)
            sys.exit(1)
        name, kind = _OPTIONS[flag]
        options[name] = _number(value, flag.lstrip("-"), kind)
    days = _number(argv[3], "days", int)
    if days <= 0:
        sys.stderr.write("acceptance_report: days must be positive, got %d\n" % days)
        sys.exit(1)
    return argv[1], argv[2], days, options


def _number(raw, name, kind):
    try:
        return kind(raw)
    except ValueError:
        sys.stderr.write("acceptance_report: %s must be a number, got %r\n" % (name, raw))
        sys.exit(1)


def _open(db_path):
    # sqlite3.connect CREATES a missing file: "no database" and "nothing in
    # it" must not print the same sentence, nor leave an empty .db behind.
    if not os.path.isfile(db_path):
        print("acceptance: no metrics database at %s" % db_path)
        sys.exit(0)
    try:
        return sqlite3.connect(db_path)
    except sqlite3.Error:
        print("acceptance: the metrics database could not be opened")
        sys.exit(0)


def _rows(db, query, args):
    try:
        return db.execute(query, args).fetchall()
    except sqlite3.Error:
        return []


def acceptance_by_rule(db: sqlite3.Connection, project_hash: str, window: str) -> dict:
    """rule -> (fixed, ignored), only outcomes that are a verdict on the rule.

    `overridden` and `scoped` are decisions about the rule's scope, not about
    one finding, and `open` is a Haiku finding still waiting; none of the three
    says whether the developer agreed with the finding.
    """
    counts = {}
    for rule, action, hits in _rows(db, """
        SELECT rule, action, COUNT(*) FROM corrections
        WHERE project_hash = ? AND timestamp > datetime('now', ?)
          AND action IN ('fixed', 'ignored')
        GROUP BY rule, action""", (project_hash, window)):
        fixed, ignored = counts.get(rule, (0, 0))
        if action == "fixed":
            fixed += hits
        else:
            ignored += hits
        counts[rule] = (fixed, ignored)
    return counts


def no_outcome(db: sqlite3.Connection, project_hash: str, window: str) -> tuple:
    """Rules that fired and never produced a correction row: count, volume."""
    fired = _rows(db, """
        SELECT v.rule, COUNT(*) FROM violations v
        WHERE v.project_hash = ? AND v.timestamp > datetime('now', ?)
          AND NOT EXISTS (
              SELECT 1 FROM corrections c
              WHERE c.project_hash = v.project_hash AND c.rule = v.rule)
        GROUP BY v.rule ORDER BY COUNT(*) DESC""", (project_hash, window))
    total = _rows(db, """
        SELECT COUNT(*) FROM violations
        WHERE project_hash = ? AND timestamp > datetime('now', ?)""", (project_hash, window))
    volume = total[0][0] if total else 0
    return fired, volume


def pct(part: int, whole: int) -> "float | None":
    return None if not whole else 100.0 * part / whole


def fmt_pct(value) -> str:
    return "n/a" if value is None else "%.1f%%" % value


def _print_ranked(counts):
    """Lowest acceptance first, so the rule to look at is the first line."""
    ranked = sorted(counts.items(),
                    key=lambda item: (pct(item[1][0], sum(item[1])) or 0.0, -sum(item[1])))
    for rule, (fixed, ignored) in ranked:
        print("rule %s: acceptance %s (%d fixed, %d ignored)"
              % (rule, fmt_pct(pct(fixed, fixed + ignored)), fixed, ignored))
    return ranked


def _print_proposals(ranked, options):
    proposals = [
        (rule, fixed, ignored) for rule, (fixed, ignored) in ranked
        if fixed + ignored >= options["min"]
        and (pct(fixed, fixed + ignored) or 0.0) < options["threshold"]
    ]
    if not ranked:
        print("proposed relaxations: none, no outcome recorded in the window")
        return
    if not proposals:
        print("proposed relaxations: none (no rule under %.0f%% with %d+ outcomes)"
              % (options["threshold"], options["min"]))
        return
    print("proposed relaxations (acceptance under %.0f%% over %d+ outcomes):"
          % (options["threshold"], options["min"]))
    for rule, fixed, ignored in proposals:
        print("  %s: warn   # .craft-rules.yml, acceptance %s over %d outcomes; "
              "record the decision: in the owning manifest"
              % (rule, fmt_pct(pct(fixed, fixed + ignored)), fixed + ignored))


def _print_no_outcome(db, project_hash, window):
    fired, volume = no_outcome(db, project_hash, window)
    silent_volume = sum(hits for _, hits in fired)
    print("rules that fired with no recorded outcome: %d, %d violation(s), %s of the volume"
          % (len(fired), silent_volume, fmt_pct(pct(silent_volume, volume))))
    for rule, hits in fired[:6]:
        print("  %s: %d fired, no correction ever recorded" % (rule, hits))


def main() -> int:
    db_path, project_hash, days, options = _parse(sys.argv)
    db = _open(db_path)
    window = "-%d days" % days
    counts = acceptance_by_rule(db, project_hash, window)

    fixed_total = sum(fixed for fixed, _ in counts.values())
    ignored_total = sum(ignored for _, ignored in counts.values())
    outcomes = fixed_total + ignored_total
    print("acceptance window: %d days, %d outcome(s) recorded (%d fixed, %d ignored)"
          % (days, outcomes, fixed_total, ignored_total))
    print("overall acceptance: %s" % fmt_pct(pct(fixed_total, outcomes)))
    _print_proposals(_print_ranked(counts), options)
    _print_no_outcome(db, project_hash, window)
    return 0


if __name__ == "__main__":
    sys.exit(main())
