#!/usr/bin/env bash
# =============================================================================
# Tests for /craftsman:legacy command
# Validates frontmatter, the 4 modes, iron laws, and knowledge references.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

LEGACY_CMD="$ROOT_DIR/commands/legacy.md"

echo ""
echo "=== Legacy Command Tests ==="

# --- Existence + frontmatter ---
if [[ -f "$LEGACY_CMD" ]]; then
    log_pass "legacy.md exists"
else
    log_fail "legacy.md missing"
    test_summary
    exit 0
fi

head -1 "$LEGACY_CMD" | grep -q '^---$' && log_pass "has YAML frontmatter" || log_fail "missing frontmatter"
grep -q '^description:' "$LEGACY_CMD" && log_pass "has description" || log_fail "missing description"
grep -q '^effort:' "$LEGACY_CMD" && log_pass "has effort" || log_fail "missing effort"
grep -q '^effort: heavy' "$LEGACY_CMD" && log_pass "effort is heavy" || log_fail "effort should be heavy"

# --- The 4 modes ---
for mode in audit cover untangle migrate; do
    if grep -q "craftsman:legacy ${mode}" "$LEGACY_CMD"; then
        log_pass "documents mode: ${mode}"
    else
        log_fail "missing mode" "${mode}"
    fi
done

# --- Iron laws present (behavior-preservation discipline) ---
if grep -qi 'Iron Law' "$LEGACY_CMD"; then
    log_pass "states Iron Laws"
else
    log_fail "should state Iron Laws (never change behavior while netting, no big-bang)"
fi

# --- Knowledge references wired (ADR-0005 knowledge-first) ---
KNOWLEDGE_REFS=(
    "legacy/characterization-testing.md"
    "legacy/legacy-techniques.md"
    "legacy/strangler-fig.md"
    "refactoring/refactoring-campaigns.md"
)
for ref in "${KNOWLEDGE_REFS[@]}"; do
    if grep -q "$ref" "$LEGACY_CMD"; then
        log_pass "references knowledge: ${ref}"
    else
        log_fail "should reference knowledge" "${ref}"
    fi
done

# --- Consume tool output, do not re-compute (positioning) ---
if grep -q 'legacy audit --from' "$LEGACY_CMD"; then
    log_pass "audit supports --from (ingests SonarQube/PHPStan/CodeScene reports)"
else
    log_fail "audit should support --from to consume existing tool output"
fi
if grep -q 'tooling-integration.md' "$LEGACY_CMD"; then
    log_pass "references tooling-integration knowledge"
else
    log_fail "should reference knowledge/tooling-integration.md"
fi

# --- Migration state persistence (atomic write rule) ---
if grep -q '.craftsman/legacy-campaign.json' "$LEGACY_CMD"; then
    log_pass "migrate mode persists campaign state"
else
    log_fail "migrate should persist to .craftsman/legacy-campaign.json"
fi

if grep -qi 'atomic' "$LEGACY_CMD"; then
    log_pass "mentions atomic write for state"
else
    log_fail "should require atomic write for .craftsman state"
fi

# --- Copywriting rule ---
if [[ "$(grep -c $'\xe2\x80\x94' "$LEGACY_CMD")" == "0" ]]; then
    log_pass "no em-dash in legacy.md"
else
    log_fail "em-dash found in legacy.md"
fi

# --- Registered in the routing table ---
source "$ROOT_DIR/hooks/lib/config.sh" 2>/dev/null || true
source "$ROOT_DIR/hooks/lib/pack-loader.sh" 2>/dev/null || true
source "$ROOT_DIR/hooks/lib/routing-table.sh" 2>/dev/null || true
if routing_table 2>/dev/null | grep -q '/craftsman:legacy'; then
    log_pass "legacy is in the routing table"
else
    log_fail "legacy should be registered in routing-table.sh"
fi

test_summary
