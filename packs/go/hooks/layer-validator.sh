#!/usr/bin/env bash
# =============================================================================
# Go Layer Validator - Go Pack
# Provides pack_validate_go_layers() for DDD layer enforcement.
#
# Rules: LAYER001 (owned by core, see rules/core.yml - this pack supplies only
#   the Level 1 Go detector, the same split packs/python and packs/react use)
# Requires: add_violation()
#   This is provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# =============================================================================

pack_validate_go_layers() {
    local file="$1"

    # Go package directories are lowercase by convention, unlike PHP's
    # Domain/Infrastructure namespaces, so the path check matches /domain/ in
    # kind. An import path is a quoted string, which is why the pattern looks
    # for the segment inside quotes rather than anywhere on the line: a comment
    # mentioning infrastructure is not an import of it.
    if [[ "$file" == *"/domain/"* ]]; then
        if grep -qE '^[[:space:]]*(_[[:space:]]+|[A-Za-z0-9_]+[[:space:]]+)?"[^"]*/(infrastructure|infra)/' "$file" 2>/dev/null; then
            add_violation "LAYER001" "Domain imports Infrastructure - DDD layer violation"
        fi
    fi
}
