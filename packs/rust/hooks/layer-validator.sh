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

_RUST_LAYER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pack_validate_rust_layers() {
    local file="$1"

    # Rust module paths are lowercase by convention, so the path check matches
    # /domain/ in kind. `domain.rs` counts too: the 2018 edition dropped
    # mod.rs, so a whole domain layer can live in one file beside its
    # directory.
    case "$file" in
        */domain/*|*/domain.rs|domain/*|domain.rs) ;;
        *) return 0 ;;
    esac

    # The statement scan lives in rust_imports.py: rustfmt writes the grouped
    # form by default and spreads it over several lines, so a grep anchored on
    # the segment right after `use` missed `use crate::{domain::X,
    # infrastructure::Y};` entirely. Without python3 the check cannot run, and
    # says so rather than reporting the file clean.
    if ! command -v python3 >/dev/null 2>&1; then
        echo "craftsman: python3 not found, LAYER001 was not checked on $file" >&2
        return 0
    fi
    if python3 "${_RUST_LAYER_DIR}/rust_imports.py" "$file" infrastructure infra >/dev/null 2>&1; then
        add_violation "LAYER001" "Domain imports Infrastructure - DDD layer violation"
    fi
}
