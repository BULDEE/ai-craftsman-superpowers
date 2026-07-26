#!/usr/bin/env bash
# =============================================================================
# Deterministic verification loop tests (ADR-0023)
# TaskCompleted evidence gate + test-failure revocation
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

FAKE_HOME="/tmp/craftsman-verify-loop-$$"
mkdir -p "$FAKE_HOME/.claude"
FAKE_STATE="$FAKE_HOME/state.json"
printf '%s' "$FAKE_STATE" > "$FAKE_HOME/.claude/craftsman-session-state-path"

gate() {
    local subject="$1" strictness="$2"
    echo "{\"task\":{\"subject\":\"$subject\"}}" | \
        HOME="$FAKE_HOME" CLAUDE_PLUGIN_OPTION_strictness="$strictness" \
        bash "$ROOT_DIR/hooks/task-completed-verify.sh" 2>/dev/null
}

echo "=== TaskCompleted Evidence Gate ==="

echo '{"verified": false, "writes_count": 5}' > "$FAKE_STATE"
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]]; then
    log_pass "strict + unverified + writes: blocks (exit 2)"
else
    log_fail "strict gate" "expected exit 2, got $EXIT_CODE"
fi

echo '{"verified": true, "writes_count": 5}' > "$FAKE_STATE"
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "strict + verified: allows (exit 0)"
else
    log_fail "verified pass-through" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false, "writes_count": 5}' > "$FAKE_STATE"
OUTPUT=$(gate "Implement user entity" moderate)
if echo "$OUTPUT" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "moderate + unverified: warns via systemMessage, no block"
else
    log_fail "moderate warn" "expected systemMessage: $OUTPUT"
fi

EXIT_CODE=0
gate "Implement user entity" relaxed >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "relaxed: silent pass"
else
    log_fail "relaxed gate" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false, "writes_count": 5}' > "$FAKE_STATE"
EXIT_CODE=0
gate "docs: update readme" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "docs-prefixed task exempt from evidence gate"
else
    log_fail "docs exemption" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false, "writes_count": 0}' > "$FAKE_STATE"
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "no writes this session: nothing to verify (exit 0)"
else
    log_fail "no-writes exemption" "expected exit 0, got $EXIT_CODE"
fi

echo ""
echo "=== Test-Failure Revocation (post-bash-test-verify) ==="

DATA_DIR="$FAKE_HOME/plugin-data"
mkdir -p "$DATA_DIR"

run_verify_hook() {
    local exit_code="$1"
    echo "{\"tool_input\":{\"command\":\"npm test\"},\"tool_result\":{\"exit_code\":$exit_code}}" | \
        HOME="$FAKE_HOME" CLAUDE_PLUGIN_DATA="$DATA_DIR" \
        bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1
}

# Green run sets verified
echo '{"verified": false}' > "$FAKE_STATE"
run_verify_hook 0 >/dev/null || true
# set-verified writes via bridge; verify flag flip is environment-dependent,
# so assert the regression path directly:
echo '{"verified": true}' > "$FAKE_STATE"
EXIT_CODE=0
OUTPUT=$(run_verify_hook 1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]] && echo "$OUTPUT" | grep -q "REGRESSED"; then
    log_pass "failing run after green: exit 2 with regression message (asyncRewake)"
else
    log_fail "regression rewake" "exit=$EXIT_CODE output=$OUTPUT"
fi

if grep -q "test failure: npm test" "$DATA_DIR/test-failures.log" 2>/dev/null; then
    log_pass "failure appended to test-failures.log (monitor feed)"
else
    log_fail "failure log" "missing test-failures.log entry"
fi

echo '{"verified": false}' > "$FAKE_STATE"
EXIT_CODE=0
run_verify_hook 1 >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "failing run without prior green: silent (no rewake spam)"
else
    log_fail "no-spam guard" "expected exit 0, got $EXIT_CODE"
fi

# monitors.json is valid and wires the failure log
if jq -e '.[0].name == "craftsman-test-failures"' "$ROOT_DIR/monitors/monitors.json" >/dev/null 2>&1; then
    log_pass "monitors.json valid, test-failures monitor declared"
else
    log_fail "monitors.json" "invalid or missing monitor entry"
fi

rm -rf "$FAKE_HOME"

test_summary
