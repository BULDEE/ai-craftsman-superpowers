#!/usr/bin/env bash
# =============================================================================
# TypeScript Regex Validator - React Pack
# Provides pack_validate_typescript() for the pack-loader pipeline.
#
# Rules: TS001-003, WARN-TS001 (regex) + NEST001/LOC001/GOD001/PARAM001
#   (brace-aware, via structural_check_file).
# Requires: add_violation(), add_warning(), line_has_ignore(), metrics_record_violation()
# craftsman-ignore: SH001
# =============================================================================

_check_ts001() {
    local file="$1"
    local line
    while IFS= read -r line; do
        echo "$line" | grep -qE ": any[^a-zA-Z]|<any>|: any$" 2>/dev/null || continue
        if ! line_has_ignore "$line" "no-any"; then
            add_violation "TS001" "'any' type found - use proper types or 'unknown'"
        else
            metrics_record_violation "TS001" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
        fi
    done < "$file"
}

_check_ts002() {
    local file="$1"
    if grep -q "export default" "$file" 2>/dev/null; then
        add_violation "TS002" "Default export found - use named exports"
    fi
}

_check_ts003() {
    local file="$1"
    # No non-null assertion (!) - exclude !=, !==, !., logical NOT (!expr), and end-of-line
    if grep -qE "[a-zA-Z0-9_\)]\!([^=\.!(]|$)" "$file" 2>/dev/null; then
        add_violation "TS003" "Non-null assertion (!) found - handle null explicitly"
    fi
}

_check_warn_ts001() {
    local file="$1"
    if grep -qE "(function\s+\w+|=>)\s*\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-TS001" "Function with 4+ parameters - consider refactoring to object"
    fi
}

_check_ts_structure() {
    local file="$1"
    if declare -F structural_check_file >/dev/null 2>&1; then
        structural_check_file "$file" "ts"
    fi
}

pack_validate_typescript() {
    local file="$1"
    _check_ts001 "$file"
    _check_ts002 "$file"
    _check_ts003 "$file"
    _check_warn_ts001 "$file"
    _check_ts_structure "$file"
}
