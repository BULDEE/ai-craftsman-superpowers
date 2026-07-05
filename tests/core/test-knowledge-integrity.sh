#!/usr/bin/env bash
# =============================================================================
# test-knowledge-integrity.sh — Integrity of the core knowledge base (v3.6.0)
# Verifies new files exist, deprecation stubs are in place, no em-dashes leak,
# and every [[wiki-link]] resolves to a real knowledge file.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
KNOWLEDGE_DIR="${ROOT_DIR}/knowledge"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo ""
echo "=== Knowledge Base Integrity (v3.6.0) ==="

# -----------------------------------------------------------------------------
# 1. New core knowledge files exist
# -----------------------------------------------------------------------------
EXPECTED_FILES=(
    "clean-architecture.md"
    "hexagonal.md"
    "tdd.md"
    "testing-strategy.md"
    "ddd/ddd-domain-design.md"
    "ddd/ddd-cqrs-architecture.md"
    "legacy/legacy-techniques.md"
    "legacy/characterization-testing.md"
    "legacy/strangler-fig.md"
    "legacy/taking-over-legacy.md"
    "legacy/communicating-tech-debt.md"
    "refactoring/mikado-method.md"
    "refactoring/refactoring-campaigns.md"
    "refactoring/code-smells.md"
    "refactoring/refactoring-katas.md"
    "anti-patterns/god-object.md"
    "anti-patterns/primitive-obsession.md"
    "anti-patterns/singleton-abuse.md"
)
for rel in "${EXPECTED_FILES[@]}"; do
    if [[ -f "${KNOWLEDGE_DIR}/${rel}" ]]; then
        log_pass "core knowledge exists: ${rel}"
    else
        log_fail "missing core knowledge" "${rel}"
    fi
done

# -----------------------------------------------------------------------------
# 2. Deprecation stubs are in place and marked deprecated
# -----------------------------------------------------------------------------
STUBS=(
    "${KNOWLEDGE_DIR}/design-patterns.md"
    "${ROOT_DIR}/packs/symfony/knowledge/ddd-domain-design.md"
    "${ROOT_DIR}/packs/symfony/knowledge/ddd-cqrs-architecture.md"
)
for stub in "${STUBS[@]}"; do
    name="$(basename "$(dirname "$stub")")/$(basename "$stub")"
    if [[ -f "$stub" ]] && grep -qiE 'deprecated|moved|merged' "$stub"; then
        log_pass "deprecation stub present: ${name}"
    else
        log_fail "stub missing or not marked deprecated" "${name}"
    fi
done

# -----------------------------------------------------------------------------
# 3. No em-dash (U+2014) anywhere in knowledge/ (copywriting rule)
# -----------------------------------------------------------------------------
EMDASH_HITS=$(grep -rl $'\xe2\x80\x94' "$KNOWLEDGE_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$EMDASH_HITS" == "0" ]]; then
    log_pass "no em-dash (U+2014) in knowledge/"
else
    log_fail "em-dash found in knowledge/" "$EMDASH_HITS file(s): $(grep -rl $'\xe2\x80\x94' "$KNOWLEDGE_DIR" | head -3 | tr '\n' ' ')"
fi

# -----------------------------------------------------------------------------
# 4. No live reference to design-patterns.md outside the stub itself
# -----------------------------------------------------------------------------
LIVE_REFS=$(grep -rl 'design-patterns\.md\|\[\[design-patterns\]\]' \
    "${ROOT_DIR}/commands" "${ROOT_DIR}/agents" "${ROOT_DIR}/hooks" "${ROOT_DIR}/packs" 2>/dev/null \
    | grep -v node_modules | wc -l | tr -d ' ')
if [[ "$LIVE_REFS" == "0" ]]; then
    log_pass "no live code reference to design-patterns.md"
else
    log_fail "design-patterns.md still referenced by code" "$LIVE_REFS file(s)"
fi

# -----------------------------------------------------------------------------
# 5. Every [[wiki-link]] in knowledge/ resolves to a real file
# -----------------------------------------------------------------------------
resolve_link() {
    # A link like [[ddd/ddd-domain-design]] -> knowledge/ddd/ddd-domain-design.md
    local target="$1"
    [[ -f "${KNOWLEDGE_DIR}/${target}.md" ]]
}

broken_links=0
checked_links=0
while IFS= read -r link; do
    [[ -z "$link" ]] && continue
    checked_links=$((checked_links + 1))
    if ! resolve_link "$link"; then
        broken_links=$((broken_links + 1))
        [[ "$broken_links" -le 5 ]] && echo "  broken wiki-link: [[${link}]]"
    fi
done < <(grep -rhoE '\[\[[a-zA-Z0-9/_-]+\]\]' "$KNOWLEDGE_DIR" 2>/dev/null \
    | sed -E 's/^\[\[//; s/\]\]$//' | sort -u)

if [[ "$broken_links" == "0" ]]; then
    log_pass "all ${checked_links} wiki-links resolve"
else
    log_fail "unresolved wiki-links" "${broken_links} of ${checked_links} broken"
fi

# -----------------------------------------------------------------------------
# 6. Each new knowledge file has a top-level heading
# -----------------------------------------------------------------------------
missing_heading=0
for rel in "${EXPECTED_FILES[@]}"; do
    f="${KNOWLEDGE_DIR}/${rel}"
    [[ -f "$f" ]] || continue
    if ! grep -qE '^# ' "$f"; then
        missing_heading=$((missing_heading + 1))
        echo "  no top-level heading: ${rel}"
    fi
done
if [[ "$missing_heading" == "0" ]]; then
    log_pass "all new knowledge files have a top-level heading"
else
    log_fail "knowledge files missing a top-level heading" "${missing_heading}"
fi

test_summary
