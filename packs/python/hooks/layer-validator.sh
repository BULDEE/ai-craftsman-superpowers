#!/usr/bin/env bash
# =============================================================================
# Python Layer Validator - Python Pack
# Provides pack_validate_python_layers() for DDD layer enforcement.
#
# Rules: LAYER001 (owned by core, see rules/core.yml - this pack only supplies
#   the Level 1 detector, the same split react/hooks/layer-validator.sh uses)
# Requires: add_violation()
#   This is provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# =============================================================================

pack_validate_python_layers() {
    local file="$1"

    # Python packages are lowercase by convention, unlike PHP's Domain/
    # Infrastructure namespaces, so the path check matches /domain/ in kind.
    if [[ "$file" == *"/domain/"* ]]; then
        if grep -qE '^\s*(from|import)\s+[A-Za-z0-9_.]*infrastructure' "$file" 2>/dev/null; then
            add_violation "LAYER001" "Domain imports Infrastructure - DDD layer violation"
        fi
    fi
}
