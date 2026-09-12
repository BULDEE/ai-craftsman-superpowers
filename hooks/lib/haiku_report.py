#!/usr/bin/env python3
"""The three numbers the semantic layer has to earn its place with.

Written as a script rather than as rows for a model to add up: this decides
whether a paid layer stays on by default, and a decision that opens or closes a
gate cannot depend on arithmetic done in prose.

  1. the share of Haiku findings with no Level 1 finding on the same file
     pattern in the window. Only that share justifies a second layer.
  2. the fixed rate of Haiku findings, comparable to Level 1's own.
  3. Haiku seconds spent per accepted finding.

Usage: haiku_report.py <metrics.db> <project_hash> <days>
"""

import sqlite3, sys

import os

if len(sys.argv) < 4:
    sys.stderr.write("usage: haiku_report.py <metrics.db> <project_hash> <days>\n")
    sys.exit(1)

db_path, project_hash = sys.argv[1], sys.argv[2]
try:
    days = int(sys.argv[3])
except ValueError:
    sys.stderr.write("haiku_report: days must be a whole number, got %r\n" % sys.argv[3])
    sys.exit(1)
if days <= 0:
    sys.stderr.write("haiku_report: days must be positive, got %d\n" % days)
    sys.exit(1)
window = "-%d days" % days

# sqlite3.connect CREATES a missing file, so "no database" and "a database with
# nothing in it" printed the same sentence and left an empty .db behind on a
# machine that had never run the layer.
if not os.path.isfile(db_path):
    print("haiku: no metrics database at %s" % db_path)
    sys.exit(0)
try:
    db = sqlite3.connect(db_path)
except sqlite3.Error:
    print("haiku: the metrics database could not be opened")
    sys.exit(0)

def scalar(query, args, default=0):
    try:
        row = db.execute(query, args).fetchone()
    except sqlite3.Error:
        return default
    return row[0] if row and row[0] is not None else default

runs = scalar("SELECT COUNT(*) FROM haiku_runs WHERE project_hash=? AND timestamp > datetime('now',?)",
              (project_hash, window))
if not runs:
    print("haiku runs: 0 in %d days (the semantic layer recorded nothing yet)" % days)
    sys.exit(0)

with_findings = scalar("SELECT COUNT(*) FROM haiku_runs WHERE project_hash=? AND verdict='findings' AND timestamp > datetime('now',?)",
                       (project_hash, window))
unavailable = scalar("SELECT COUNT(*) FROM haiku_runs WHERE project_hash=? AND verdict='unavailable' AND timestamp > datetime('now',?)",
                     (project_hash, window))
seconds = scalar("SELECT SUM(duration_ms) FROM haiku_runs WHERE project_hash=? AND timestamp > datetime('now',?)",
                 (project_hash, window)) / 1000.0

findings = scalar("SELECT COUNT(*) FROM violations WHERE project_hash=? AND source='haiku' AND timestamp > datetime('now',?)",
                  (project_hash, window))

# A Haiku finding on a file pattern Level 1 also fired on is not evidence of a
# second layer: it is the same file seen twice. The share that matters is the
# one Level 1 never touched.
# Joined on the EXACT file, not on the directory bucket.
#
# `file_pattern` maps every .php in a directory to one glob, so a Haiku finding
# on Order.php counted as "Level 1 saw it" because Level 1 had fired on
# Customer.php next door; and whenever the two layers spelled the same path
# differently, the same query reported 100% novelty. Rows written before the
# file_path column existed are excluded from BOTH sides rather than counted as
# unseen, which is why the line says how many rows it could compare.
comparable = scalar("""
    SELECT COUNT(*) FROM violations
    WHERE project_hash=? AND source='haiku' AND file_path IS NOT NULL AND file_path <> ''
      AND timestamp > datetime('now',?)
""", (project_hash, window))

unseen = scalar("""
    SELECT COUNT(*) FROM violations v
    WHERE v.project_hash=? AND v.source='haiku'
      AND v.file_path IS NOT NULL AND v.file_path <> ''
      AND v.timestamp > datetime('now',?)
      AND NOT EXISTS (
        SELECT 1 FROM violations l
        WHERE l.project_hash = v.project_hash AND l.source <> 'haiku'
          AND l.file_path = v.file_path
          AND l.timestamp > datetime('now',?)
      )
""", (project_hash, window, window))

# Written by haiku_close_resolved: what the verifier said last time about a
# file and no longer says. Nothing else in the tree writes a HAIKU_ correction,
# which is why these two lines printed a permanent n/a before that existed.
fixed = scalar("SELECT COUNT(*) FROM corrections WHERE project_hash=? AND rule LIKE 'HAIKU%' AND action='fixed' AND timestamp > datetime('now',?)",
               (project_hash, window))
resolved = scalar("SELECT COUNT(*) FROM corrections WHERE project_hash=? AND rule LIKE 'HAIKU%' AND action <> 'open' AND timestamp > datetime('now',?)",
                  (project_hash, window))
level1_fixed = scalar("SELECT COUNT(*) FROM corrections WHERE project_hash=? AND rule NOT LIKE 'HAIKU%' AND action='fixed' AND timestamp > datetime('now',?)",
                      (project_hash, window))
level1_resolved = scalar("SELECT COUNT(*) FROM corrections WHERE project_hash=? AND rule NOT LIKE 'HAIKU%' AND action <> 'open' AND timestamp > datetime('now',?)",
                         (project_hash, window))

def pct(part, whole):
    return "n/a" if not whole else "%.1f%%" % (100.0 * part / whole)

print("haiku runs: %d in %d days (%d found something, %d could not run)"
      % (runs, days, with_findings, unavailable))
print("haiku findings: %d" % findings)
if comparable:
    print("findings Level 1 never saw on the same file: %d of %d comparable (%s)"
          % (unseen, comparable, pct(unseen, comparable)))
else:
    print("findings Level 1 never saw on the same file: not computable yet "
          "(%d finding(s) recorded before the exact path was stored)" % findings)
print("haiku fixed rate: %s (%d of %d resolved)" % (pct(fixed, resolved), fixed, resolved))
print("level 1 fixed rate: %s (%d of %d resolved)" % (pct(level1_fixed, level1_resolved), level1_fixed, level1_resolved))
print("haiku seconds per accepted finding: %s"
      % ("n/a" if not fixed else "%.1f" % (seconds / fixed)))
print("haiku seconds total: %.1f" % seconds)
