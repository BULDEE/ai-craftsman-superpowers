#!/usr/bin/env bash
# =============================================================================
# TypeScript Layer Validator — React Pack
# Provides pack_validate_typescript_layers() for DDD layer enforcement.
#
# Rules: LAYER001
# =============================================================================

pack_validate_typescript_layers() {
    local file="$1"

    # TypeScript: domain must not import infrastructure
    if [[ "$file" == *"/domain/"* ]]; then
        if grep -qE "from\s+['\"].*infrastructure" "$file" 2>/dev/null; then
            add_violation "LAYER001" "domain imports infrastructure — layer violation"
        fi
    fi
}
