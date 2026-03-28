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
export CLAUDE_PLUGIN_OPTION_stack="react"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "stack=react skips PHP rules (exit 0 on PHP file)"
else
    log_fail "stack=react should skip PHP rules" "got exit $exit_code"
fi
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: stack=symfony skips TS rules
export CLAUDE_PLUGIN_OPTION_stack="symfony"
result=$(run_post_hook "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "stack=symfony skips TS rules (exit 0 on TS file)"
else
    log_fail "stack=symfony should skip TS rules" "got exit $exit_code"
fi
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: strictness=relaxed warns instead of blocking
export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "strictness=relaxed warns PHP001 (exit 0)"
else
    log_fail "strictness=relaxed should warn not block" "got exit $exit_code"
fi
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

# Test: strictness=moderate blocks LAYER but warns PHP001
export CLAUDE_PLUGIN_OPTION_strictness="moderate"
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
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

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
export CLAUDE_PLUGIN_OPTION_stack="react"
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write: stack=react skips PHP layer checks (exit 0)"
else
    log_fail "Pre-write: stack=react should skip PHP" "got exit $exit_code"
fi
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: strictness=relaxed warns instead of blocking layer violations
export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
result=$(run_pre_hook "src/Domain/Service/UserService.php" "<?php\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Pre-write: strictness=relaxed warns layer violation (exit 0)"
else
    log_fail "Pre-write: strictness=relaxed should warn" "got exit $exit_code"
fi
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

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
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

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
# FileChanged Hook Tests
# =============================================================================
echo ""
echo "=== FileChanged Hook Tests ==="

run_file_changed() {
    local file_path="$1"
    local output
    output=$(jq -n --arg fp "$file_path" '{"file_path":$fp}' | bash "$ROOT_DIR/hooks/file-changed.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

# Clear env
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: Ignores non-PHP/TS files
result=$(run_file_changed "$ROOT_DIR/tests/run-tests.sh")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" ]]; then
    log_pass "FileChanged ignores non-PHP/TS files (silent exit 0)"
else
    log_fail "FileChanged should ignore non-source files" "exit=$exit_code output=$output"
fi

# Test: Detects PHP violations (non-blocking)
result=$(run_file_changed "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "PHP001"; then
    log_pass "FileChanged detects PHP001 (non-blocking, exit 0)"
else
    log_fail "FileChanged should detect PHP001" "exit=$exit_code"
fi

# Test: Detects TS violations (non-blocking)
result=$(run_file_changed "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "TS001"; then
    log_pass "FileChanged detects TS001 (non-blocking, exit 0)"
else
    log_fail "FileChanged should detect TS001" "exit=$exit_code"
fi

# Test: Silent when file is clean
result=$(run_file_changed "$FIXTURES_DIR/valid-entity.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" ]]; then
    log_pass "FileChanged silent on clean file"
else
    log_fail "FileChanged should be silent on clean file" "output=$output"
fi

# Test: Respects stack config
export CLAUDE_PLUGIN_OPTION_stack="react"
result=$(run_file_changed "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" ]]; then
    log_pass "FileChanged respects stack=react (skips PHP)"
else
    log_fail "FileChanged should skip PHP for stack=react" "output=$output"
fi
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: Respects stack config (skips TS when stack=symfony)
export CLAUDE_PLUGIN_OPTION_stack="symfony"
result=$(run_file_changed "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && [[ -z "$output" ]]; then
    log_pass "FileChanged respects stack=symfony (skips TS)"
else
    log_fail "FileChanged should skip TS for stack=symfony" "output=$output"
fi
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Test: Always non-blocking (exit 0)
result=$(run_file_changed "$FIXTURES_DIR/invalid-layer-violation.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "FileChanged always exits 0 (even on LAYER violations)"
else
    log_fail "FileChanged should always exit 0" "got exit $exit_code"
fi

# =============================================================================
# Agent Hook Schema Tests
# =============================================================================
echo ""
echo "=== Agent Hook Schema Tests ==="

HOOKS_FILE="$ROOT_DIR/hooks/hooks.json"

# Test: PostToolUse has 3 hooks (command + 2 agents)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostToolUse'][0]['hooks']
assert len(hooks) == 3, f'Expected 3 hooks, got {len(hooks)}'
assert hooks[0]['type'] == 'command'
assert hooks[1]['type'] == 'agent'
assert hooks[2]['type'] == 'agent'
" 2>/dev/null; then
    log_pass "PostToolUse has 3 hooks (command + 2 agents)"
else
    log_fail "PostToolUse hook count" "expected 3 hooks"
fi

# Test: DDD verifier agent hook valid
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
ddd_hook = d['hooks']['PostToolUse'][0]['hooks'][1]
assert ddd_hook['type'] == 'agent'
assert 'prompt' in ddd_hook
assert ddd_hook['model'] == 'haiku'
assert ddd_hook['timeout'] == 30
assert '\$ARGUMENTS' in ddd_hook['prompt']
" 2>/dev/null; then
    log_pass "PostToolUse DDD agent hook: valid schema (type, prompt, model, timeout)"
else
    log_fail "PostToolUse DDD agent hook schema" "missing or invalid"
fi

# Test: Sentry agent hook valid
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
sentry_hook = d['hooks']['PostToolUse'][0]['hooks'][2]
assert sentry_hook['type'] == 'agent'
assert sentry_hook['model'] == 'haiku'
assert sentry_hook['timeout'] == 30
assert 'Sentry' in sentry_hook['prompt']
assert '\$ARGUMENTS' in sentry_hook['prompt']
assert 'CLAUDE_PLUGIN_OPTION_sentry_org' in sentry_hook['prompt']
" 2>/dev/null; then
    log_pass "PostToolUse Sentry agent hook: valid schema (haiku, 30s, org check)"
else
    log_fail "Sentry agent hook" "missing or invalid"
fi

# Test: InstructionsLoaded agent hook
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['InstructionsLoaded'][0]['hooks']
agent = [h for h in hooks if h.get('type') == 'agent']
assert len(agent) == 1
assert agent[0]['model'] == 'haiku'
assert agent[0]['timeout'] == 20
" 2>/dev/null; then
    log_pass "InstructionsLoaded agent hook: valid schema (haiku, 20s timeout)"
else
    log_fail "InstructionsLoaded agent hook schema" "missing or invalid"
fi

# Test: InstructionsLoaded prompt contains correction trends query
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
prompt = d['hooks']['InstructionsLoaded'][0]['hooks'][0]['prompt']
assert 'corrections' in prompt.lower(), 'Missing corrections reference'
assert 'sqlite3' in prompt, 'Missing sqlite3 query'
" 2>/dev/null; then
    log_pass "InstructionsLoaded prompt contains correction trends query"
else
    log_fail "InstructionsLoaded corrections" "missing sqlite3 or corrections reference"
fi

# Test: InstructionsLoaded prompt contains channel status check
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
prompt = d['hooks']['InstructionsLoaded'][0]['hooks'][0]['prompt']
assert 'channel_status_summary' in prompt, 'Missing channel_status_summary'
" 2>/dev/null; then
    log_pass "InstructionsLoaded prompt contains channel_status_summary"
else
    log_fail "InstructionsLoaded channel status" "missing channel_status_summary"
fi

# Test: Stop agent hook
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['Stop'][0]['hooks']
agent = [h for h in hooks if h.get('type') == 'agent']
assert len(agent) == 1
assert agent[0]['model'] == 'haiku'
assert agent[0]['timeout'] == 30
" 2>/dev/null; then
    log_pass "Stop agent hook: valid schema (haiku, 30s timeout)"
else
    log_fail "Stop agent hook schema" "missing or invalid"
fi

# Test: Stop agent prompt contains strictness gate
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['Stop'][0]['hooks']
agent = [h for h in hooks if h.get('type') == 'agent'][0]
assert 'CLAUDE_PLUGIN_OPTION_strictness' in agent['prompt']
" 2>/dev/null; then
    log_pass "Stop agent prompt contains strictness gate"
else
    log_fail "Stop agent prompt" "missing CLAUDE_PLUGIN_OPTION_strictness gate"
fi

# Test: Existing command hooks still present
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostToolUse'][0]['hooks']
cmd = [h for h in hooks if h.get('type') == 'command']
assert len(cmd) == 1, 'Command hook missing'
assert 'post-write-check.sh' in cmd[0]['command']
" 2>/dev/null; then
    log_pass "PostToolUse command hook preserved alongside agent hook"
else
    log_fail "PostToolUse command hook" "missing or modified"
fi

# =============================================================================
# Channel Lifecycle Tests
# =============================================================================
echo ""
echo "=== Channel Lifecycle Tests ==="

source "$ROOT_DIR/hooks/lib/channels.sh" 2>/dev/null

# Test: channel_available "sentry" returns false when not configured
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true
if ! channel_available "sentry"; then
    log_pass "channel_available 'sentry' false when not configured"
else
    log_fail "channel_available should be false" "returned true"
fi

# Test: channel_available "sentry" returns true when configured
export CLAUDE_PLUGIN_OPTION_sentry_org="test-org"
export CLAUDE_PLUGIN_OPTION_sentry_project="test-project"
if channel_available "sentry"; then
    log_pass "channel_available 'sentry' true when configured"
else
    log_fail "channel_available should be true" "returned false"
fi

# Test: channel_available "unknown" returns false
if ! channel_available "unknown"; then
    log_pass "channel_available 'unknown' returns false"
else
    log_fail "channel_available 'unknown'" "returned true"
fi

# Test: channel_status_summary empty when no channels
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true
result=$(channel_status_summary)
if [[ -z "$(echo "$result" | tr -d ' ')" ]]; then
    log_pass "channel_status_summary empty when no channels active"
else
    log_fail "channel_status_summary should be empty" "got '$result'"
fi

# Test: channel_status_summary shows sentry when configured
export CLAUDE_PLUGIN_OPTION_sentry_org="test-org"
export CLAUDE_PLUGIN_OPTION_sentry_project="test-project"
result=$(channel_status_summary)
if echo "$result" | grep -q "sentry:enabled"; then
    log_pass "channel_status_summary shows 'sentry:enabled'"
else
    log_fail "channel_status_summary" "got '$result', expected 'sentry:enabled'"
fi

unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true

# =============================================================================
# Correction Learning Tests
# =============================================================================
echo ""
echo "=== Correction Learning Tests ==="

source "$ROOT_DIR/hooks/lib/metrics-db.sh"
metrics_init 2>/dev/null || true

# Test: corrections table exists after init
if sqlite3 "$METRICS_DB" ".tables" 2>/dev/null | grep -q "corrections"; then
    log_pass "corrections table created by metrics_init"
else
    log_fail "corrections table" "not created"
fi

# Test: metrics_record_correction writes to DB
metrics_record_correction "PHP002" "src/Domain/**/*.php" "fixed" "removed public setter" 2>/dev/null
CORR_COUNT=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM corrections;" 2>/dev/null || echo 0)
if [[ "$CORR_COUNT" -ge 1 ]]; then
    log_pass "metrics_record_correction writes to corrections table"
else
    log_fail "metrics_record_correction" "no rows inserted"
fi

# Test: metrics_record_correction stores correct action
ACTION=$(sqlite3 "$METRICS_DB" "SELECT action FROM corrections ORDER BY id DESC LIMIT 1;" 2>/dev/null)
if [[ "$ACTION" == "fixed" ]]; then
    log_pass "metrics_record_correction stores action='fixed'"
else
    log_fail "correction action" "got '$ACTION', expected 'fixed'"
fi

# Test: metrics_record_correction handles 'ignored' action
metrics_record_correction "TS003" "src/**/*.ts" "ignored" "craftsman-ignore added" 2>/dev/null
ACTION=$(sqlite3 "$METRICS_DB" "SELECT action FROM corrections WHERE rule='TS003' LIMIT 1;" 2>/dev/null)
if [[ "$ACTION" == "ignored" ]]; then
    log_pass "metrics_record_correction stores action='ignored'"
else
    log_fail "correction ignored action" "got '$ACTION'"
fi

# Test: metrics_corrections_30d returns summary
SUMMARY=$(metrics_corrections_30d 2>/dev/null)
if echo "$SUMMARY" | grep -q "PHP002"; then
    log_pass "metrics_corrections_30d includes PHP002 in summary"
else
    log_fail "metrics_corrections_30d" "missing PHP002"
fi

# =============================================================================
# Session State & Correction Detection Tests
# =============================================================================
echo ""
echo "=== Session State & Correction Detection Tests ==="

SESSION_STATE="${CLAUDE_PLUGIN_DATA}/session-state.json"

# Test: Session state file created when violation blocks
rm -f "$SESSION_STATE"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
result=$(run_post_hook "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]] && [[ -f "$SESSION_STATE" ]]; then
    log_pass "Session state file created on block"
else
    log_fail "Session state file" "exit=$exit_code, file exists=$(test -f "$SESSION_STATE" && echo yes || echo no)"
fi

# Test: Session state contains the blocked rule
if [[ -f "$SESSION_STATE" ]] && python3 -c "
import json
d = json.load(open('$SESSION_STATE'))
bv = d.get('blocked_violations', {})
found = any('PHP001' in rules for rules in bv.values())
assert found, 'PHP001 not in blocked_violations'
" 2>/dev/null; then
    log_pass "Session state records PHP001 for blocked file"
else
    log_fail "Session state content" "PHP001 not recorded"
fi

# Test: Session state cleared at SessionEnd
echo '{"session_duration_seconds": 10}' | bash "$ROOT_DIR/hooks/session-metrics.sh" 2>/dev/null
if [[ ! -f "$SESSION_STATE" ]]; then
    log_pass "Session state cleared at SessionEnd"
else
    log_fail "Session state should be cleared at SessionEnd" "file still exists"
fi

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
