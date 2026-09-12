#!/usr/bin/env python3
"""Does a rule earn the severity it was given? The number nobody read (#44).

The correction loop records whether a user fixed a violation or suppressed it,
and until now nothing read that back. Measured on this repository's own
database over five months: PHP002 fixed 2 times and ignored 153, a 98.7%
rejection, while still blocking every write it fired on. A rule that is
always suppressed enforces nothing and still costs a round trip.

The other half is stated too, split the way the instrument sees it: an
advisory finding never enters the correction loop (only blocking findings
reach the session state the hook reads), so its silence is by construction;
a blocking finding with no verdict in the window is the one a user can act on.
On the database above, 99.5% of the silent volume was advisory.

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
    says whether the developer agreed with the finding. HAIKU_* rows are left
    out: the semantic layer closes its own loop with `fixed` only, so they sit
    at a structural 100% and haiku_report.py already reports that layer.
    """
    counts = {}
    for rule, action, hits in _rows(db, """
        SELECT rule, action, COUNT(*) FROM corrections
        WHERE project_hash = ? AND timestamp > datetime('now', ?)
          AND action IN ('fixed', 'ignored') AND rule NOT LIKE 'HAIKU%'
        GROUP BY rule, action""", (project_hash, window)):
        fixed, ignored = counts.get(rule, (0, 0))
        if action == "fixed":
            fixed += hits
        else:
            ignored += hits
        counts[rule] = (fixed, ignored)
    return counts


def blocked_by_rule(db: sqlite3.Connection, project_hash: str, window: str) -> dict:
    """rule -> blocking findings in the window, the most a rule can have been judged on.

    By severity, not by the `blocked` column: rows written before 4.6 carry
    blocked=1 on advisory findings (the `$((1 - ignored))` defect
    post-write-check.sh documents), and this count decides whether a proposal
    is even possible.
    """
    return dict(_rows(db, """
        SELECT rule, COUNT(*) FROM violations
        WHERE project_hash = ? AND timestamp > datetime('now', ?)
          AND severity = 'critical' AND ignored = 0
        GROUP BY rule""", (project_hash, window)))


def top_pattern_share(db: sqlite3.Connection, project_hash: str, window: str, rule: str) -> tuple:
    """(pattern, share) of the rule's rejections held by its most rejecting directory.

    The one relaxation this repository has recorded was a SCOPE, not a
    relaxation: 96 of PY002's 99 suppressions came from two generator scripts,
    so the answer was a directory `.craft-rules.yml`, not `PY002: warn`.
    """
    rows = _rows(db, """
        SELECT file_pattern, COUNT(*) FROM corrections
        WHERE project_hash = ? AND timestamp > datetime('now', ?)
          AND rule = ? AND action = 'ignored'
        GROUP BY file_pattern ORDER BY COUNT(*) DESC""", (project_hash, window, rule))
    total = sum(hits for _, hits in rows)
    if not rows or not total:
        return "", None
    return rows[0][0], 100.0 * rows[0][1] / total


# The two halves of this report use one definition of a verdict: a `fixed` or
# `ignored` row for the rule, in the window. An `overridden` row or a fix from
# a year ago used to satisfy the old NOT EXISTS and hide a rule from both
# halves at once.
#
# Split by severity because the instrument cannot see an advisory finding:
# only blocking findings enter the session state the correction loop reads
# (post-write-check.sh, _blocked_rules_json), so an advisory rule with no
# verdict is silent by construction, not by anyone's choice. The blocking
# bucket is the one a user can act on.
def no_verdict(db: sqlite3.Connection, project_hash: str, window: str) -> tuple:
    """Findings in the window that no verdict answered: (blocking rows, advisory rows, volume)."""
    rows = _rows(db, """
        SELECT v.rule, v.severity, COUNT(*) FROM violations v
        WHERE v.project_hash = ? AND v.timestamp > datetime('now', ?)
          AND NOT EXISTS (
              SELECT 1 FROM corrections c
              WHERE c.project_hash = v.project_hash AND c.rule = v.rule
                AND c.action IN ('fixed', 'ignored')
                AND c.timestamp > datetime('now', ?))
        GROUP BY v.rule, v.severity ORDER BY COUNT(*) DESC""", (project_hash, window, window))
    blocking = [(rule, hits) for rule, severity, hits in rows if severity == "critical"]
    advisory = [(rule, hits) for rule, severity, hits in rows if severity != "critical"]
    total = _rows(db, """
        SELECT COUNT(*) FROM violations
        WHERE project_hash = ? AND timestamp > datetime('now', ?)""", (project_hash, window))
    volume = total[0][0] if total else 0
    return blocking, advisory, volume


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


