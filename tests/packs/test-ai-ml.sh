#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; ((TESTS_PASSED++)); }
log_fail() { echo "  ✗ $1 — $2"; ((TESTS_FAILED++)); }

echo "=== AI-ML Pack Tests ==="

# Test: pack.yml exists and is valid
if [[ -f "$ROOT_DIR/packs/ai-ml/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "file not found"
fi

# Test: wildcard stack compatibility
stack_line=$(grep "stack:" "$ROOT_DIR/packs/ai-ml/pack.yml")
if echo "$stack_line" | grep -q '"\*"'; then
    log_pass "Stack compatibility is wildcard (*)"
else
    log_fail "Stack compatibility is wildcard" "got: $stack_line"
fi

# Test: ai-engineer agent exists
if [[ -f "$ROOT_DIR/packs/ai-ml/agents/ai-engineer.md" ]]; then
    log_pass "ai-engineer agent exists"
else
    log_fail "ai-engineer agent exists" "file not found"
fi

# Test: knowledge files exist
for f in mlops-principles.md rag-architecture.md vector-databases.md; do
    if [[ -f "$ROOT_DIR/packs/ai-ml/knowledge/$f" ]]; then
        log_pass "Knowledge: $f exists"
    else
        log_fail "Knowledge: $f exists" "file not found"
    fi
done

# Test: commands exist
for f in rag.md mlops.md agent-design.md; do
    if [[ -f "$ROOT_DIR/packs/ai-ml/commands/$f" ]]; then
        log_pass "Command: $f exists"
    else
        log_fail "Command: $f exists" "file not found"
    fi
done

# Test: MCP server source exists
if [[ -f "$ROOT_DIR/packs/ai-ml/mcp/knowledge-rag/package.json" ]]; then
    log_pass "MCP server package.json exists"
else
    log_fail "MCP server package.json exists" "file not found"
fi

# Test: setup script exists
if [[ -f "$ROOT_DIR/packs/ai-ml/scripts/setup.sh" ]]; then
    log_pass "Setup script exists"
else
    log_fail "Setup script exists" "file not found"
fi

# Test: mcpServers declared in pack.yml
if grep -q "mcpServers:" "$ROOT_DIR/packs/ai-ml/pack.yml"; then
    log_pass "mcpServers declared in pack.yml"
else
    log_fail "mcpServers declared in pack.yml" "not found"
fi

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
