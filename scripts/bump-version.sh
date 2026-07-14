#!/usr/bin/env bash
# =============================================================================
# bump-version.sh - Update version across all project files
#
# Usage: ./scripts/bump-version.sh <new_version>
# Example: ./scripts/bump-version.sh 2.3.0
#
# Updates:
#   - .claude-plugin/plugin.json
#   - .claude-plugin/marketplace.json (2 occurrences)
#   - ci/craftsman-ci.sh (VERSION=)
#   - CLAUDE.md (Current version)
#
# README badges are dynamic (shields.io github/v/release) since 3.8.0 and
# tests/ci/test-adapters.sh mock reports are frozen fixtures - neither is
# touched here. Exits 1 if any tracked file matches neither the old nor the
# new version (drift), so a silent miss can't survive two releases again.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

NEW_VERSION="${1:-}"

if [[ -z "$NEW_VERSION" ]]; then
    echo "Usage: $0 <new_version>"
    echo "Example: $0 2.3.0"
    exit 1
fi

# Validate semver format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be semver format (e.g., 2.3.0)"
    exit 1
fi

# Detect current version from plugin.json (source of truth)
CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('${ROOT_DIR}/.claude-plugin/plugin.json'))['version'])")

if [[ -z "$CURRENT_VERSION" ]]; then
    echo "Error: Could not read current version from plugin.json"
    exit 1
fi

echo "Bumping version: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo ""

# Track files changed and drift
CHANGED=0
DRIFTED=0

bump_file() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    local label="${4:-$file}"

    if [[ ! -f "$file" ]]; then
        echo "  SKIP  $label (file not found)"
        return
    fi

    if grep -q "$pattern" "$file" 2>/dev/null; then
        sed -i '' "s|${pattern}|${replacement}|g" "$file"
        local count
        count=$(grep -c "$replacement" "$file" 2>/dev/null || echo "0")
        echo "  ✓  $label (${count} occurrence(s))"
        CHANGED=$((CHANGED + 1))
    elif grep -q "$replacement" "$file" 2>/dev/null; then
        echo "  -  $label (already at ${NEW_VERSION})"
    else
        echo "  ✗  $label (matches neither ${CURRENT_VERSION} nor ${NEW_VERSION} - version drift, fix manually)"
        DRIFTED=$((DRIFTED + 1))
    fi
}

# 1. plugin.json
bump_file "${ROOT_DIR}/.claude-plugin/plugin.json" \
    "\"version\": \"${CURRENT_VERSION}\"" \
    "\"version\": \"${NEW_VERSION}\"" \
    ".claude-plugin/plugin.json"

# 2. marketplace.json (2 occurrences)
bump_file "${ROOT_DIR}/.claude-plugin/marketplace.json" \
    "\"version\": \"${CURRENT_VERSION}\"" \
    "\"version\": \"${NEW_VERSION}\"" \
    ".claude-plugin/marketplace.json"

# 3. craftsman-ci.sh
bump_file "${ROOT_DIR}/ci/craftsman-ci.sh" \
    "VERSION=\"${CURRENT_VERSION}\"" \
    "VERSION=\"${NEW_VERSION}\"" \
    "ci/craftsman-ci.sh"

# 4. CLAUDE.md
bump_file "${ROOT_DIR}/CLAUDE.md" \
    "Current version:.* ${CURRENT_VERSION}" \
    "Current version:** ${NEW_VERSION}" \
    "CLAUDE.md"

echo ""
if [[ "$DRIFTED" -gt 0 ]]; then
    echo "FAILED: ${DRIFTED} file(s) drifted out of version sync (see ✗ above)."
    echo "Fix them manually to ${NEW_VERSION}, then re-run to verify."
    exit 1
fi
echo "Done. ${CHANGED} file(s) updated."
echo ""
echo "Next steps:"
echo "  1. Update CHANGELOG.md with new version entry"
echo "  2. git add -A && git commit -m 'chore: bump version to ${NEW_VERSION}'"
echo "  3. git tag v${NEW_VERSION}"
echo "  4. git push origin main && git push origin v${NEW_VERSION}"
