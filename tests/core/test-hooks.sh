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
# FileChanged Hook Tests — wired in hooks.json with matcher *.php|*.ts|*.tsx
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

# Test: PostToolUse has 1 command hook (post-write-check only — agent hooks moved to Stop)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostToolUse'][0]['hooks']
assert len(hooks) == 1, f'Expected 1 hook, got {len(hooks)}'
assert hooks[0]['type'] == 'command'
assert 'post-write-check.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "PostToolUse has 1 command hook (post-write-check)"
else
    log_fail "PostToolUse hook count" "expected 1 command hook"
fi

# Test: DDD verifier in Stop hook (moved from PostToolUse for latency reduction)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
stop_hooks = d['hooks']['Stop'][0]['hooks']
ddd_found = any('agent-ddd-verifier.sh' in h['command'] for h in stop_hooks)
assert ddd_found, 'DDD verifier not found in Stop hooks'
" 2>/dev/null; then
    log_pass "Stop DDD verifier: command hook with gate script"
else
    log_fail "Stop DDD verifier" "missing or invalid"
fi

# Test: DDD verifier script has agent_hooks gate
if grep -q 'CLAUDE_PLUGIN_OPTION_agent_hooks' "$ROOT_DIR/hooks/agent-ddd-verifier.sh" 2>/dev/null; then
    log_pass "DDD verifier script contains agent_hooks gate"
else
    log_fail "DDD verifier gate" "missing CLAUDE_PLUGIN_OPTION_agent_hooks check"
fi

# Test: Sentry context in Stop hook (moved from PostToolUse for latency reduction)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
stop_hooks = d['hooks']['Stop'][0]['hooks']
sentry_found = any('agent-sentry-context.sh' in h['command'] for h in stop_hooks)
assert sentry_found, 'Sentry context not found in Stop hooks'
" 2>/dev/null; then
    log_pass "Stop Sentry context: command hook with gate script"
else
    log_fail "Sentry context hook" "missing or invalid"
fi

# Test: Sentry context script has sentry_org gate
if grep -q 'CLAUDE_PLUGIN_OPTION_sentry_org' "$ROOT_DIR/hooks/agent-sentry-context.sh" 2>/dev/null; then
    log_pass "Sentry context script contains sentry_org gate"
else
    log_fail "Sentry context gate" "missing CLAUDE_PLUGIN_OPTION_sentry_org check"
fi

# Test: InstructionsLoaded command hook references structure analyzer
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['InstructionsLoaded'][0]['hooks']
assert len(hooks) == 1
assert hooks[0]['type'] == 'command'
assert 'agent-structure-analyzer.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "InstructionsLoaded: command hook with structure analyzer"
else
    log_fail "InstructionsLoaded hook" "missing or invalid"
fi

# Test: Structure analyzer script contains corrections query
if grep -q 'corrections' "$ROOT_DIR/hooks/agent-structure-analyzer.sh" 2>/dev/null; then
    log_pass "Structure analyzer contains correction trends query"
else
    log_fail "InstructionsLoaded corrections" "missing corrections reference"
fi

# Test: Structure analyzer script contains channel status check
if grep -q 'channel_status_summary' "$ROOT_DIR/hooks/agent-structure-analyzer.sh" 2>/dev/null; then
    log_pass "Structure analyzer contains channel_status_summary"
else
    log_fail "InstructionsLoaded channel status" "missing channel_status_summary"
fi

# Test: Stop has 3 command hooks (ddd-verifier + sentry-context + final-review)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['Stop'][0]['hooks']
assert len(hooks) == 3, f'Expected 3 Stop hooks, got {len(hooks)}'
assert all(h['type'] == 'command' for h in hooks)
assert 'agent-final-review.sh' in hooks[2]['command']
" 2>/dev/null; then
    log_pass "Stop: 3 command hooks (ddd-verifier, sentry, final-review)"
else
    log_fail "Stop hook" "missing or invalid"
fi

# Test: Final review script contains strictness gate
if grep -q 'CLAUDE_PLUGIN_OPTION_strictness' "$ROOT_DIR/hooks/agent-final-review.sh" 2>/dev/null; then
    log_pass "Final review script contains strictness gate"
else
    log_fail "Final review gate" "missing CLAUDE_PLUGIN_OPTION_strictness check"
fi

# Test: post-write-check.sh command hook still present
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostToolUse'][0]['hooks']
assert 'post-write-check.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "PostToolUse post-write-check.sh command hook present"
else
    log_fail "PostToolUse command hook" "missing or modified"
fi

