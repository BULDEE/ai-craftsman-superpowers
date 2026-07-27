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

# Next.js, Remix, Storybook and every tool that loads a config by path require
# a default export: the framework resolves the module's default, there is no
# named alternative. Flagging those files is not a finding, it is the rule
# being wrong about the file.
_ts002_default_export_is_required() {
    local file="$1" base
    base="$(basename "$file")"
    case "$base" in
        page.tsx|page.ts|layout.tsx|layout.ts|loading.tsx|error.tsx|not-found.tsx) return 0 ;;
        template.tsx|default.tsx|route.ts|middleware.ts|instrumentation.ts) return 0 ;;
        *.stories.tsx|*.stories.ts|*.config.ts|*.config.js|*.config.mjs) return 0 ;;
        *.d.ts) return 0 ;;
    esac
    # The pages router resolves every module under pages/ by default export.
    [[ "$file" == */pages/* ]] && return 0
    return 1
}

# One finding per file, as before, but a suppressed line no longer stands for
# the whole file: the scan keeps going and reports a later unsuppressed one.
_check_ts002() {
    local file="$1"
    _ts002_default_export_is_required "$file" && return 0
    local line suppressed=0
    while IFS= read -r line; do
        [[ "$line" == *"export default"* ]] || continue
        if ! line_has_ignore "$line" "TS002"; then
            add_violation "TS002" "Default export found - use named exports"
            return 0
        fi
        suppressed=1
    done < "$file"
    [[ $suppressed -eq 1 ]] \
        && { metrics_record_violation "TS002" "$FILE_PATTERN" "warning" 0 1 2>/dev/null || true; }
    return 0
}

_check_ts003() {
    local file="$1"
    local line suppressed=0
    # No non-null assertion (!) - exclude !=, !==, !., logical NOT (!expr), and end-of-line
    while IFS= read -r line; do
        echo "$line" | grep -qE "[a-zA-Z0-9_\)]\!([^=\.!(]|$)" 2>/dev/null || continue
        if ! line_has_ignore "$line" "TS003"; then
            add_violation "TS003" "Non-null assertion (!) found - handle null explicitly"
            return 0
        fi
        suppressed=1
    done < "$file"
    [[ $suppressed -eq 1 ]] \
        && { metrics_record_violation "TS003" "$FILE_PATTERN" "warning" 0 1 2>/dev/null || true; }
    return 0
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