def _proposals(ranked: list, options: dict, blocked: dict) -> tuple:
    """(proposals, recounted): what to propose, and what the instrument recounted.

    A `fixed` or `ignored` row is not a verdict on ONE finding: the hook
    records it from a session state keyed by directory glob, so every later
    write under that glob re-records the same outcome. Measured on a real
    database: PHP002 with 106 `ignored` rows from one pattern against 56
    blocking findings. A rule whose outcomes outnumber the findings it could
    have been judged on is being recounted, and a proposal built on that would
    hand the user a `warn` for an artefact of the instrument. Refused, and the
    discrepancy printed, until the loop counts once per finding.
    """
    proposals, recounted = [], []
    for rule, (fixed, ignored) in ranked:
        if fixed + ignored < options["min"] or (pct(fixed, fixed + ignored) or 0.0) >= options["threshold"]:
            continue
        if fixed + ignored > blocked.get(rule, 0):
            recounted.append((rule, fixed + ignored, blocked.get(rule, 0)))
            continue
        proposals.append((rule, fixed, ignored))
    return proposals, recounted


def _print_proposals(db: sqlite3.Connection, project_hash: str, window: str,
                     ranked: list, options: dict) -> None:
    if not ranked:
        print("proposed relaxations: none, no outcome recorded in the window")
        return
    proposals, recounted = _proposals(ranked, options, blocked_by_rule(db, project_hash, window))
    for rule, outcomes, findings in recounted:
        print("  %s: %d outcomes for %d blocking finding(s), the loop recounts this rule; no proposal"
              % (rule, outcomes, findings))
    if not proposals:
        print("proposed relaxations: none (no rule under %.0f%% with %d+ outcomes)"
              % (options["threshold"], options["min"]))
        return
    print("proposed relaxations (acceptance under %.0f%% over %d+ outcomes), for .craft-rules.yml:"
          % (options["threshold"], options["min"]))
    print("  rules:")
    for rule, fixed, ignored in proposals:
        print("    %s: warn   # acceptance %s over %d outcomes; record the decision: in the owning manifest"
              % (rule, fmt_pct(pct(fixed, fixed + ignored)), fixed + ignored))
        pattern, share = top_pattern_share(db, project_hash, window, rule)
        if share is not None and share >= 50.0:
            print("    # %s of the rejections come from %s: a directory .craft-rules.yml there may be the "
                  "scope, not a relaxation" % (fmt_pct(share), pattern))


def _print_no_verdict(db: sqlite3.Connection, project_hash: str, window: str) -> None:
    blocking, advisory, volume = no_verdict(db, project_hash, window)
    blocking_volume = sum(hits for _, hits in blocking)
    advisory_volume = sum(hits for _, hits in advisory)
    print("blocking findings with no verdict in the window: %d rule(s), %d finding(s), %s of the volume"
          % (len(blocking), blocking_volume, fmt_pct(pct(blocking_volume, volume))))
    for rule, hits in blocking[:6]:
        print("  %s: %d blocked, never fixed nor ignored in the window" % (rule, hits))
    print("advisory findings with no verdict: %d rule(s), %d finding(s), %s of the volume; unobservable by "
          "construction, only a blocking finding enters the correction loop"
          % (len(advisory), advisory_volume, fmt_pct(pct(advisory_volume, volume))))
    for rule, hits in advisory[:3]:
        print("  %s: %d advisory" % (rule, hits))


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
    _print_proposals(db, project_hash, window, _print_ranked(counts), options)
    _print_no_verdict(db, project_hash, window)
    return 0


if __name__ == "__main__":
    sys.exit(main())
