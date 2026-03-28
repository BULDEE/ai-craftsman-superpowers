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
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# =============================================================================
# 1. Default values (no config, no env vars)
# =============================================================================
echo ""
echo "=== Default Values ==="

# Ensure no config file and no env vars
rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

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
# 2. CLAUDE_PLUGIN_OPTION env var overrides defaults
# =============================================================================
echo ""
echo "=== Env Var Overrides ==="

rm -f "$TEST_DIR/.craft-config.yml"

export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
export CLAUDE_PLUGIN_OPTION_stack="react"

result=$(config_strictness)
if [[ "$result" == "relaxed" ]]; then
    log_pass "CLAUDE_PLUGIN_OPTION_strictness=relaxed overrides default"
else
    log_fail "Env var strictness override" "got '$result', expected 'relaxed'"
fi

result=$(config_stack)
if [[ "$result" == "react" ]]; then
    log_pass "CLAUDE_PLUGIN_OPTION_stack=react overrides default"
else
    log_fail "Env var stack override" "got '$result', expected 'react'"
fi

unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# =============================================================================
# 3. .craft-config.yml overrides env var (highest priority)
# =============================================================================
echo ""
echo "=== .craft-config.yml Overrides Env Var ==="

export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
export CLAUDE_PLUGIN_OPTION_stack="react"

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
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# =============================================================================
# 4. Stack helpers
# =============================================================================
echo ""
echo "=== Stack Helpers ==="

# stack=react: php disabled, ts enabled
export CLAUDE_PLUGIN_OPTION_stack="react"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
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
export CLAUDE_PLUGIN_OPTION_stack="symfony"

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
export CLAUDE_PLUGIN_OPTION_stack="fullstack"

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
export CLAUDE_PLUGIN_OPTION_stack="other"

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

unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# =============================================================================
# 5. Blocking behavior (config_should_block)
# =============================================================================
echo ""
echo "=== Blocking Behavior ==="

rm -f "$TEST_DIR/.craft-config.yml"

# strict: always block
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

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
export CLAUDE_PLUGIN_OPTION_strictness="moderate"

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
export CLAUDE_PLUGIN_OPTION_strictness="relaxed"

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

# WARN rules never block, even in strict
cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
strictness: strict
YAML

if ! config_should_block "WARN-PHP001"; then
    log_pass "strict: WARN-PHP001 does NOT block (warnings never block)"
else
    log_fail "strict: WARN-PHP001 should NOT block" ""
fi

if ! config_should_block "PHP005"; then
    log_pass "strict: PHP005 does NOT block (warnings never block)"
else
    log_fail "strict: PHP005 should NOT block" ""
fi

rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

# =============================================================================
# 6. Stop review enabled (config_stop_review_enabled)
# =============================================================================
echo ""
echo "=== Stop Review Enabled ==="

rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# strict: stop review enabled
export CLAUDE_PLUGIN_OPTION_strictness="strict"

if config_stop_review_enabled; then
    log_pass "strict: stop review enabled"
else
    log_fail "strict: stop review should be enabled" "returned false"
fi

# moderate: stop review disabled
export CLAUDE_PLUGIN_OPTION_strictness="moderate"

if ! config_stop_review_enabled; then
    log_pass "moderate: stop review disabled"
else
    log_fail "moderate: stop review should be disabled" "returned true"
fi

# relaxed: stop review disabled
export CLAUDE_PLUGIN_OPTION_strictness="relaxed"

if ! config_stop_review_enabled; then
    log_pass "relaxed: stop review disabled"
else
    log_fail "relaxed: stop review should be disabled" "returned true"
fi

# default (no env var): strict → enabled
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

if config_stop_review_enabled; then
    log_pass "default (strict): stop review enabled"
else
    log_fail "default should enable stop review" "returned false"
fi

unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

# =============================================================================
# 7. Sentry config (config_sentry_org, config_sentry_project, config_sentry_enabled)
# =============================================================================
echo ""
echo "=== Sentry Config ==="

rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true

# Default: empty (opt-in)
result=$(config_sentry_org)
if [[ -z "$result" ]]; then
    log_pass "Default sentry_org is empty"
else
    log_fail "Default sentry_org should be empty" "got '$result'"
fi

result=$(config_sentry_project)
if [[ -z "$result" ]]; then
    log_pass "Default sentry_project is empty"
else
    log_fail "Default sentry_project should be empty" "got '$result'"
fi

# Not enabled when both empty
if ! config_sentry_enabled; then
    log_pass "config_sentry_enabled returns false when both empty"
else
    log_fail "config_sentry_enabled should be false" "returned true"
fi

# Not enabled when only org set
export CLAUDE_PLUGIN_OPTION_sentry_org="my-org"
if ! config_sentry_enabled; then
    log_pass "config_sentry_enabled returns false when only org set"
else
    log_fail "config_sentry_enabled should be false (no project)" "returned true"
fi

# Not enabled when only project set
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
export CLAUDE_PLUGIN_OPTION_sentry_project="my-project"
if ! config_sentry_enabled; then
    log_pass "config_sentry_enabled returns false when only project set"
else
    log_fail "config_sentry_enabled should be false (no org)" "returned true"
fi

# Enabled when both set via env vars
export CLAUDE_PLUGIN_OPTION_sentry_org="my-org"
export CLAUDE_PLUGIN_OPTION_sentry_project="my-project"
if config_sentry_enabled; then
    log_pass "config_sentry_enabled returns true when both set"
else
    log_fail "config_sentry_enabled should be true" "returned false"
fi

result=$(config_sentry_org)
if [[ "$result" == "my-org" ]]; then
    log_pass "config_sentry_org reads env var"
else
    log_fail "config_sentry_org env var" "got '$result'"
fi

result=$(config_sentry_project)
if [[ "$result" == "my-project" ]]; then
    log_pass "config_sentry_project reads env var"
else
    log_fail "config_sentry_project env var" "got '$result'"
fi

# .craft-config.yml overrides env var
cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
sentry_org: yml-org
sentry_project: yml-project
YAML

result=$(config_sentry_org)
if [[ "$result" == "yml-org" ]]; then
    log_pass "config_sentry_org reads .craft-config.yml"
else
    log_fail "config_sentry_org yml override" "got '$result'"
fi

result=$(config_sentry_project)
if [[ "$result" == "yml-project" ]]; then
    log_pass "config_sentry_project reads .craft-config.yml"
else
    log_fail "config_sentry_project yml override" "got '$result'"
fi

rm -f "$TEST_DIR/.craft-config.yml"
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true

# =============================================================================
# Cleanup
# =============================================================================
cd "$ORIGINAL_PWD"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true
rm -rf "$TEST_DIR"

echo ""
echo "==================================="
echo -e " ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e " ${RED}Failed:${NC} $TESTS_FAILED"
echo "==================================="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
