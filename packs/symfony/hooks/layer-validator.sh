#!/usr/bin/env bash
# =============================================================================
# PHP Layer Validator - Symfony Pack
# Provides pack_validate_php_layers() for DDD layer enforcement.
#
# Rules: LAYER001, LAYER002, LAYER003
# Requires: add_violation()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
# =============================================================================

# "App" is only the Symfony skeleton's default root namespace. Hardcoding it
# meant every project that renamed its root, and every package in a monorepo,
# passed all three layer rules by construction. The root now comes from
# composer.json (see config_php_namespace_root); "App" remains the fallback
# when there is no composer.json to read.
_layer_ns_regex() {
    local file="$1" root
    if declare -F config_php_namespace_root >/dev/null 2>&1; then
        root=$(config_php_namespace_root "$(dirname "$file")")
    fi
    [[ -n "${root:-}" ]] || root="App"
    # A backslash in the root has to survive into the ERE as a literal.
    printf '%s' "${root//\\/\\\\}"
}

# In this layer, is the file part of $layer? Path or declared namespace.
_layer_is() {
    local file="$1" ns="$2" layer="$3"
    [[ "$file" == *"/${layer}/"* ]] && return 0
    grep -qE "namespace\s+${ns}\\\\${layer}" "$file" 2>/dev/null
}

_layer_imports() {
    local file="$1" ns="$2" layer="$3"
    grep -qE "use\s+${ns}\\\\${layer}" "$file" 2>/dev/null
}

pack_validate_php_layers() {
    local file="$1"
    local ns
    ns=$(_layer_ns_regex "$file")

    if _layer_is "$file" "$ns" "Domain"; then
        _layer_imports "$file" "$ns" "Infrastructure" \
            && add_violation "LAYER001" "Domain imports Infrastructure - DDD layer violation"
        _layer_imports "$file" "$ns" "Presentation" \
            && add_violation "LAYER002" "Domain imports Presentation - DDD layer violation"
    fi

    if _layer_is "$file" "$ns" "Application"; then
        _layer_imports "$file" "$ns" "Presentation" \
            && add_violation "LAYER003" "Application imports Presentation - DDD layer violation"
    fi
    return 0
}
