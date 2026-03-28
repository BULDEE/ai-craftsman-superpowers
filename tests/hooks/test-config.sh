#!/usr/bin/env bash
# =============================================================================
# Config Resolution Library Tests
# Tests config.sh with TDD: default values, env var overrides, .craft-config.yml
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

source "$ROOT_DIR/hooks/lib/config.sh"

# Use temp dir for isolation
TEST_DIR="/tmp/craftsman-config-tests-$$"
mkdir -p "$TEST_DIR"
ORIGINAL_PWD="$PWD"
cd "$TEST_DIR"

# Clean env before each test section
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# =============================================================================
# 1. Default values (no config, no env vars)
# =============================================================================
echo ""
echo "=== Default Values ==="

# Ensure no config file and no env vars
rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

result=$(config_strictness)
if [[ "$result" == "strict" ]]; then
    log_pass "Default strictness is 'strict'"
else
    log_fail "Default strictness should be 'strict'" "got '$result'"
fi

result=$(config_stack)
if [[ "$result" == "fullstack" ]]; then
    log_pass "Default stack is 'fullstack'"
else
    log_fail "Default stack should be 'fullstack'" "got '$result'"
fi

# =============================================================================
# 2. CLAUDE_USER_CONFIG env var overrides defaults
# =============================================================================
echo ""
echo "=== Env Var Overrides ==="

rm -f "$TEST_DIR/.craft-config.yml"

export CLAUDE_USER_CONFIG_strictness="relaxed"
export CLAUDE_USER_CONFIG_stack="react"

result=$(config_strictness)
if [[ "$result" == "relaxed" ]]; then
    log_pass "CLAUDE_USER_CONFIG_strictness=relaxed overrides default"
else
    log_fail "Env var strictness override" "got '$result', expected 'relaxed'"
fi

result=$(config_stack)
if [[ "$result" == "react" ]]; then
    log_pass "CLAUDE_USER_CONFIG_stack=react overrides default"
else
    log_fail "Env var stack override" "got '$result', expected 'react'"
fi

unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# =============================================================================
# 3. .craft-config.yml overrides env var (highest priority)
# =============================================================================
echo ""
echo "=== .craft-config.yml Overrides Env Var ==="

export CLAUDE_USER_CONFIG_strictness="relaxed"
export CLAUDE_USER_CONFIG_stack="react"

cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
strictness: moderate
stack: symfony
YAML

result=$(config_strictness)
if [[ "$result" == "moderate" ]]; then
    log_pass ".craft-config.yml strictness overrides env var"
else
    log_fail ".craft-config.yml should override env var strictness" "got '$result', expected 'moderate'"
fi

result=$(config_stack)
if [[ "$result" == "symfony" ]]; then
    log_pass ".craft-config.yml stack overrides env var"
else
    log_fail ".craft-config.yml should override env var stack" "got '$result', expected 'symfony'"
fi

rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# =============================================================================
# 4. Stack helpers
# =============================================================================
echo ""
echo "=== Stack Helpers ==="

# stack=react: php disabled, ts enabled
export CLAUDE_USER_CONFIG_stack="react"
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
rm -f "$TEST_DIR/.craft-config.yml"

if ! config_php_enabled; then
    log_pass "config_php_enabled returns false for stack=react"
else
    log_fail "config_php_enabled should return false for react" "returned true"
fi

if config_ts_enabled; then
    log_pass "config_ts_enabled returns true for stack=react"
else
    log_fail "config_ts_enabled should return true for react" "returned false"
fi

# stack=symfony: php enabled, ts disabled
export CLAUDE_USER_CONFIG_stack="symfony"

if config_php_enabled; then
    log_pass "config_php_enabled returns true for stack=symfony"
else
    log_fail "config_php_enabled should return true for symfony" "returned false"
fi

if ! config_ts_enabled; then
    log_pass "config_ts_enabled returns false for stack=symfony"
else
    log_fail "config_ts_enabled should return false for symfony" "returned true"
fi

# stack=fullstack: both enabled
export CLAUDE_USER_CONFIG_stack="fullstack"

if config_php_enabled; then
    log_pass "config_php_enabled returns true for stack=fullstack"
else
    log_fail "config_php_enabled should return true for fullstack" "returned false"
fi

if config_ts_enabled; then
    log_pass "config_ts_enabled returns true for stack=fullstack"
else
    log_fail "config_ts_enabled should return true for fullstack" "returned false"
fi

# stack=other: both disabled
export CLAUDE_USER_CONFIG_stack="other"

if ! config_php_enabled; then
    log_pass "config_php_enabled returns false for stack=other"
else
    log_fail "config_php_enabled should return false for other" "returned true"
fi

if ! config_ts_enabled; then
    log_pass "config_ts_enabled returns false for stack=other"
else
    log_fail "config_ts_enabled should return false for other" "returned true"
fi

unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

# =============================================================================
# 5. Blocking behavior (config_should_block)
# =============================================================================
echo ""
echo "=== Blocking Behavior ==="

rm -f "$TEST_DIR/.craft-config.yml"

# strict: always block
export CLAUDE_USER_CONFIG_strictness="strict"
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true

if config_should_block "PHP001"; then
    log_pass "strict: blocks PHP001"
else
    log_fail "strict should block PHP001" "returned non-blocking"
fi

if config_should_block "TS001"; then
    log_pass "strict: blocks TS001"
else
    log_fail "strict should block TS001" "returned non-blocking"
fi

if config_should_block "LAYER001"; then
    log_pass "strict: blocks LAYER001"
else
    log_fail "strict should block LAYER001" "returned non-blocking"
fi

# moderate: only LAYER* rules block
export CLAUDE_USER_CONFIG_strictness="moderate"

if config_should_block "LAYER001"; then
    log_pass "moderate: blocks LAYER001"
else
    log_fail "moderate should block LAYER001" "returned non-blocking"
fi

if config_should_block "LAYER_VIOLATION"; then
    log_pass "moderate: blocks LAYER_VIOLATION"
else
    log_fail "moderate should block LAYER_VIOLATION" "returned non-blocking"
fi

if ! config_should_block "PHP001"; then
    log_pass "moderate: does NOT block PHP001 (warns only)"
else
    log_fail "moderate should not block PHP001" "returned blocking"
fi

if ! config_should_block "TS001"; then
    log_pass "moderate: does NOT block TS001 (warns only)"
else
    log_fail "moderate should not block TS001" "returned blocking"
fi

# relaxed: nothing blocks
export CLAUDE_USER_CONFIG_strictness="relaxed"

if ! config_should_block "PHP001"; then
    log_pass "relaxed: does NOT block PHP001"
else
    log_fail "relaxed should not block PHP001" "returned blocking"
fi

if ! config_should_block "LAYER001"; then
    log_pass "relaxed: does NOT block LAYER001"
else
    log_fail "relaxed should not block LAYER001" "returned blocking"
fi

if ! config_should_block "TS001"; then
    log_pass "relaxed: does NOT block TS001"
else
    log_fail "relaxed should not block TS001" "returned blocking"
fi

# =============================================================================
# Cleanup
# =============================================================================
cd "$ORIGINAL_PWD"
unset CLAUDE_USER_CONFIG_strictness 2>/dev/null || true
unset CLAUDE_USER_CONFIG_stack 2>/dev/null || true
rm -rf "$TEST_DIR"

echo ""
echo "==================================="
echo -e " ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e " ${RED}Failed:${NC} $TESTS_FAILED"
echo "==================================="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
