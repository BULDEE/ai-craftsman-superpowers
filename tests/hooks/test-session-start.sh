#!/usr/bin/env bash
# =============================================================================
# Session Start Hook Tests
# Tests dependency checking and auto-setup gate.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-session-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"

mkdir -p "$CLAUDE_PLUGIN_DATA"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

echo ""
echo "=== Session Start Hook Tests ==="

# Test: Hook outputs valid JSON
result=$(echo '{}' | bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
exit_code=$?
if [[ "$exit_code" == "0" ]]; then
    log_pass "Session start exits 0"
else
    log_fail "Session start should exit 0" "got exit $exit_code"
fi

# Test: Output is valid JSON with systemMessage
if echo "$result" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "Output contains systemMessage key"
else
    log_fail "Output should contain systemMessage" "got: $result"
fi

# Test: systemMessage contains Craftsman active
msg=$(echo "$result" | jq -r '.systemMessage' 2>/dev/null)
if [[ "$msg" == *"Craftsman active"* ]]; then
    log_pass "systemMessage contains 'Craftsman active'"
else
    log_fail "systemMessage should contain 'Craftsman active'" "got: $msg"
fi

# Test: Dependency check — all deps present means no warning
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v sqlite3 >/dev/null 2>&1; then
    if [[ "$msg" != *"MISSING"* ]]; then
        log_pass "No dependency warning when all deps present"
    else
        log_fail "Should not warn when all deps present" "got: $msg"
    fi
fi

# Test: Auto-setup gate warns when no config
ORIGINAL_HOME="$HOME"
export HOME="/tmp/craftsman-fake-home-$$"
mkdir -p "$HOME/.claude"
result2=$(echo '{}' | bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
msg2=$(echo "$result2" | jq -r '.systemMessage' 2>/dev/null)
if [[ "$msg2" == *"/craftsman:setup"* ]]; then
    log_pass "Auto-setup gate warns when no .craft-config.yml"
else
    log_fail "Should warn about missing config" "got: $msg2"
fi
export HOME="$ORIGINAL_HOME"

# Cleanup
rm -rf "$CLAUDE_PLUGIN_DATA" "/tmp/craftsman-fake-home-$$"

echo ""
echo "=== Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="

[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
