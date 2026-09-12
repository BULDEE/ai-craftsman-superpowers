#!/usr/bin/env bash
# =============================================================================
# Acceptance per rule: the number the correction loop recorded and nobody read.
#
# Measured on a real database: PHP002 fixed 2 times, ignored 153, still
# blocking every write. The report ranks rules by fixed / (fixed + ignored),
# proposes a relaxation under a threshold once enough outcomes exist, and
# states how much of the violation volume never produced an outcome at all.
# Asserted on VALUES from a synthetic database whose arithmetic is known, and
# on the two silences a report like this can hide behind: an empty window is
# "no outcome", never a rate, and a rule with too few outcomes is not proposed.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-acceptance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"

echo "=== Acceptance report (#44) ==="

REPORT="$ROOT_DIR/hooks/lib/acceptance_report.py"
DB="$WORK/data/metrics.db"
( source "$ROOT_DIR/hooks/lib/metrics-db.sh"; metrics_init ) >/dev/null 2>&1
HASH="$( cd "$WORK" && bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_project_hash" )"

# rows <table> <count> <rule> <action or severity> [pattern] [age in days]
# One INSERT per group through the parameterised helper, however many rows.
rows() {
    local table="$1" count="$2" rule="$3" kind="$4" pattern="${5:-src/**/*.php}" age="${6:-0}"
    [[ "$count" -gt 0 ]] || return 0
    local series="WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < CAST(? AS INTEGER)) SELECT i FROM n"
    if [[ "$table" == "corrections" ]]; then
        python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
            "INSERT INTO corrections (project_hash, rule, file_pattern, action, timestamp) SELECT ?, ?, ?, ?, datetime('now', ?) FROM ($series)" \
            "$HASH" "$rule" "$pattern" "$kind" "-${age} days" "$count"
    else
        python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
            "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored, timestamp) SELECT ?, ?, ?, ?, 1, 0, datetime('now', ?) FROM ($series)" \
            "$HASH" "$rule" "$pattern" "$kind" "-${age} days" "$count"
    fi
}

# --- An empty window is a sentence, not a rate --------------------------------
empty="$(python3 "$REPORT" "$DB" "$HASH" 30)"
assert_contains "no outcome recorded reads as n/a, never as 0%" "$empty" "overall acceptance: n/a"
assert_contains "and proposes nothing" "$empty" "proposed relaxations: none, no outcome recorded"

# --- The issue's own numbers ---------------------------------------------------
rows corrections 2   PHP002 fixed   "src/Domain/**/*.php"
rows corrections 153 PHP002 ignored "src/Domain/**/*.php"   # every rejection from one directory
rows violations  160 PHP002 critical                        # judged at most once per finding
rows corrections 176 PY001 fixed
rows corrections 10  PY001 ignored
rows violations  200 PY001 critical
rows corrections 55  SH002 fixed
rows corrections 44  SH002 ignored
rows violations  100 SH002 critical
rows corrections 1   TS002 fixed
rows corrections 5   TS002 ignored                          # 16.7% but 6 outcomes: too few
rows violations  10  TS002 critical
rows corrections 1   PHP002 scoped                          # a scope decision, not a verdict
rows corrections 9   HAIKU_DDD fixed                        # the semantic layer closes its own loop
# The instrument's own artefact: 5 fixed and 25 ignored on a rule that
# produced 10 blocking findings. Thirty verdicts on ten findings is a recount.
rows corrections 5   RECOUNT001 fixed
rows corrections 25  RECOUNT001 ignored
rows violations  10  RECOUNT001 critical
# No verdict, four shapes: a blocking rule never answered; an advisory rule
# (unobservable by construction); a rule answered only by `overridden` (the
# deptrac precedence path, not a verdict); a rule whose one fix is 400 days old.
rows violations  60  PHPSTAN001 critical
rows violations  20  LOC001 warning
rows violations  30  LAYER001 critical
rows corrections 3   LAYER001 overridden
rows violations  5   OLD001 critical
rows corrections 1   OLD001 fixed "src/**/*.php" 400

out="$(python3 "$REPORT" "$DB" "$HASH" 30)"
assert_contains "PHP002 acceptance is 1.3% (2 of 155), and scoped is not an outcome" "$out" "rule PHP002: acceptance 1.3% (2 fixed, 153 ignored)"
assert_contains "PY001 acceptance is 94.6%" "$out" "rule PY001: acceptance 94.6% (176 fixed, 10 ignored)"
if echo "$out" | grep -q "HAIKU"; then
    log_fail "HAIKU rows are not ranked as rules-engine verdicts" "$(echo "$out" | grep HAIKU)"
else
    log_pass "HAIKU rows are not ranked as rules-engine verdicts (the semantic layer has its own report)"
