#!/usr/bin/env bash
# =============================================================================
# Agent Hook Tests - validates gate logic and output for all agent hook scripts
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Agent Hook Gate Tests ==="

# --- DDD Verifier ---

# Test: DDD verifier skips when agent_hooks=false
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=false bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "ddd-verifier: skips when agent_hooks=false (exit 0)"
else
    log_fail "ddd-verifier gate" "expected exit 0, got $EXIT_CODE"
fi

# Test: DDD verifier skips on empty stdin
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=true bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "ddd-verifier: exits 0 on empty file_path"
else
    log_fail "ddd-verifier empty input" "expected exit 0, got $EXIT_CODE"
fi

# --- Sentry Context ---

# Test: Sentry context skips when agent_hooks=false
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=false bash "$ROOT_DIR/hooks/agent-sentry-context.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "sentry-context: skips when agent_hooks=false (exit 0)"
else
    log_fail "sentry-context gate" "expected exit 0, got $EXIT_CODE"
fi

# Test: Sentry context skips when sentry_org not set
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=true CLAUDE_PLUGIN_OPTION_sentry_org="" bash "$ROOT_DIR/hooks/agent-sentry-context.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "sentry-context: skips when sentry_org empty (exit 0)"
else
    log_fail "sentry-context sentry gate" "expected exit 0, got $EXIT_CODE"
fi

# --- Final Review ---

# Test: Final review skips when agent_hooks=false
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=false bash "$ROOT_DIR/hooks/agent-final-review.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "final-review: skips when agent_hooks=false (exit 0)"
else
    log_fail "final-review gate" "expected exit 0, got $EXIT_CODE"
fi

# Test: Final review skips when strictness=relaxed
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=true CLAUDE_PLUGIN_OPTION_strictness=relaxed bash "$ROOT_DIR/hooks/agent-final-review.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "final-review: skips when strictness=relaxed (exit 0)"
else
    log_fail "final-review strictness gate" "expected exit 0, got $EXIT_CODE"
fi

# --- Structure Analyzer ---

# Test: Structure analyzer skips when agent_hooks=false
EXIT_CODE=0
echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=false bash "$ROOT_DIR/hooks/agent-structure-analyzer.sh" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "structure-analyzer: skips when agent_hooks=false (exit 0)"
else
    log_fail "structure-analyzer gate" "expected exit 0, got $EXIT_CODE"
fi

# Test: Structure analyzer runs (exits 0) with agent_hooks=true
EXIT_CODE=0
OUTPUT=$(echo '{}' | CLAUDE_PLUGIN_OPTION_agent_hooks=true CLAUDE_PLUGIN_DATA="/tmp/craftsman-agent-test-$$" bash "$ROOT_DIR/hooks/agent-structure-analyzer.sh" 2>/dev/null) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "structure-analyzer: exits 0 with agent_hooks=true"
else
    log_fail "structure-analyzer run" "expected exit 0, got $EXIT_CODE"
fi

# --- All agent hooks must always exit 0 (non-blocking) ---
echo ""
echo "=== Agent Hook Non-Blocking Tests ==="

# Run from a non-git tmp dir so agent-final-review's git diff is empty and
# no headless Haiku subprocess is ever spawned from the test suite.
NONGIT_DIR="/tmp/craftsman-agent-nongit-$$"
mkdir -p "$NONGIT_DIR"

for script in agent-ddd-verifier.sh agent-sentry-context.sh agent-final-review.sh agent-structure-analyzer.sh; do
    EXIT_CODE=0
    echo '{"tool_input":{"file_path":"/nonexistent/file.php"}}' | \
        CLAUDE_PLUGIN_OPTION_agent_hooks=true \
        CLAUDE_PLUGIN_OPTION_sentry_org="test" \
        CLAUDE_PLUGIN_OPTION_strictness=strict \
        GIT_DIR="$NONGIT_DIR/.git-nonexistent" \
        bash "$ROOT_DIR/hooks/$script" >/dev/null 2>&1 || EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 0 ]]; then
        log_pass "$script: exits 0 on nonexistent file (non-blocking)"
    else
        log_fail "$script non-blocking" "expected exit 0, got $EXIT_CODE"
    fi
done

# --- v4 headless verification guards (ADR-0018) ---
echo ""
echo "=== Headless Verification Guard Tests ==="

# Recursion guard: a verification subprocess must never verify again
TMP_PHP="/tmp/craftsman-agent-test-$$.php"
printf '<?php\nclass Foo {}\n' > "$TMP_PHP"
EXIT_CODE=0
OUTPUT=$(echo "{\"tool_input\":{\"file_path\":\"$TMP_PHP\"}}" | \
    CRAFTSMAN_HEADLESS_VERIFY=1 \
    CLAUDE_PLUGIN_OPTION_agent_hooks=true \
    bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 && -z "$OUTPUT" ]]; then
    log_pass "ddd-verifier: recursion guard short-circuits (silent exit 0)"
else
    log_fail "ddd-verifier recursion guard" "exit=$EXIT_CODE output='$OUTPUT'"
fi
rm -f "$TMP_PHP"

# Auto-fix: Write of a PHP class missing only strict_types gets updatedInput
AUTOFIX_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/Foo.php","content":"<?php\n\nfinal class Foo\n{\n}\n"}}'
OUTPUT=$(echo "$AUTOFIX_INPUT" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>/dev/null)
if echo "$OUTPUT" | jq -e '.hookSpecificOutput.permissionDecision == "allow" and (.hookSpecificOutput.updatedInput.content | contains("declare(strict_types=1);"))' >/dev/null 2>&1; then
    log_pass "pre-write-check: PHP001 auto-fixed via updatedInput"
else
    log_fail "pre-write-check auto-fix" "no updatedInput with strict_types: $OUTPUT"
fi

# No auto-fix when strict_types already present
CLEAN_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x/Foo.php","content":"<?php\n\ndeclare(strict_types=1);\n\nfinal class Foo\n{\n}\n"}}'
OUTPUT=$(echo "$CLEAN_INPUT" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>/dev/null)
if [[ -z "$OUTPUT" ]] || ! echo "$OUTPUT" | grep -q "updatedInput"; then
    log_pass "pre-write-check: clean file passes untouched"
else
    log_fail "pre-write-check clean file" "unexpected rewrite: $OUTPUT"
fi

# Cleanup
rm -rf "/tmp/craftsman-agent-test-$$" "$NONGIT_DIR"

test_summary