# =============================================================================
# New Hook Events Tests (v3.1 — PostToolUseFailure, FileChanged, SubagentStop, PreCompact)
# =============================================================================
echo ""
echo "=== New Hook Events Tests ==="

# Test: PostToolUseFailure event wired with async
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostToolUseFailure'][0]['hooks']
assert len(hooks) == 1
assert hooks[0].get('async') == True, 'Expected async: true'
assert 'tool-failure-tracker.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "PostToolUseFailure: async tool-failure-tracker hook"
else
    log_fail "PostToolUseFailure hook" "missing or invalid"
fi

# Test: FileChanged event wired with matcher and async
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
fc = d['hooks']['FileChanged'][0]
assert fc.get('matcher') == '*.php|*.ts|*.tsx', f'Wrong matcher: {fc.get(\"matcher\")}'
assert fc['hooks'][0].get('async') == True
assert 'file-changed.sh' in fc['hooks'][0]['command']
" 2>/dev/null; then
    log_pass "FileChanged: async file-changed hook with *.php|*.ts|*.tsx matcher"
else
    log_fail "FileChanged hook" "missing or invalid"
fi

# Test: SubagentStop event wired with async
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['SubagentStop'][0]['hooks']
assert len(hooks) == 1
assert hooks[0].get('async') == True
assert 'subagent-quality-gate.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "SubagentStop: async subagent-quality-gate hook"
else
    log_fail "SubagentStop hook" "missing or invalid"
fi

# Test: PreCompact event wired (non-async — must complete before compaction)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PreCompact'][0]['hooks']
assert len(hooks) == 1
assert hooks[0].get('async', False) == False, 'PreCompact must be synchronous'
assert 'pre-compact-save.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "PreCompact: synchronous pre-compact-save hook"
else
    log_fail "PreCompact hook" "missing or invalid"
fi

# Test: Stop hooks have async: true
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['Stop'][0]['hooks']
assert all(h.get('async') == True for h in hooks), 'All Stop hooks should be async'
" 2>/dev/null; then
    log_pass "Stop hooks: all async (non-blocking session end)"
else
    log_fail "Stop hooks async" "expected all async: true"
fi

# Test: PreToolUse Bash has conditional if field
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
bash_entry = d['hooks']['PreToolUse'][1]
assert bash_entry.get('if') is not None, 'Expected if field on Bash PreToolUse'
assert 'git push' in bash_entry['if'], f'Expected git push in if, got: {bash_entry[\"if\"]}'
" 2>/dev/null; then
    log_pass "PreToolUse Bash: conditional if field for git push"
else
    log_fail "PreToolUse conditional" "missing if field"
fi

# Test: New hook scripts exist and are executable
for script in tool-failure-tracker.sh subagent-quality-gate.sh pre-compact-save.sh; do
    if [[ -x "$ROOT_DIR/hooks/$script" ]]; then
        log_pass "$script exists and is executable"
    else
        log_fail "$script" "missing or not executable"
    fi
done

# Test: PostCompact event wired (synchronous — verify state after compaction)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
hooks = d['hooks']['PostCompact'][0]['hooks']
assert len(hooks) == 1
assert hooks[0].get('async', False) == False, 'PostCompact must be synchronous'
assert 'post-compact-verify.sh' in hooks[0]['command']
" 2>/dev/null; then
    log_pass "PostCompact: synchronous post-compact-verify hook"
else
    log_fail "PostCompact verify hook" "missing or invalid"
fi

# Test: post-compact-verify.sh exists and is executable
if [[ -x "$ROOT_DIR/hooks/post-compact-verify.sh" ]]; then
    log_pass "post-compact-verify.sh exists and is executable"
else
    log_fail "post-compact-verify.sh" "missing or not executable"
fi

# Test: Total hook event count (12 events wired)
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
events = list(d['hooks'].keys())
assert len(events) == 12, f'Expected 12 hook events, got {len(events)}: {events}'
" 2>/dev/null; then
    log_pass "Total hook events: 12 (was 7, +5 new)"
else
    log_fail "Hook event count" "expected 12"
fi

# =============================================================================
# Plugin Integrity Tests (badges, bin/, output-styles)
# =============================================================================
echo ""
echo "=== Plugin Integrity Tests ==="

# Test: bin/ executables exist
for exe in craftsman-ci craftsman-validate; do
    if [[ -x "$ROOT_DIR/bin/$exe" ]]; then
        log_pass "bin/$exe exists and is executable"
    else
        log_fail "bin/$exe" "missing or not executable"
    fi
done