fi
if [[ "$(echo "$out" | grep '^rule ' | head -1)" == "rule PHP002:"* ]]; then
    log_pass "the worst acceptance is the first rule listed"
else
    log_fail "the worst acceptance is the first rule listed" "$(echo "$out" | grep '^rule ' | head -1)"
fi
assert_contains "the proposals are written under the rules: key the engine reads" "$out" "  rules:"
assert_contains "PHP002 is proposed for relaxation with the line to write" "$out" "    PHP002: warn   # acceptance 1.3% over 155 outcomes"
assert_contains "and told where the decision is recorded" "$out" "record the decision: in the owning manifest"
# -F: the pattern carries `**`, which assert_contains would read as a regex.
if echo "$out" | grep -qF "# 100.0% of the rejections come from src/Domain/**/*.php: a directory .craft-rules.yml there may be the scope"; then
    log_pass "and told that its rejections come from one directory, a scope rather than a relaxation"
else
    log_fail "and told that its rejections come from one directory, a scope rather than a relaxation" "$(echo "$out" | grep -F 'rejections come from')"
fi
if echo "$out" | grep -q "^    TS002: warn"; then
    log_fail "a rule with too few outcomes is not proposed" "TS002 proposed on 6 outcomes"
else
    log_pass "a rule with too few outcomes is not proposed (TS002, 6 outcomes)"
fi
if echo "$out" | grep -q "^    SH002: warn\|^    PY001: warn"; then
    log_fail "a rule above the threshold is not proposed" "$(echo "$out" | grep '^    .*: warn')"
else
    log_pass "a rule above the threshold is not proposed (SH002 55.6%, PY001 94.6%)"
fi
assert_contains "a rule with more outcomes than blocking findings is refused as a recount, and the discrepancy printed" "$out" \
    "  RECOUNT001: 30 outcomes for 10 blocking finding(s), the loop recounts this rule; no proposal"
if echo "$out" | grep -q "^    RECOUNT001: warn"; then
    log_fail "and not proposed" "RECOUNT001 proposed"
else
    log_pass "and not proposed"
fi

# --- The half that is worse: findings with no verdict --------------------------
# Volume: 160 + 200 + 100 + 10 + 10 + 60 + 20 + 30 + 5 = 595. Blocking with no
# verdict in the window: PHPSTAN001 60, LAYER001 30 (overridden is not a
# verdict), OLD001 5 (the fix is outside the window): 95, 16.0%. Advisory:
# LOC001 20, 3.4%.
assert_contains "blocking findings with no verdict are counted as a share of the volume, overridden and out-of-window excluded" "$out" \
    "blocking findings with no verdict in the window: 3 rule(s), 95 finding(s), 16.0% of the volume"
assert_contains "and the biggest silent blocking rule is named first" "$out" "  PHPSTAN001: 60 blocked, never fixed nor ignored in the window"
assert_contains "a rule answered only by overridden rows is silent, not answered" "$out" "  LAYER001: 30 blocked"
assert_contains "a fix outside the window does not answer this window's findings" "$out" "  OLD001: 5 blocked"
assert_contains "advisory findings are reported apart, as unobservable by construction" "$out" \
    "advisory findings with no verdict: 1 rule(s), 20 finding(s), 3.4% of the volume; unobservable by construction"

# --- The thresholds are arguments, so a team can tighten them -------------------
strict_out="$(python3 "$REPORT" "$DB" "$HASH" 30 --threshold 60 --min-occurrences 5)"
assert_contains "a lower bar proposes TS002 too" "$strict_out" "    TS002: warn"
assert_contains "and SH002 at 55.6% under a 60% threshold" "$strict_out" "    SH002: warn"
bad_out="$(python3 "$REPORT" "$DB" "$HASH" 30 --threshold high 2>&1)"
assert_contains "a threshold that is not a number is refused, not read as 0" "$bad_out" "threshold must be a number"

# --- Through the shipped entry point ------------------------------------------
via_shell="$( cd "$WORK" && bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_acceptance_report 30" 2>/dev/null )"
assert_contains "metrics_acceptance_report reaches the same database" "$via_shell" "rule PHP002: acceptance 1.3%"
via_flags="$( cd "$WORK" && bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_acceptance_report --threshold 60 --min-occurrences 5" 2>/dev/null )"
assert_contains "the day count is optional before the flags" "$via_flags" "    TS002: warn"

# --- A missing database is said, and not created ------------------------------
missing_out="$(python3 "$REPORT" "$WORK/absent.db" "$HASH" 30)"
assert_contains "a missing database is named" "$missing_out" "no metrics database at"
if [[ -f "$WORK/absent.db" ]]; then
    log_fail "a missing database is not created by the report" "absent.db appeared"
else
    log_pass "a missing database is not created by the report"
fi

test_summary
