#!/usr/bin/env bash
# =============================================================================
# Dashboard tests: multi-repository aggregation, self-contained output,
# graceful behaviour on an empty or missing database.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

DASH="$ROOT_DIR/hooks/lib/dashboard.py"
WORK="/tmp/craftsman-dashboard-test-$$"
mkdir -p "$WORK"
DB="$WORK/metrics.db"

sqlite3 "$DB" <<'SQL'
CREATE TABLE violations (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, rule TEXT, file_pattern TEXT, severity TEXT, blocked INT, ignored INT);
CREATE TABLE corrections (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, rule TEXT, file_pattern TEXT, action TEXT, context TEXT);
CREATE TABLE sessions (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, duration_seconds INT, skills_used TEXT, agents_spawned TEXT,
  violations_blocked INT, violations_warned INT, writes_count INT);
INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored) VALUES
  ('repoAAA','PHP001','src/**','critical',1,0),
  ('repoAAA','PHP001','src/**','critical',1,0),
  ('repoAAA','DB003','src/**','warning',0,0),
  ('repoBBB','TS001','src/**','critical',1,0);
INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES
  ('repoAAA','PHP001','src/**','fixed');
INSERT INTO sessions (project_hash, violations_blocked, violations_warned, writes_count) VALUES
  ('repoAAA',3,1,40);
SQL

echo "=== Aggregation ==="

JSON=$(python3 "$DASH" "$DB" --json)

if echo "$JSON" | jq -e '.projects | length == 2' >/dev/null 2>&1; then
    log_pass "aggregates across repositories (2 projects)"
else
    log_fail "multi-repo aggregation" "$(echo "$JSON" | jq -c '.projects')"
fi

if echo "$JSON" | jq -e '.top_rules[0][0] == "PHP001"' >/dev/null 2>&1; then
    log_pass "most-violated rule ranked first (PHP001)"
else
    log_fail "rule ranking" "$(echo "$JSON" | jq -c '.top_rules')"
fi

if echo "$JSON" | jq -e '.corrections | length >= 1' >/dev/null 2>&1; then
    log_pass "corrections included in the aggregate"
else
    log_fail "corrections" "missing from output"
fi

echo ""
echo "=== HTML output ==="

OUT="$WORK/dash.html"
python3 "$DASH" "$DB" --out "$OUT" >/dev/null 2>&1

if [[ -f "$OUT" ]]; then
    log_pass "writes the HTML report to --out"
else
    log_fail "html output" "missing $OUT"
fi

if grep -q "PHP001" "$OUT" && grep -q "repoAAA" "$OUT"; then
    log_pass "report contains per-repository and per-rule data"
else
    log_fail "report content" "missing project or rule rows"
fi

if grep -qE 'src="https?://|href="https?://[^"]*\.css' "$OUT"; then
    log_fail "self-contained" "report references external assets"
else
    log_pass "report is self-contained (no external assets)"
fi

if grep -q "prefers-color-scheme" "$OUT"; then
    log_pass "report styles both light and dark themes"
else
    log_fail "theming" "no prefers-color-scheme block"
fi

echo ""
echo "=== Quality score: one formula, and a fix counts ==="
# /craftsman:metrics described a score of its own in prose, counting
# corrections with action='fix', a value the corrections table refuses: the
# bonus was zero on every database. The dashboard computed a second score that
# ignored corrections altogether (review of main eb54d13, delivery D3). One
# function now, asserted on its values: 3 blocked, 1 warned, 40 writes and one
# correction, which counts only when it is recorded as fixed.
_score_of() { # the score of the last 7 days, the first line of --score, as a number
    local db="$1"
    python3 "$DASH" "$db" --score 7 2>/dev/null | sed -nE '1s/.*: ([0-9]+)\/100.*/\1/p'
}
IGNORED_DB="$WORK/ignored.db"
cp "$DB" "$IGNORED_DB"
sqlite3 "$IGNORED_DB" "UPDATE corrections SET action='ignored';"
WITH_FIX=$(_score_of "$DB")
WITHOUT_FIX=$(_score_of "$IGNORED_DB")
if [[ "$WITH_FIX" == "93" && "$WITHOUT_FIX" == "92" ]]; then
    log_pass "a correction recorded as fixed raises the score (93), the same row recorded as ignored does not (92)"
else
    log_fail "fixed corrections in the score" "with fixed='${WITH_FIX}' with ignored='${WITHOUT_FIX}' (expected 93 and 92)"
fi
python3 "$DASH" "$DB" --out "$WORK/score.html" >/dev/null 2>&1
CARD=$(grep -oE '<div class="n">[0-9]+</div><div class="l">quality score' "$WORK/score.html" | grep -oE '[0-9]+' | head -1)
if [[ -n "$WITH_FIX" && "$CARD" == "$WITH_FIX" ]]; then
    log_pass "the dashboard card and the skill's --score print the same number ($CARD): one formula"
else
    log_fail "one score formula" "dashboard card='${CARD}' --score='${WITH_FIX}'"
fi
SKILL_MD="$ROOT_DIR/skills/metrics/SKILL.md"
if grep -q 'dashboard --score' "$SKILL_MD" && ! grep -qE 'Score = 100|corrections_fixed' "$SKILL_MD"; then
    log_pass "the metrics skill reads the score from the helper and states no formula of its own"
else
    log_fail "the metrics skill carries its own score formula" "$(grep -nE 'Score = 100|corrections_fixed' "$SKILL_MD" | head -2 | tr '\n' ' ')"
fi

echo ""
echo "=== Degradation ==="

EMPTY_DB="$WORK/empty.db"
sqlite3 "$EMPTY_DB" "CREATE TABLE violations (id INTEGER PRIMARY KEY, timestamp TEXT, project_hash TEXT, rule TEXT, file_pattern TEXT, severity TEXT, blocked INT, ignored INT);"
if python3 "$DASH" "$EMPTY_DB" --out "$WORK/empty.html" >/dev/null 2>&1 && grep -q "no data yet" "$WORK/empty.html"; then
    log_pass "empty database renders without error"
else
    log_fail "empty database" "should render an empty-state report"
fi

EXIT_CODE=0
python3 "$DASH" "$WORK/missing.db" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    log_pass "missing database exits non-zero with a clear error"
else
    log_fail "missing database" "should fail"
fi

rm -rf "$WORK"

test_summary
