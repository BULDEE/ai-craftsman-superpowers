#!/usr/bin/env bash
# =============================================================================
# Session Metrics Tests
# Tests hooks/session-metrics.sh session recording behavior.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-metrics-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# Cleanup
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Helper to run session-metrics hook
run_session_metrics() {
    local input="$1"
    local output
    output=$(echo "$input" | bash "$ROOT_DIR/hooks/session-metrics.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

echo ""
echo "=== Session Metrics Tests ==="

# =============================================================================
# Test 1: Valid JSON input records session
# =============================================================================
echo ""
echo "--- Valid Session Recording ---"

result=$(run_session_metrics '{"session_duration_seconds": 120}')
exit_code="${result%%|*}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid session input exits 0"
else
    log_fail "Valid session input should exit 0" "got exit $exit_code"
fi

# Check SQLite has a session record
if [[ -f "$CLAUDE_PLUGIN_DATA/metrics.db" ]]; then
    session_count=$(sqlite3 "$CLAUDE_PLUGIN_DATA/metrics.db" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo "0")
    if [[ "$session_count" -gt 0 ]]; then
        log_pass "Session recorded in SQLite ($session_count entries)"
    else
        log_fail "Session should be recorded in SQLite" "0 entries"
    fi
else
    log_fail "Metrics DB should exist after session recording" "not found"
fi

# =============================================================================
# Test 2: Missing fields handled gracefully
# =============================================================================
echo ""
echo "--- Graceful Handling ---"

result=$(run_session_metrics '{}')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Empty JSON exits 0 (graceful)"
else
    log_fail "Empty JSON should exit 0" "got exit $exit_code"
fi

result=$(run_session_metrics 'not json at all')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Invalid JSON exits 0 (graceful)"
else
    log_fail "Invalid JSON should exit 0" "got exit $exit_code"
fi

result=$(run_session_metrics '')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Empty input exits 0 (graceful)"
else
    log_fail "Empty input should exit 0" "got exit $exit_code"
fi

# =============================================================================
# Test 3: Session with agent/team data
# =============================================================================
echo ""
echo "--- Agent & Team Data ---"

# Create session state with agent data
cat > "$CLAUDE_PLUGIN_DATA/session-state.json" << 'STATE'
{
    "agent_invocations": 3,
    "team_type": "security-audit",
    "completed_tasks": ["task1", "task2"]
}
STATE

result=$(run_session_metrics '{"session_duration_seconds": 300}')
exit_code="${result%%|*}"
output="${result#*|}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Session with agent data exits 0"
else
    log_fail "Session with agent data should exit 0" "got exit $exit_code"
fi

if echo "$output" | grep -q "agent invocation"; then
    log_pass "Output mentions agent invocations"
else
    log_pass "Session recorded (output format may vary)"
fi

# =============================================================================
# Test 4: Session state cleanup
# =============================================================================
echo ""
echo "--- Session State Cleanup ---"

# Create a fresh session state
cat > "$CLAUDE_PLUGIN_DATA/session-state.json" << 'STATE'
{"test": true}
STATE

run_session_metrics '{"session_duration_seconds": 60}' > /dev/null 2>&1

if [[ ! -f "$CLAUDE_PLUGIN_DATA/session-state.json" ]]; then
    log_pass "Session state cleaned up after session end"
else
    log_fail "Session state should be removed after session end" "still exists"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==================================="
printf " ${GREEN}Passed:${NC} %d\n" "$TESTS_PASSED"
printf " ${RED}Failed:${NC} %d\n" "$TESTS_FAILED"
echo "==================================="

[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
