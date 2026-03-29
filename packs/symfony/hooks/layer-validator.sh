#!/usr/bin/env bash
# =============================================================================
# PHP Layer Validator — Symfony Pack
# Provides pack_validate_php_layers() for DDD layer enforcement.
#
# Rules: LAYER001, LAYER002, LAYER003
# Requires: add_violation()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
# =============================================================================

pack_validate_php_layers() {
    local file="$1"

    local is_domain=false
    local is_application=false

    # Check path OR namespace
    if [[ "$file" == *"/Domain/"* ]] || grep -qE "namespace\s+App\\\\Domain" "$file" 2>/dev/null; then
        is_domain=true
    fi
    if [[ "$file" == *"/Application/"* ]] || grep -qE "namespace\s+App\\\\Application" "$file" 2>/dev/null; then
        is_application=true
    fi

    # Domain must not import Infrastructure
    if [[ "$is_domain" == true ]]; then
        if grep -qE "use\s+App\\\\Infrastructure" "$file" 2>/dev/null; then
            add_violation "LAYER001" "Domain imports Infrastructure — DDD layer violation"
        fi
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_violation "LAYER002" "Domain imports Presentation — DDD layer violation"
        fi
    fi

    # Application must not import Presentation
    if [[ "$is_application" == true ]]; then
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_violation "LAYER003" "Application imports Presentation — DDD layer violation"
        fi
    fi
}
