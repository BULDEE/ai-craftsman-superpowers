#!/usr/bin/env bash
# =============================================================================
# Tests for healthcheck library
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-test-hc-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Healthcheck Library Tests ==="

# Source healthcheck
source "$ROOT_DIR/hooks/lib/healthcheck.sh"

# Test: hc_check_system_deps should pass (python3, jq, sqlite3 available in test env)
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_system_deps
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_system_deps reports ok when deps present"
else
    log_fail "hc_check_system_deps should report ok: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_node should pass (node available)
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_node
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_node reports ok for node >= 20"
else
    log_fail "hc_check_node should report ok: ${_HC_STATUSES[0]}"
fi

# Test: hc_run_all produces results
hc_run_all
if [[ ${#_HC_NAMES[@]} -ge 4 ]]; then
    log_pass "hc_run_all produces ${#_HC_NAMES[@]} check results"
else
    log_fail "hc_run_all should produce at least 4 results, got ${#_HC_NAMES[@]}"
fi

# Test: hc_summary produces a one-liner
summary=$(hc_summary)
if [[ "$summary" == Healthcheck:* ]]; then
    log_pass "hc_summary produces one-liner: $summary"
else
    log_fail "hc_summary should start with 'Healthcheck:', got: $summary"
fi

# Test: hc_json produces valid JSON
json=$(hc_json)
if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    log_pass "hc_json produces valid JSON"
else
    log_fail "hc_json should produce valid JSON: $json"
fi

# Test: hc_check_session_bridge warns when bridge file is missing
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
_ORIG_HOME="$HOME"
export HOME="/tmp/craftsman-test-bridge-$$"
mkdir -p "$HOME/.claude"
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "warn" ]]; then
    log_pass "hc_check_session_bridge warns when bridge missing"
else
    log_fail "hc_check_session_bridge should warn when missing: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_session_bridge errors when bridge file is empty
printf '' > "$HOME/.claude/craftsman-session-state-path"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "error" ]]; then
    log_pass "hc_check_session_bridge errors when bridge empty"
else
    log_fail "hc_check_session_bridge should error when empty: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_session_bridge ok when bridge points to valid dir
mkdir -p "$HOME/.claude/plugins/data/craftsman"
printf '%s' "$HOME/.claude/plugins/data/craftsman/session-state.json" > "$HOME/.claude/craftsman-session-state-path"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_session_bridge ok when bridge valid"
else
    log_fail "hc_check_session_bridge should be ok when valid: ${_HC_STATUSES[0]}"
fi

# Cleanup bridge test
rm -rf "$HOME"
export HOME="$_ORIG_HOME"

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
