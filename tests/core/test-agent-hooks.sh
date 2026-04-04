#!/usr/bin/env bash
# =============================================================================
# Agent Hook Tests — validates gate logic and output for all agent hook scripts
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

for script in agent-ddd-verifier.sh agent-sentry-context.sh agent-final-review.sh agent-structure-analyzer.sh; do
    EXIT_CODE=0
    echo '{"tool_input":{"file_path":"/nonexistent/file.php"}}' | \
        CLAUDE_PLUGIN_OPTION_agent_hooks=true \
        CLAUDE_PLUGIN_OPTION_sentry_org="test" \
        CLAUDE_PLUGIN_OPTION_strictness=strict \
        bash "$ROOT_DIR/hooks/$script" >/dev/null 2>&1 || EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 0 ]]; then
        log_pass "$script: exits 0 on nonexistent file (non-blocking)"
    else
        log_fail "$script non-blocking" "expected exit 0, got $EXIT_CODE"
    fi
done

# Cleanup
rm -rf "/tmp/craftsman-agent-test-$$"

test_summary
