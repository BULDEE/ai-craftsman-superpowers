#!/usr/bin/env bash
# =============================================================================
# Hook Behavior Tests
# Tests post-write-check.sh and pre-write-check.sh with fixtures.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Use temp dir for metrics to avoid polluting real DB
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-hook-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Run a hook with fixture, capture exit code and output
run_post_hook() {
    local fixture="$1"
    local output
    output=$(echo "{\"tool_input\":{\"file_path\":\"$fixture\"}}" | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

run_pre_hook() {
    local file_path="$1"
    local content="$2"
    local output
    output=$(jq -n --arg fp "$file_path" --arg c "$content" '{"tool_input":{"file_path":$fp,"content":$c}}' | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

# =============================================================================
# Post-Write Hook Tests
# =============================================================================
echo ""
echo "=== Post-Write Hook Tests ==="

# Test: Valid PHP should pass
result=$(run_post_hook "$FIXTURES_DIR/valid-entity.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid PHP passes (exit 0)"
else
    log_fail "Valid PHP should pass" "got exit $exit_code"
fi

# Test: Missing strict_types should block
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "PHP001"; then
    log_pass "Missing strict_types blocks (exit 2, PHP001)"
else
    log_fail "Missing strict_types should block" "exit=$exit_code"
fi

# Test: Missing final should block
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-final.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "PHP002"; then
    log_pass "Missing final blocks (exit 2, PHP002)"
else
    log_fail "Missing final should block" "exit=$exit_code"
fi

# Test: TypeScript any should block
result=$(run_post_hook "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "TS001"; then
    log_pass "TypeScript any blocks (exit 2, TS001)"
else
    log_fail "TypeScript any should block" "exit=$exit_code"
fi

# Test: Valid TypeScript should pass
result=$(run_post_hook "$FIXTURES_DIR/valid-component.tsx")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid TypeScript passes (exit 0)"
else
    log_fail "Valid TypeScript should pass" "got exit $exit_code"
fi

# Test: craftsman-ignore should pass (not block)
result=$(run_post_hook "$FIXTURES_DIR/with-craftsman-ignore.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "craftsman-ignore suppresses blocking (exit 0)"
else
    log_fail "craftsman-ignore should suppress" "got exit $exit_code"
fi

# Test: Layer violation should block
result=$(run_post_hook "$FIXTURES_DIR/invalid-layer-violation.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "LAYER"; then
    log_pass "Layer violation blocks (exit 2, LAYER)"
else
    log_fail "Layer violation should block" "exit=$exit_code"
fi

# Test: JSON output is valid
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | jq . >/dev/null 2>&1; then
    log_pass "Output is valid JSON"
else
    log_fail "Output should be valid JSON" "$output"
fi

# Test: Metrics were recorded
METRIC_COUNT=$(sqlite3 "$CLAUDE_PLUGIN_DATA/metrics.db" "SELECT COUNT(*) FROM violations;" 2>/dev/null || echo 0)
if [[ "$METRIC_COUNT" -gt 0 ]]; then
    log_pass "Metrics recorded ($METRIC_COUNT violations in DB)"
else
    log_fail "Metrics should be recorded" "0 violations in DB"
fi

# =============================================================================
# Pre-Write Hook Tests
# =============================================================================
echo ""
echo "=== Pre-Write Hook Tests ==="

# Test: Domain importing Infrastructure should block
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Pre-write blocks Domain->Infrastructure import (exit 2)"
else
    log_fail "Pre-write should block layer violation" "exit=$exit_code"
fi

# Test: Valid Domain file should pass
result=$(run_pre_hook "src/Domain/Entity/User.php" "<?php\ndeclare(strict_types=1);\nnamespace App\\\\Domain\\\\Entity;\nfinal class User {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write allows valid Domain file (exit 0)"
else
    log_fail "Pre-write should allow valid file" "exit=$exit_code"
fi

# Test: Non-source files should pass silently
result=$(run_pre_hook "config/services.yaml" "services:\n  App\\:")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write ignores non-source files (exit 0)"
else
    log_fail "Pre-write should ignore non-source files" "exit=$exit_code"
fi

# =============================================================================
# Post-Write Hook — Config-Aware Tests
# =============================================================================
echo ""
echo "=== Post-Write Hook — Config-Aware Tests ==="

# Test: stack=react skips PHP rules
export CLAUDE_USER_CONFIG_stack="react"
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "stack=react skips PHP rules (exit 0 on PHP file)"
else
    log_fail "stack=react should skip PHP rules" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# Test: stack=symfony skips TS rules
export CLAUDE_USER_CONFIG_stack="symfony"
result=$(run_post_hook "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "stack=symfony skips TS rules (exit 0 on TS file)"
else
    log_fail "stack=symfony should skip TS rules" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# Test: strictness=relaxed warns instead of blocking
export CLAUDE_USER_CONFIG_strictness="relaxed"
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "strictness=relaxed warns PHP001 (exit 0)"
else
    log_fail "strictness=relaxed should warn not block" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true

# Test: strictness=moderate blocks LAYER but warns PHP001
export CLAUDE_USER_CONFIG_strictness="moderate"
result=$(run_post_hook "$FIXTURES_DIR/invalid-layer-violation.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "LAYER"; then
    log_pass "strictness=moderate blocks LAYER violations (exit 2)"
else
    log_fail "strictness=moderate should block LAYER" "exit=$exit_code"
fi

result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "strictness=moderate warns PHP001 (exit 0)"
else
    log_fail "strictness=moderate should warn PHP001" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true

# Test: default behavior unchanged (strict + fullstack)
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Default behavior: PHP001 still blocks (backward compatible)"
else
    log_fail "Default behavior should block PHP001" "got exit $exit_code"
fi

# =============================================================================
# Pre-Write Hook — Config-Aware Tests
# =============================================================================
echo ""
echo "=== Pre-Write Hook — Config-Aware Tests ==="

# Test: stack=react skips PHP layer checks
export CLAUDE_USER_CONFIG_stack="react"
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write: stack=react skips PHP layer checks (exit 0)"
else
    log_fail "Pre-write: stack=react should skip PHP" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# Test: strictness=relaxed warns instead of blocking layer violations
export CLAUDE_USER_CONFIG_strictness="relaxed"
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write: strictness=relaxed warns layer violation (exit 0)"
else
    log_fail "Pre-write: strictness=relaxed should warn" "got exit $exit_code"
fi
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true

# Test: default still blocks
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Pre-write: default still blocks layer violations (backward compatible)"
else
    log_fail "Pre-write: default should block" "got exit $exit_code"
fi

# =============================================================================
# SessionStart Hook Tests
# =============================================================================
echo ""
echo "=== SessionStart Hook Tests ==="

run_session_start() {
    local output
    output=$(echo '{}' | bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

ORIGINAL_PWD="$PWD"
SESSION_TEST_DIR="/tmp/craftsman-session-tests-$$"
mkdir -p "$SESSION_TEST_DIR"
cd "$SESSION_TEST_DIR"

# Clean env for session tests
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# Test: Outputs valid JSON
result=$(run_session_start)
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | jq . >/dev/null 2>&1; then
    log_pass "SessionStart outputs valid JSON (exit 0)"
else
    log_fail "SessionStart should output valid JSON" "exit=$exit_code"
fi

# Test: Detects symfony (composer.json only)
rm -f package.json
echo '{}' > composer.json
result=$(run_session_start)
output="${result#*|}"
if echo "$output" | grep -qi "symfony\|Stack: symfony"; then
    log_pass "SessionStart detects composer.json project"
else
    log_fail "SessionStart should detect symfony" "$output"
fi
rm -f composer.json

# Test: Detects react (package.json only)
rm -f composer.json
echo '{}' > package.json
result=$(run_session_start)
output="${result#*|}"
if echo "$output" | grep -qi "react\|Stack: react"; then
    log_pass "SessionStart detects package.json project"
else
    log_fail "SessionStart should detect react" "$output"
fi
rm -f package.json

# Test: Detects fullstack (both)
echo '{}' > composer.json
echo '{}' > package.json
result=$(run_session_start)
output="${result#*|}"
if echo "$output" | grep -q "fullstack"; then
    log_pass "SessionStart detects fullstack project"
else
    log_fail "SessionStart should detect fullstack" "$output"
fi
rm -f composer.json package.json

# Test: Suggests setup when no .craft-config.yml
result=$(run_session_start)
output="${result#*|}"
if echo "$output" | grep -q "craft-config\|setup"; then
    log_pass "SessionStart suggests /craftsman:setup when no config"
else
    log_fail "SessionStart should suggest setup" "$output"
fi

# Test: No setup suggestion when .craft-config.yml exists
cat > "$SESSION_TEST_DIR/.craft-config.yml" <<'YAML'
strictness: strict
stack: fullstack
YAML
result=$(run_session_start)
output="${result#*|}"
if ! echo "$output" | grep -q "setup"; then
    log_pass "SessionStart silent about setup when config exists"
else
    log_fail "SessionStart should not suggest setup" "$output"
fi
rm -f .craft-config.yml

# Test: Always exits 0
result=$(run_session_start)
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "SessionStart always exits 0 (non-blocking)"
else
    log_fail "SessionStart should always exit 0" "got exit $exit_code"
fi

cd "$ORIGINAL_PWD"
rm -rf "$SESSION_TEST_DIR"

# =============================================================================
# Cleanup & Summary
# =============================================================================
rm -rf "$CLAUDE_PLUGIN_DATA"

echo ""
echo "==================================="
echo -e " ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e " ${RED}Failed:${NC} $TESTS_FAILED"
echo "==================================="

[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
