#!/usr/bin/env bash
# =============================================================================
# TypeScript and JavaScript Layer Validator - React Pack
# Provides pack_validate_typescript_layers() and pack_validate_javascript_layers()
# for DDD layer enforcement. One body serves both languages, so the verdict
# cannot differ between a .ts and a .js file.
#
# Rules: LAYER001
# =============================================================================

# Domain must not import infrastructure, whether by an ESM `from`, a CommonJS
# `require(...)` or a dynamic `import(...)`.
_react_layers_check() {
    local file="$1"
    [[ "$file" == *"/domain/"* ]] || return 0
    grep -q 'infrastructure' "$file" 2>/dev/null || return 0
    if grep -vE '^[[:space:]]*(//|\*|/\*)' "$file" 2>/dev/null \
        | grep -qE "(from[[:space:]]+|require[[:space:]]*\([[:space:]]*|import[[:space:]]*\([[:space:]]*)['\"\`][^'\"\`]*infrastructure"; then
        add_violation "LAYER001" "domain imports infrastructure - layer violation"
    fi
}

pack_validate_typescript_layers() {
    _react_layers_check "$1"
}

pack_validate_javascript_layers() {
    _react_layers_check "$1"
}
