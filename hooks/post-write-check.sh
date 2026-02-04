#!/usr/bin/env bash
# =============================================================================
# Post-Write/Edit Validation Hook for Claude Code
# Validates written or edited files against craftsman coding standards.
#
# TRIGGERS: PostToolUse for Write and Edit tools
# SECURITY: This script only READS the specified file and outputs warnings.
#           It does NOT modify files, execute code, or access network.
# =============================================================================
set -euo pipefail

# Read tool input from stdin (JSON from Claude Code)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit silently if no file path or file doesn't exist
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Get file extension
EXT="${FILE_PATH##*.}"
ISSUES=0

# =============================================================================
# PHP Validation Rules
# =============================================================================
validate_php() {
    local file="$1"

    # Rule PHP001: declare(strict_types=1) required
    if ! grep -q "declare(strict_types=1)" "$file" 2>/dev/null; then
        echo "⚠️  PHP001: Missing declare(strict_types=1)"
        ((ISSUES++)) || true
    fi

    # Rule PHP002: Classes must be final (except interface/trait/abstract)
    if grep -q "^class " "$file" 2>/dev/null; then
        if ! grep -q "final class" "$file" 2>/dev/null; then
            if ! grep -qE "(interface|trait|abstract class)" "$file" 2>/dev/null; then
                echo "⚠️  PHP002: Class should be final"
                ((ISSUES++)) || true
            fi
        fi
    fi

    # Rule PHP003: No public setters
    if grep -qE "public function set[A-Z]" "$file" 2>/dev/null; then
        echo "⚠️  PHP003: Public setter found (use behavioral methods)"
        ((ISSUES++)) || true
    fi

    # Rule PHP004: No new DateTime() - use Clock abstraction
    if grep -q "new \\\\DateTime()" "$file" 2>/dev/null; then
        echo "⚠️  PHP004: new DateTime() found (inject Clock instead)"
        ((ISSUES++)) || true
    fi
}

# =============================================================================
# TypeScript Validation Rules
# =============================================================================
validate_typescript() {
    local file="$1"

    # Rule TS001: No 'any' type
    if grep -qE ": any[^a-zA-Z]|<any>" "$file" 2>/dev/null; then
        echo "⚠️  TS001: 'any' type found (use proper types or 'unknown')"
        ((ISSUES++)) || true
    fi

    # Rule TS002: No default exports
    if grep -q "export default" "$file" 2>/dev/null; then
        echo "⚠️  TS002: Default export found (use named exports)"
        ((ISSUES++)) || true
    fi

    # Rule TS003: No non-null assertion (!)
    # Exclude != and !== comparisons
    if grep -qE "[a-zA-Z0-9_]+![^=]" "$file" 2>/dev/null; then
        echo "⚠️  TS003: Non-null assertion (!) found (handle null explicitly)"
        ((ISSUES++)) || true
    fi
}

# =============================================================================
# Run Validation
# =============================================================================
echo "📋 Validating: ${FILE_PATH##*/}"

case "$EXT" in
    php)
        validate_php "$FILE_PATH"
        ;;
    ts|tsx)
        validate_typescript "$FILE_PATH"
        ;;
esac

# Summary
if [[ $ISSUES -gt 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Found $ISSUES issue(s). Review before commit."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Always exit 0 (warning only, never block)
exit 0
