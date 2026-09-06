#!/usr/bin/env bash
# =============================================================================
# Rust Layer Validator - Rust Pack
# Provides pack_validate_rust_layers() for DDD layer enforcement.
#
# Rules: LAYER001 (owned by core, see rules/core.yml - this pack supplies only
#   the Level 1 Rust detector, the same split packs/go and packs/python use)
# Requires: add_violation()
#   This is provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# =============================================================================

pack_validate_rust_layers() {
    local file="$1"

    # Rust module paths are lowercase by convention, so the path check matches
    # /domain/ in kind. A `use` path is a bare token rather than a quoted
    # string as in Go, so the pattern anchors on the `use` keyword: a comment
    # or a doc example mentioning infrastructure is not an import of it. Both
    # `crate::infrastructure::x` and `use crate::infrastructure;` count, which
    # is why the segment may end on `::` or on the statement terminator.
    if [[ "$file" == *"/domain/"* ]]; then
        if grep -qE '^[[:space:]]*(pub[[:space:]]+)?use[[:space:]]+[A-Za-z0-9_:]*\b(infrastructure|infra)\b' "$file" 2>/dev/null; then
            add_violation "LAYER001" "Domain imports Infrastructure - DDD layer violation"
        fi
    fi
}
