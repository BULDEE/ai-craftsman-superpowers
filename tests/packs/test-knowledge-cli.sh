#!/usr/bin/env bash
# =============================================================================
# Tests for knowledge-rag CLI modes
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_DIR="$ROOT_DIR/packs/ai-ml/mcp/knowledge-rag"

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; (( TESTS_PASSED++ )); }
log_fail() { echo "  ✗ $1"; (( TESTS_FAILED++ )); }

echo "=== Knowledge CLI Tests ==="

# Skip if node_modules not installed
if [[ ! -d "$MCP_DIR/node_modules" ]]; then
    echo "  SKIP: node_modules not installed in $MCP_DIR"
    echo "  Run: cd $MCP_DIR && npm install"
    exit 0
fi

# Test: cli.ts exists
if [[ -f "$MCP_DIR/scripts/cli.ts" ]]; then
    log_pass "cli.ts exists"
else
    log_fail "cli.ts should exist at $MCP_DIR/scripts/cli.ts"
fi

# Test: cli.ts with unknown mode exits with error
result=$(cd "$MCP_DIR" && npx tsx scripts/cli.ts unknown 2>&1) || true
if echo "$result" | grep -q "Unknown mode"; then
    log_pass "cli.ts rejects unknown mode"
else
    log_fail "cli.ts should reject unknown mode: $result"
fi

# Test: status mode produces valid JSON (does not require Ollama)
result=$(cd "$MCP_DIR" && npx tsx scripts/cli.ts status 2>/dev/null) || true
if echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'totalChunks' in d" 2>/dev/null; then
    log_pass "cli.ts status produces valid JSON with totalChunks"
else
    log_fail "cli.ts status should produce valid JSON: $result"
fi

# Test: list mode produces valid JSON
result=$(cd "$MCP_DIR" && npx tsx scripts/cli.ts list 2>/dev/null) || true
if echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'sources' in d" 2>/dev/null; then
    log_pass "cli.ts list produces valid JSON with sources"
else
    log_fail "cli.ts list should produce valid JSON: $result"
fi

# Test: add without path shows usage error
result=$(cd "$MCP_DIR" && npx tsx scripts/cli.ts add 2>&1) || true
if echo "$result" | grep -qi "usage\|file-path"; then
    log_pass "cli.ts add without args shows usage"
else
    log_fail "cli.ts add should show usage: $result"
fi

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
