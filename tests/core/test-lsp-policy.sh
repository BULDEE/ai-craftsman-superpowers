#!/usr/bin/env bash
# =============================================================================
# LSP policy tests (ADR-0019 amendment)
#
# Claude Code spawns a declared LSP server unconditionally and surfaces a
# plugin error (ENOENT) when the binary is missing. The plugin therefore
# never declares one: no .lsp.json anywhere, no lspServers in any manifest.
# LSP wiring belongs to the official per-language plugins the user opts into.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== LSP Policy Tests ==="

# Test: no .lsp.json shipped anywhere in the plugin tree
lsp_files="$(find "$ROOT_DIR" -name ".lsp.json" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)"
if [[ -z "$lsp_files" ]]; then
    log_pass "no .lsp.json shipped in the plugin tree"
else
    log_fail "found .lsp.json (Claude Code errors when the binary is missing): $lsp_files"
fi

# Test: no lspServers declaration in any plugin manifest
manifest_hits=""
for manifest in "$ROOT_DIR/.claude-plugin/plugin.json" "$ROOT_DIR/.claude-plugin/marketplace.json"; do
    [[ -f "$manifest" ]] || continue
    if jq -e '.. | objects | select(has("lspServers"))' "$manifest" >/dev/null 2>&1; then
        manifest_hits="${manifest_hits} ${manifest}"
    fi
done
if [[ -z "$manifest_hits" ]]; then
    log_pass "no lspServers declaration in plugin manifests"
else
    log_fail "manifest declares lspServers (must move to an official LSP plugin):${manifest_hits}"
fi

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
