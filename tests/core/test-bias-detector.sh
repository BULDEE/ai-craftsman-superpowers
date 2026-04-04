#!/usr/bin/env bash
# =============================================================================
# Bias Detector Tests
# Tests hooks/bias-detector.sh pattern detection accuracy.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-bias-tests-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# Cleanup
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Helper to run bias detector
run_bias() {
    local prompt="$1"
    local output
    output=$(echo "{\"prompt\":\"$prompt\"}" | bash "$ROOT_DIR/hooks/bias-detector.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

# =============================================================================
# Acceleration Bias Detection
# =============================================================================
echo ""
echo "=== Bias Detector Tests ==="
echo ""
echo "--- Acceleration Bias ---"

result=$(run_bias "fais ça vite")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Acceleration"; then
    log_pass "FR 'fais ça vite' detects acceleration bias"
else
    log_fail "FR 'fais ça vite' should detect acceleration" "exit=$exit_code"
fi

result=$(run_bias "just do it quick")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Acceleration"; then
    log_pass "EN 'just do it quick' detects acceleration bias"
else
    log_fail "EN 'just do it quick' should detect acceleration" "exit=$exit_code"
fi

# =============================================================================
# Scope Creep Detection
# =============================================================================
echo ""
echo "--- Scope Creep ---"

result=$(run_bias "et aussi ajoutons une feature")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Scope Creep"; then
    log_pass "FR 'et aussi ajoutons' detects scope creep"
else
    log_fail "FR 'et aussi ajoutons' should detect scope creep" "exit=$exit_code"
fi

result=$(run_bias "let's also add logging")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Scope Creep"; then
    log_pass "EN 'let's also add' detects scope creep"
else
    log_fail "EN 'let's also add' should detect scope creep" "exit=$exit_code"
fi

# =============================================================================
# Over-Optimization Detection
# =============================================================================
echo ""
echo "--- Over-Optimization ---"

result=$(run_bias "il faut abstraire ce pattern")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Over-Optimization"; then
    log_pass "FR 'abstraire ce pattern' detects over-optimization"
else
    log_fail "FR 'abstraire ce pattern' should detect over-optimization" "exit=$exit_code"
fi

# =============================================================================
# Domain Modeling Suggestion
# =============================================================================
echo ""
echo "--- Domain Modeling ---"

result=$(run_bias "crée une entité User")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Domain Modeling"; then
    log_pass "FR 'crée une entité' detects domain modeling suggestion"
else
    log_fail "FR 'crée une entité' should detect domain modeling" "exit=$exit_code"
fi

# =============================================================================
# False Positive Tests (should NOT detect any bias)
# =============================================================================
echo ""
echo "--- False Positives ---"

result=$(run_bias "review this pull request")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" || ! "$output" =~ "BIAS DETECTED" ]]; then
    log_pass "'review this pull request' no false positive"
else
    log_fail "'review this pull request' should not detect bias" "got output: $output"
fi

result=$(run_bias "the quick brown fox jumps over the lazy dog")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "Acceleration"; then
    log_pass "'the quick brown fox' triggers acceleration (known: 'quick' matches regex)"
else
    log_fail "'the quick brown fox' should match 'quick' pattern" "exit=$exit_code"
fi

result=$(run_bias "the brown fox jumps over the lazy dog")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" || ! "$output" =~ "Acceleration" ]]; then
    log_pass "'the brown fox' no false acceleration"
else
    log_fail "'the brown fox' should not detect acceleration" "got output: $output"
fi

result=$(run_bias "summarize the changes")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" || ! "$output" =~ "BIAS DETECTED" ]]; then
    log_pass "'summarize the changes' no false positive"
else
    log_fail "'summarize the changes' should not detect bias" "got output: $output"
fi

# =============================================================================
# Exit code must ALWAYS be 0 (non-blocking hook)
# =============================================================================
echo ""
echo "--- Exit Code Safety ---"

for prompt in "fais ça vite" "et aussi" "abstraire" "crée une entité User" "normal prompt"; do
    result=$(run_bias "$prompt")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "0" ]]; then
        log_pass "Exit 0 for: '$prompt'"
    else
        log_fail "Must always exit 0" "got exit $exit_code for '$prompt'"
    fi
done

test_summary
