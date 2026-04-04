#!/usr/bin/env bash
# =============================================================================
# Tests for routing table library
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-test-rt-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"
pack_loader_init 2>/dev/null || true

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; (( TESTS_PASSED++ )); }
log_fail() { echo "  ✗ $1"; (( TESTS_FAILED++ )); }

echo "=== Routing Table Tests ==="

source "$ROOT_DIR/hooks/lib/routing-table.sh"

# Test: routing_table produces output
output=$(routing_table)
if [[ -n "$output" ]]; then
    log_pass "routing_table produces non-empty output"
else
    log_fail "routing_table should produce output"
fi

# Test: output contains CRAFTSMAN COMMANDS header
if echo "$output" | grep -q "CRAFTSMAN COMMANDS"; then
    log_pass "output contains CRAFTSMAN COMMANDS header"
else
    log_fail "output should contain CRAFTSMAN COMMANDS header"
fi

# Test: core commands always present
for cmd in debug team design spec plan challenge refactor git healthcheck verify; do
    if echo "$output" | grep -q "/craftsman:${cmd}"; then
        log_pass "core command /craftsman:${cmd} present"
    else
        log_fail "core command /craftsman:${cmd} should be present"
    fi
done

# Test: routing mentions trigger contexts (not just command names)
if echo "$output" | grep -q "Bug.*error.*crash"; then
    log_pass "routing contains trigger context for debug"
else
    log_fail "routing should contain trigger context for debug"
fi

# Test: output contains do-not-auto-execute instruction
if echo "$output" | grep -qi "do NOT auto-execute\|propose to user"; then
    log_pass "routing contains non-execution instruction"
else
    log_fail "routing should instruct not to auto-execute"
fi

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
