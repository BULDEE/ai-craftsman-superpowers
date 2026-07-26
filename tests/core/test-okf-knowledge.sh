#!/usr/bin/env bash
# =============================================================================
# OKF knowledge bundle tests (ADR-0024): frontmatter conformance and
# deterministic lookup. No RAG remnants.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

LOOKUP="$ROOT_DIR/hooks/lib/knowledge_lookup.py"
BUNDLE="$ROOT_DIR/knowledge"

echo "=== Bundle conformance (OKF v0.2) ==="

MISSING_TYPE=0
TOTAL=0
while IFS= read -r file; do
    [[ "$(basename "$file")" == "index.md" || "$(basename "$file")" == "log.md" ]] && continue
    TOTAL=$((TOTAL + 1))
    head -12 "$file" | grep -q "^type:" || { MISSING_TYPE=$((MISSING_TYPE + 1)); echo "  missing type: $file"; }
done < <(find "$BUNDLE" -name "*.md")

if [[ $MISSING_TYPE -eq 0 && $TOTAL -ge 30 ]]; then
    log_pass "all $TOTAL concept files declare 'type' (the only OKF-required key)"
else
    log_fail "OKF conformance" "$MISSING_TYPE of $TOTAL files missing type"
fi

if head -3 "$BUNDLE/index.md" | grep -q 'okf_version: "0.2"'; then
    log_pass "bundle index declares okf_version 0.2"
else
    log_fail "bundle index" "missing okf_version declaration"
fi

echo ""
echo "=== Deterministic lookup ==="

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-rule LAYER004)
if echo "$OUT" | grep -q "persistence/repository-pattern"; then
    log_pass "by-rule LAYER004 routes to repository-pattern"
else
    log_fail "rule routing" "$OUT"
fi

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-rule DB002)
if echo "$OUT" | grep -q "persistence/migration-discipline"; then
    log_pass "by-rule DB002 routes to migration-discipline"
else
    log_fail "rule routing DB002" "$OUT"
fi

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-rule SEC001)
if echo "$OUT" | grep -q "security/secure-by-design"; then
    log_pass "by-rule SEC001 routes to secure-by-design"
else
    log_fail "SEC001 routing" "$OUT"
fi

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-tag security)
if [[ $(echo "$OUT" | grep -c .) -eq 2 ]]; then
    log_pass "by-tag security returns the 2 security concepts"
else
    log_fail "security tag routing" "$OUT"
fi

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-tag persistence)
if [[ $(echo "$OUT" | grep -c .) -eq 4 ]]; then
    log_pass "by-tag persistence returns the 4 persistence concepts"
else
    log_fail "tag routing" "$OUT"
fi

OUT=$(python3 "$LOOKUP" "$BUNDLE" by-rule NOPE999)
if [[ -z "$OUT" ]]; then
    log_pass "unknown rule yields silent empty output (caller degrades)"
else
    log_fail "unknown rule" "expected empty, got: $OUT"
fi

echo ""
echo "=== RAG removal is complete ==="

if [[ ! -d "$ROOT_DIR/packs/ai-ml/mcp" ]]; then
    log_pass "packs/ai-ml/mcp removed"
else
    log_fail "mcp removal" "directory still present"
fi

if ! grep -q "mcpServers" "$ROOT_DIR/.claude-plugin/plugin.json"; then
    log_pass "plugin.json ships no MCP server"
else
    log_fail "plugin.json" "mcpServers block still present"
fi

if ! grep -rq "hc_check_ollama" "$ROOT_DIR/hooks/lib/healthcheck.sh"; then
    log_pass "healthcheck no longer probes Ollama"
else
    log_fail "healthcheck" "ollama probe still present"
fi

test_summary
