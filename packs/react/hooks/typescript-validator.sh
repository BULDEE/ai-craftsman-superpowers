#!/usr/bin/env bash
# =============================================================================
# TypeScript Regex Validator — React Pack
# Provides pack_validate_typescript() for the pack-loader pipeline.
#
# Rules: TS001-003, WARN-TS001
# Requires: add_violation(), add_warning(), line_has_ignore(), metrics_record_violation()
# =============================================================================

pack_validate_typescript() {
    local file="$1"

    # TS001: No 'any' type (check per line for craftsman-ignore)
    while IFS= read -r line; do
        if echo "$line" | grep -qE ": any[^a-zA-Z]|<any>|: any$" 2>/dev/null; then
            if ! line_has_ignore "$line" "no-any"; then
                add_violation "TS001" "'any' type found — use proper types or 'unknown'"
            else
                metrics_record_violation "TS001" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # TS002: No default exports
    if grep -q "export default" "$file" 2>/dev/null; then
        add_violation "TS002" "Default export found — use named exports"
    fi

    # TS003: No non-null assertion (!) — exclude !=, !==, !., logical NOT (!expr), and end-of-line
    if grep -qE "[a-zA-Z0-9_\)]\!([^=\.!(]|$)" "$file" 2>/dev/null; then
        add_violation "TS003" "Non-null assertion (!) found — handle null explicitly"
    fi

    # WARN-TS001: Max 3 parameters
    if grep -qE "(function\s+\w+|=>)\s*\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-TS001" "Function with 4+ parameters — consider refactoring to object"
    fi
}