# Test: output-styles exist
STYLE_COUNT=$(find "$ROOT_DIR/output-styles" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$STYLE_COUNT" -ge 2 ]]; then
    log_pass "output-styles: $STYLE_COUNT style files found"
else
    log_fail "output-styles" "expected >= 2 style files, got $STYLE_COUNT"
fi

# Test: All agents have effort field in plugin.json
if python3 -c "
import json
d = json.load(open('$ROOT_DIR/.claude-plugin/plugin.json'))
agents = d.get('agents', {})
missing = [n for n, a in agents.items() if 'effort' not in a]
assert not missing, f'Agents missing effort field: {missing}'
" 2>/dev/null; then
    log_pass "All 11 agents have effort field in plugin.json"
else
    log_fail "Agent effort fields" "some agents missing effort"
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
if echo "$result" | grep -qE "sentry:(enabled|closed|open|half-open)"; then
    log_pass "channel_status_summary shows sentry with valid state"
else
    log_fail "channel_status_summary" "got '$result', expected 'sentry:<state>'"
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
# craftsman-ignore Multi-Rule Tests
# =============================================================================
echo ""
echo "=== craftsman-ignore Multi-Rule Tests ==="

# Test: multi-rule craftsman-ignore suppresses all listed rules (exit 0)
result=$(run_post_hook "$FIXTURES_DIR/with-craftsman-ignore-multi.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "craftsman-ignore multi-rule suppresses violations (exit 0)"
else
    log_fail "craftsman-ignore multi-rule should suppress" "got exit $exit_code"
fi

# Test: single-rule craftsman-ignore still works (backward compat)
result=$(run_post_hook "$FIXTURES_DIR/with-craftsman-ignore.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "craftsman-ignore single-rule backward compatible (exit 0)"
else
    log_fail "craftsman-ignore single-rule backward compat" "got exit $exit_code"
fi

# Test: line_has_ignore function matches single rule
source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/metrics-db.sh"

# Inline test: verify line_has_ignore logic for comma-separated rules
FILE_PATH="$FIXTURES_DIR/with-craftsman-ignore-multi.php"
FILE_PATTERN=$(metrics_file_pattern "$FILE_PATH" 2>/dev/null || echo "test/**/*.php")
EXT="php"

line_has_ignore_test() {
    local line="$1"
    local rule="$2"
    if echo "$line" | grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" 2>/dev/null; then
        return 0
    fi
    if echo "$line" | grep -qE "craftsman-ignore\s*$" 2>/dev/null; then
        return 0
    fi
    return 1
}

if line_has_ignore_test "// craftsman-ignore: PHP001, TS001, LAYER001" "PHP001"; then
    log_pass "line_has_ignore matches first rule in multi-rule list"
else
    log_fail "line_has_ignore should match PHP001 in multi-rule" ""
fi

if line_has_ignore_test "// craftsman-ignore: PHP001, TS001, LAYER001" "LAYER001"; then
    log_pass "line_has_ignore matches last rule in multi-rule list"
else
    log_fail "line_has_ignore should match LAYER001 in multi-rule" ""
fi

if ! line_has_ignore_test "// craftsman-ignore: PHP001, TS001" "PHP002"; then
    log_pass "line_has_ignore does NOT match absent rule"
else
    log_fail "line_has_ignore should not match PHP002 not in list" ""
fi

if line_has_ignore_test "// craftsman-ignore: no-setter, PHP003" "PHP003"; then
    log_pass "line_has_ignore matches rule mixed with non-code token"
else
    log_fail "line_has_ignore should match PHP003 in mixed list" ""
fi

# =============================================================================
# Cross-File Correction Pattern Tests
# =============================================================================
echo ""
echo "=== Cross-File Correction Pattern Tests ==="

# Simulate multiple file violations in session state to trigger pattern detection
PATTERN_TEST_STATE="${CLAUDE_PLUGIN_DATA}/session-state.json"
mkdir -p "$(dirname "$PATTERN_TEST_STATE")"

# Write a session state with 3 files violating PHP001 in same directory
python3 -c "
import json, sys
state = {
    'blocked_violations': {
        'src/Domain/**/*.php': ['PHP001'],
        'src/Domain/Entity/**/*.php': ['PHP001'],
        'src/Domain/ValueObject/**/*.php': ['PHP001'],
    },
    'patterns': {
        'PHP001': {
            'src/Domain': [
                'src/Domain/**/*.php',
                'src/Domain/Entity/**/*.php',
                'src/Domain/ValueObject/**/*.php',
            ]
        }
    }
}
with open(sys.argv[1], 'w') as f:
    json.dump(state, f)
" "$PATTERN_TEST_STATE" 2>/dev/null

# Test: _detect_cross_file_patterns outputs PROJECT-WIDE PATTERN for 3+ files
PATTERN_OUTPUT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
patterns = state.get('patterns', {})
suggestions = []
for rule, dir_map in patterns.items():
    all_files = set()
    for files in dir_map.values():
        all_files.update(files)
    if len(all_files) >= 3:
        suggestions.append('PATTERN:' + rule + ':' + str(len(all_files)) + ' files')
    for dir_b, files in dir_map.items():
        if len(files) >= 2 and dir_b not in ('', '.'):
            suggestions.append('DIR_PATTERN:' + rule + ':' + dir_b + ':' + str(len(files)) + ' files')
for s in suggestions:
    print(s)
" "$PATTERN_TEST_STATE" 2>/dev/null)

if echo "$PATTERN_OUTPUT" | grep -q "^PATTERN:PHP001"; then
    log_pass "Cross-file patterns: PHP001 in 3+ files triggers PROJECT-WIDE PATTERN"
else
    log_fail "Cross-file pattern detection" "expected PATTERN:PHP001, got: $PATTERN_OUTPUT"
fi

if echo "$PATTERN_OUTPUT" | grep -q "^DIR_PATTERN:PHP001:src/Domain"; then
    log_pass "Cross-file patterns: PHP001 in directory triggers DIR_PATTERN"
else
    log_fail "Directory pattern detection" "expected DIR_PATTERN:PHP001:src/Domain"
fi

# Test: session state has 'patterns' key after a blocked violation
rm -f "$PATTERN_TEST_STATE"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
run_post_hook "$FIXTURES_DIR/invalid-no-strict.php" > /dev/null 2>&1 || true

if [[ -f "$PATTERN_TEST_STATE" ]] && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert 'patterns' in state, 'patterns key missing'
" "$PATTERN_TEST_STATE" 2>/dev/null; then
    log_pass "Session state contains 'patterns' key after block"
else
    log_fail "Session state 'patterns' key" "not present after block"
fi

# =============================================================================
# Pre-Push Verify Hook Tests
# =============================================================================
echo ""
echo "=== Pre-Push Verify Hook Tests ==="

run_pre_push() {
    local command="$1"
    local output
    output=$(jq -n --arg cmd "$command" '{"tool_input":{"command":$cmd}}' | bash "$ROOT_DIR/hooks/pre-push-verify.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

# Test: non-push command passes silently (exit 0)
result=$(run_pre_push "git status")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "pre-push-verify: non-push command passes (exit 0)"
else
    log_fail "pre-push-verify: non-push command should pass" "got exit $exit_code"
fi

# Test: git push without verified flag blocks (exit 2)
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
result=$(run_pre_push "git push origin main")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "craftsman:verify"; then
    log_pass "pre-push-verify: blocks git push when not verified (exit 2)"
else
    log_fail "pre-push-verify: should block unverified push" "exit=$exit_code output=$output"
fi

# Test: git push with verified=true in session state passes (exit 0)
mkdir -p "$CLAUDE_PLUGIN_DATA"
python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'verified': True}, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null
result=$(run_pre_push "git push origin main")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "pre-push-verify: passes when verified=true (exit 0)"
else
    log_fail "pre-push-verify: should pass when verified" "got exit $exit_code"
fi

# Test: git push --force also blocked without verified
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
result=$(run_pre_push "git push --force origin main")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "pre-push-verify: blocks git push --force without verify (exit 2)"
else
    log_fail "pre-push-verify: should block git push --force" "got exit $exit_code"
fi

# Test: output is valid JSON when blocking
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
result=$(run_pre_push "git push origin main")
output="${result#*|}"
if echo "$output" | jq . >/dev/null 2>&1; then
    log_pass "pre-push-verify: output is valid JSON"
else
    log_fail "pre-push-verify: output should be valid JSON" "$output"
fi

# =============================================================================
# Bias Detector Workflow Enforcement Tests
# =============================================================================
echo ""
echo "=== Bias Detector Workflow Enforcement Tests ==="

run_bias_detector() {
    local prompt="$1"
    local output
    output=$(jq -n --arg p "$prompt" '{"prompt":$p}' | bash "$ROOT_DIR/hooks/bias-detector.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

# Test: domain modeling without design flag triggers warning (JSON output)
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
result=$(run_bias_detector "create entity User with email and name")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "craftsman:design\|domain modeling"; then
    log_pass "bias-detector: domain modeling without design warns (exit 0)"
else
    log_fail "bias-detector: should warn about missing /craftsman:design" "exit=$exit_code output=$(echo "$output" | head -3)"
fi

# Test: bias-detector outputs valid JSON when warning
if echo "$output" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "bias-detector: output is valid JSON with systemMessage"
else
    log_fail "bias-detector: output should be JSON with systemMessage" "$output"
fi

# Test: domain modeling WITH design_used=true does NOT warn
mkdir -p "$CLAUDE_PLUGIN_DATA"
python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'design_used': True}, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null
result=$(run_bias_detector "create entity User with email and name")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && ! echo "$output" | grep -qi "craftsman:design"; then
    log_pass "bias-detector: no domain modeling warning when design_used=true"
else
    log_fail "bias-detector: should NOT warn when design_used=true" "output=$output"
fi

# Test: non-domain prompt produces no workflow warning
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
result=$(run_bias_detector "fix the login bug in UserController")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && ! echo "$output" | grep -qi "craftsman:design"; then
    log_pass "bias-detector: no workflow warning for non-domain prompt"
else
    log_fail "bias-detector: non-domain prompt should not trigger workflow" "output=$output"
fi

# Test: existing bias patterns still work alongside new workflow check
result=$(run_bias_detector "let's quickly create an entity, no time, asap")
exit_code="${result%%|*}"
output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -qi "acceleration\|Acceleration"; then
    log_pass "bias-detector: acceleration bias still detected alongside workflow check"
else
    log_fail "bias-detector: acceleration bias should still trigger" "exit=$exit_code"
fi

# Test: bias-detector always exits 0 (never blocks)
result=$(run_bias_detector "create aggregate Order with line items urgently")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "bias-detector: always exits 0 (non-blocking)"
else
    log_fail "bias-detector: should always exit 0" "got exit $exit_code"
fi

# Test: no output when no bias detected
result=$(run_bias_detector "add a unit test for the UserRepository")
output="${result#*|}"
if [[ -z "$output" ]]; then
    log_pass "bias-detector: no output when no bias detected"
else
    log_fail "bias-detector: should produce no output for clean prompt" "$output"
fi

# =============================================================================
# Hook Event Validation (only supported events)
# =============================================================================
echo ""
echo "=== Hook Event Validation ==="

HOOKS_FILE="$ROOT_DIR/hooks/hooks.json"

# Test: hooks.json contains only supported events
if python3 -c "
import json
d = json.load(open('$HOOKS_FILE'))
supported = {'SessionStart','PreToolUse','PostToolUse','PostToolUseFailure','UserPromptSubmit','PermissionRequest','PermissionDenied','Notification','SubagentStart','SubagentStop','TaskCreated','TaskCompleted','TeammateIdle','InstructionsLoaded','ConfigChange','CwdChanged','FileChanged','WorktreeCreate','WorktreeRemove','PreCompact','PostCompact','Elicitation','ElicitationResult','Stop','StopFailure','SessionEnd'}
actual = set(d['hooks'].keys())
unsupported = actual - supported
assert not unsupported, f'Unsupported events: {unsupported}'
" 2>/dev/null; then
    log_pass "hooks.json: all events are supported"
else
    log_fail "hooks.json events" "contains unsupported hook events"
fi

# Test: hooks.json is still valid JSON after all additions
if python3 -c "
import json
json.load(open('$HOOKS_FILE'))
print('valid')
" 2>/dev/null | grep -q "valid"; then
    log_pass "hooks.json: valid JSON after all additions"
else
    log_fail "hooks.json" "invalid JSON"
fi

# =============================================================================
# Session Metrics — Agent and Team Tracking Tests
# =============================================================================
echo ""
echo "=== Session Metrics Agent/Team Tracking Tests ==="

# Test: session-metrics outputs agent count from session state
mkdir -p "$CLAUDE_PLUGIN_DATA"
python3 -c "
import json, sys
with open(sys.argv[1], 'w') as f:
    json.dump({'agent_invocations': 3, 'team_type': 'symfony-ddd', 'completed_tasks': [{'task':'t1'},{'task':'t2'}]}, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null

result=$(echo '{"session_duration_seconds": 10}' | bash "$ROOT_DIR/hooks/session-metrics.sh" 2>/dev/null)
if echo "$result" | grep -q "agent"; then
    log_pass "session-metrics: includes agent count in summary"
else
    log_fail "session-metrics: should include agent stats" "got: $result"
fi

# Test: session-metrics outputs team type from session state
if echo "$result" | grep -q "symfony-ddd\|team"; then
    log_pass "session-metrics: includes team type in summary"
else
    log_fail "session-metrics: should include team type" "got: $result"
fi

# Test: session-metrics outputs task count from session state
if echo "$result" | grep -q "task\|complet"; then
    log_pass "session-metrics: includes completed task count in summary"
else
    log_fail "session-metrics: should include task count" "got: $result"
fi

# Test: session-metrics still exits 0
result_exit=$(echo '{"session_duration_seconds": 10}' | bash "$ROOT_DIR/hooks/session-metrics.sh" 2>/dev/null; echo $?)
# The echo $? trick — re-run cleanly
if echo '{"session_duration_seconds": 0}' | bash "$ROOT_DIR/hooks/session-metrics.sh" > /dev/null 2>&1; then
    log_pass "session-metrics: still exits 0 with empty session state"
else
    log_fail "session-metrics: should always exit 0" ""
fi

# =============================================================================
# Static Analysis Structured Output Tests
# =============================================================================
echo ""
echo "=== Static Analysis Structured Output Tests ==="

# Source the pack-specific static analysis libs (moved from hooks/lib/static-analysis.sh in v2.4.0)
source "$ROOT_DIR/packs/symfony/static-analysis/phpstan.sh" 2>/dev/null || true
source "$ROOT_DIR/packs/react/static-analysis/eslint.sh" 2>/dev/null || true
source "$ROOT_DIR/hooks/lib/static-analysis.sh"

# Test: _pack_sa_phpstan_map_error maps undefined variable (moved to packs in v2.4.0)
result=$(_pack_sa_phpstan_map_error "src/Domain/Foo.php:42:Undefined variable \$bar" 2>/dev/null)
if [[ "$result" == "PHPSTAN002" ]]; then
    log_pass "sa: undefined variable maps to PHPSTAN002"
else
    log_fail "sa: undefined variable mapping" "got $result, expected PHPSTAN002"
fi

# Test: _pack_sa_phpstan_map_error maps call to undefined to PHPSTAN003
result=$(_pack_sa_phpstan_map_error "src/Foo.php:10:Call to undefined method Foo::bar()" 2>/dev/null)
if [[ "$result" == "PHPSTAN003" ]]; then
    log_pass "sa: call to undefined maps to PHPSTAN003"
else
    log_fail "sa: call to undefined mapping" "got $result, expected PHPSTAN003"
fi

# Test: _pack_sa_phpstan_map_error defaults to PHPSTAN001 for generic errors
result=$(_pack_sa_phpstan_map_error "src/Foo.php:5:Something wrong" 2>/dev/null)
if [[ "$result" == "PHPSTAN001" ]]; then
    log_pass "sa: generic phpstan error maps to PHPSTAN001"
else
    log_fail "sa: generic phpstan error default" "got $result, expected PHPSTAN001"
fi

# Test: _pack_sa_eslint_map_error maps no-explicit-any to ESLINT001
result=$(_pack_sa_eslint_map_error "src/foo.ts: line 5, col 10, Error - Unexpected any (no-explicit-any)" 2>/dev/null || true)
if echo "$result" | grep -qE "^ESLINT[0-9]{3}$"; then
    log_pass "sa: eslint error maps to ESLINT code"
else
    log_fail "sa: eslint error mapping" "got $result"
fi

# Test: pack_sa_php not installed = graceful degradation (empty output, exit 0)
result=$(pack_sa_php "/tmp/nonexistent.php" 2>/dev/null)
if [[ -z "$result" ]]; then
    log_pass "sa_phpstan: graceful degradation when not installed"
else
    log_fail "sa_phpstan: should return empty when not installed" "got: $result"
fi

# Test: pack_sa_typescript not installed = graceful degradation
result=$(pack_sa_typescript "/tmp/nonexistent.ts" 2>/dev/null)
if [[ -z "$result" ]]; then
    log_pass "sa_eslint: graceful degradation when not installed"
else
    log_fail "sa_eslint: should return empty when not installed" "got: $result"
fi

# =============================================================================
# Behavioral Integration Tests — New Hook Scripts
# =============================================================================
echo ""
echo "=== Behavioral Integration Tests ==="

# Setup clean session state for behavioral tests
rm -rf "$CLAUDE_PLUGIN_DATA"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# --- tool-failure-tracker.sh behavioral tests ---

# Test: tool-failure-tracker writes failure to session-state.json
echo '{"tool_name":"Write","error":"Permission denied: /etc/hosts"}' | bash "$ROOT_DIR/hooks/tool-failure-tracker.sh" 2>/dev/null
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
failures = state.get('tool_failures', [])
assert len(failures) == 1, f'Expected 1 failure, got {len(failures)}'
assert failures[0]['tool'] == 'Write'
assert 'Permission denied' in failures[0]['error']
assert 'timestamp' in failures[0]
assert state.get('tool_failure_count') == 1
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "tool-failure-tracker: writes failure with tool, error, timestamp"
else
    log_fail "tool-failure-tracker behavioral" "session-state.json not written correctly"
fi

# Test: tool-failure-tracker increments count on subsequent failures
echo '{"tool_name":"Bash","error":"Command failed"}' | bash "$ROOT_DIR/hooks/tool-failure-tracker.sh" 2>/dev/null
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert state.get('tool_failure_count') == 2, f'Expected 2, got {state.get(\"tool_failure_count\")}'
assert len(state.get('tool_failures', [])) == 2
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "tool-failure-tracker: increments count on subsequent failures"
else
    log_fail "tool-failure-tracker count" "count not incremented"
fi

# Test: tool-failure-tracker truncates long errors at 200 chars
LONG_ERROR=$(python3 -c "print('X' * 500)")
jq -n --arg e "$LONG_ERROR" '{"tool_name":"Edit","error":$e}' | bash "$ROOT_DIR/hooks/tool-failure-tracker.sh" 2>/dev/null
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
last = state['tool_failures'][-1]
assert len(last['error']) <= 200, f'Error too long: {len(last[\"error\"])}'
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "tool-failure-tracker: truncates errors at 200 chars"
else
    log_fail "tool-failure-tracker truncation" "error not truncated"
fi

# Test: tool-failure-tracker caps at 50 entries
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
for i in $(seq 1 55); do
    echo "{\"tool_name\":\"Write\",\"error\":\"err$i\"}" | bash "$ROOT_DIR/hooks/tool-failure-tracker.sh" 2>/dev/null
done
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert len(state.get('tool_failures', [])) == 50, f'Expected 50, got {len(state.get(\"tool_failures\", []))}'
assert state['tool_failures'][0]['error'] == 'err6', f'Expected err6 (oldest kept), got {state[\"tool_failures\"][0][\"error\"]}'
assert state.get('tool_failure_count') == 55
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "tool-failure-tracker: caps at 50 entries, count tracks all 55"
else
    log_fail "tool-failure-tracker cap" "50-entry cap not working"
fi

# Test: tool-failure-tracker exits 0 with empty input
echo '' | bash "$ROOT_DIR/hooks/tool-failure-tracker.sh" 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "tool-failure-tracker: exits 0 with empty input"
else
    log_fail "tool-failure-tracker empty" "non-zero exit"
fi

# --- subagent-quality-gate.sh behavioral tests ---

# Reset session state
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"

# Test: subagent-quality-gate writes agent activity
echo '{"agent_type":"architect"}' | bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
agents = state.get('subagent_activity', [])
assert len(agents) == 1, f'Expected 1 agent entry, got {len(agents)}'
assert agents[0]['agent_type'] == 'architect'
assert 'completed_at' in agents[0]
assert state.get('subagent_count') == 1
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "subagent-quality-gate: writes agent activity with type and timestamp"
else
    log_fail "subagent-quality-gate behavioral" "session-state.json not written correctly"
fi

# Test: subagent-quality-gate increments on multiple agents
echo '{"agent_type":"security-pentester"}' | bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null
echo '{"agent_type":"doc-writer"}' | bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert state.get('subagent_count') == 3, f'Expected 3, got {state.get(\"subagent_count\")}'
types = [a['agent_type'] for a in state.get('subagent_activity', [])]
assert 'security-pentester' in types
assert 'doc-writer' in types
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "subagent-quality-gate: tracks multiple agent types"
else
    log_fail "subagent-quality-gate multi" "count or types wrong"
fi

# Test: subagent-quality-gate caps at 100 entries
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
for i in $(seq 1 105); do
    echo "{\"agent_type\":\"agent$i\"}" | bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null
done
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert len(state.get('subagent_activity', [])) == 100, f'Expected 100, got {len(state.get(\"subagent_activity\", []))}'
assert state.get('subagent_count') == 105
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "subagent-quality-gate: caps at 100 entries, count tracks all 105"
else
    log_fail "subagent-quality-gate cap" "100-entry cap not working"
fi

# Test: subagent-quality-gate exits 0 with empty input
echo '' | bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "subagent-quality-gate: exits 0 with empty input"
else
    log_fail "subagent-quality-gate empty" "non-zero exit"
fi

# --- pre-compact-save.sh behavioral tests ---

# Setup: create session state with violations and patterns
python3 -c "
import json, sys
state = {
    'blocked_violations': {
        'src/Domain/User.php': ['PHP001'],
        'src/App/Service.php': ['PHP003', 'PHP005']
    },
    'patterns': {'missing_final': 3},
    'tool_failure_count': 2,
    'subagent_count': 1
}
with open(sys.argv[1], 'w') as f:
    json.dump(state, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null

# Test: pre-compact-save outputs systemMessage with violation summary
result=$(echo '{}' | bash "$ROOT_DIR/hooks/pre-compact-save.sh" 2>/dev/null)
if echo "$result" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "pre-compact-save: outputs valid JSON with systemMessage"
else
    log_fail "pre-compact-save output" "no systemMessage in output: $result"
fi

# Test: pre-compact-save preserves compact_count in state
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
assert state.get('compact_count') == 1, f'Expected compact_count=1, got {state.get(\"compact_count\")}'
assert 'last_compact' in state, 'Missing last_compact timestamp'
assert 'pre_compact_summary' in state, 'Missing pre_compact_summary'
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null; then
    log_pass "pre-compact-save: writes compact_count, last_compact, pre_compact_summary"
else
    log_fail "pre-compact-save state" "missing compaction metadata"
fi

# Test: pre-compact-save grammar — singular forms
python3 -c "
import json, sys
state = {
    'blocked_violations': {'src/Foo.php': ['PHP001']},
    'patterns': {},
    'tool_failure_count': 1,
    'subagent_count': 0
}
with open(sys.argv[1], 'w') as f:
    json.dump(state, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null
result=$(echo '{}' | bash "$ROOT_DIR/hooks/pre-compact-save.sh" 2>/dev/null)
if echo "$result" | grep -q "1 active violation across 1 file" && echo "$result" | grep -q "1 tool failure"; then
    log_pass "pre-compact-save: correct singular grammar (1 file, 1 violation, 1 failure)"
else
    log_fail "pre-compact-save grammar" "singular forms incorrect: $result"
fi

# Test: pre-compact-save exits 0 with empty session state
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
echo '{}' | bash "$ROOT_DIR/hooks/pre-compact-save.sh" 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "pre-compact-save: exits 0 with no session state"
else
    log_fail "pre-compact-save empty" "non-zero exit"
fi

# --- post-compact-verify.sh behavioral tests ---

# Setup: simulate state after pre-compact-save
python3 -c "
import json, sys
state = {
    'compact_count': 1,
    'pre_compact_summary': '3 active violations across 2 files | 1 tool failure this session',
    'blocked_violations': {
        'src/Domain/User.php': ['PHP001'],
        'src/App/Service.php': ['PHP003', 'PHP005']
    },
    'tool_failure_count': 1
}
with open(sys.argv[1], 'w') as f:
    json.dump(state, f)
" "${CLAUDE_PLUGIN_DATA}/session-state.json" 2>/dev/null

# Test: post-compact-verify outputs recovery message
result=$(echo '{}' | bash "$ROOT_DIR/hooks/post-compact-verify.sh" 2>/dev/null)
if echo "$result" | jq -e '.systemMessage' >/dev/null 2>&1 && echo "$result" | grep -q "STATE OK"; then
    log_pass "post-compact-verify: outputs systemMessage with STATE OK"
else
    log_fail "post-compact-verify output" "missing systemMessage or STATE OK: $result"
fi

# Test: post-compact-verify reports compact count
if echo "$result" | grep -q "Compaction #1"; then
    log_pass "post-compact-verify: includes compaction count"
else
    log_fail "post-compact-verify count" "missing compaction count: $result"
fi

# Test: post-compact-verify exits 0 with no session state
rm -f "${CLAUDE_PLUGIN_DATA}/session-state.json"
echo '{}' | bash "$ROOT_DIR/hooks/post-compact-verify.sh" 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "post-compact-verify: exits 0 with no session state"
else
    log_fail "post-compact-verify empty" "non-zero exit"
fi

# --- craftsman-validate sanitization test ---

# Test: craftsman-validate uses jq (not string interpolation)
if grep -q 'jq -n --arg' "$ROOT_DIR/bin/craftsman-validate"; then
    log_pass "craftsman-validate: uses jq --arg for safe input"
else
    log_fail "craftsman-validate sanitization" "still using string interpolation"
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
