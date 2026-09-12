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

seed() {
    # seed <rule> <fixed> <ignored> [violations fired]
    local rule="$1" fixed="$2" ignored="$3" fired="${4:-0}" i
    for ((i = 0; i < fixed; i++)); do
        python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
            "INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES (?, ?, 'src/**/*.php', 'fixed')" "$HASH" "$rule"
    done
    for ((i = 0; i < ignored; i++)); do
        python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
            "INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES (?, ?, 'src/**/*.php', 'ignored')" "$HASH" "$rule"
    done
    for ((i = 0; i < fired; i++)); do
        python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
            "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored) VALUES (?, ?, 'src/**/*.php', 'critical', 1, 0)" "$HASH" "$rule"
    done
}

# --- An empty window is a sentence, not a rate --------------------------------
empty="$(python3 "$REPORT" "$DB" "$HASH" 30)"
assert_contains "no outcome recorded reads as n/a, never as 0%" "$empty" "overall acceptance: n/a"
assert_contains "and proposes nothing" "$empty" "proposed relaxations: none, no outcome recorded"

# --- The issue's own numbers ---------------------------------------------------
seed PHP002 2 153 40          # 1.3% acceptance, the worst offender
seed PY001 176 10 5           # 94.6%, a rule that earns its severity
seed SH002 55 44              # 55.6%, above the threshold
seed TS002 1 5                # 16.7% but 6 outcomes: too few to propose
seed PHPSTAN001 0 0 60        # fired 60 times, no outcome ever recorded
seed LOC001 0 0 20            # same
python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$DB" \
    "INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES (?, 'PHP002', 'src/**/*.php', 'scoped')" "$HASH"

out="$(python3 "$REPORT" "$DB" "$HASH" 30)"
assert_contains "PHP002 acceptance is 1.3% (2 of 155), and scoped is not an outcome" "$out" "rule PHP002: acceptance 1.3% (2 fixed, 153 ignored)"
assert_contains "PY001 acceptance is 94.6%" "$out" "rule PY001: acceptance 94.6% (176 fixed, 10 ignored)"
assert_contains "overall acceptance is the issue's 47% shape: 234 of 446" "$out" "overall acceptance: 52.5%"
if [[ "$(echo "$out" | grep '^rule ' | head -1)" == "rule PHP002:"* ]]; then
    log_pass "the worst acceptance is the first rule listed"
else
    log_fail "the worst acceptance is the first rule listed" "$(echo "$out" | grep '^rule ' | head -1)"
fi
assert_contains "PHP002 is proposed for relaxation with the line to write" "$out" "  PHP002: warn   # .craft-rules.yml, acceptance 1.3% over 155 outcomes"
assert_contains "and told where the decision is recorded" "$out" "record the decision: in the owning manifest"
if echo "$out" | grep -q "^  TS002: warn"; then
    log_fail "a rule with too few outcomes is not proposed" "TS002 proposed on 6 outcomes"
else
    log_pass "a rule with too few outcomes is not proposed (TS002, 6 outcomes)"
fi
if echo "$out" | grep -q "^  SH002: warn\|^  PY001: warn"; then
    log_fail "a rule above the threshold is not proposed" "$(echo "$out" | grep '^  .*: warn')"
else
    log_pass "a rule above the threshold is not proposed (SH002 55.6%, PY001 94.6%)"
fi

# --- The half that is worse: findings with no outcome at all -------------------
# 125 violations fired; PHPSTAN001 (60) and LOC001 (20) never produced a
# correction row: 80 of 125.
assert_contains "the no-outcome share is stated as a share of the volume" "$out" \
    "rules that fired with no recorded outcome: 2, 80 violation(s), 64.0% of the volume"
assert_contains "and the biggest silent rule is named first" "$out" "  PHPSTAN001: 60 fired, no correction ever recorded"

# --- The thresholds are arguments, so a team can tighten them -------------------
strict_out="$(python3 "$REPORT" "$DB" "$HASH" 30 --threshold 60 --min-occurrences 5)"
assert_contains "a lower bar proposes TS002 too" "$strict_out" "  TS002: warn"
assert_contains "and SH002 at 55.6% under a 60% threshold" "$strict_out" "  SH002: warn"
bad_out="$(python3 "$REPORT" "$DB" "$HASH" 30 --threshold high 2>&1)"
assert_contains "a threshold that is not a number is refused, not read as 0" "$bad_out" "threshold must be a number"

# --- Through the shipped entry point ------------------------------------------
via_shell="$( cd "$WORK" && bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_acceptance_report 30" 2>/dev/null )"
assert_contains "metrics_acceptance_report reaches the same database" "$via_shell" "rule PHP002: acceptance 1.3%"

# --- A missing database is said, and not created ------------------------------
missing_out="$(python3 "$REPORT" "$WORK/absent.db" "$HASH" 30)"
assert_contains "a missing database is named" "$missing_out" "no metrics database at"
if [[ -f "$WORK/absent.db" ]]; then
    log_fail "a missing database is not created by the report" "absent.db appeared"
else
    log_pass "a missing database is not created by the report"
fi

test_summary
