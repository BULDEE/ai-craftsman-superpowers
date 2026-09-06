#!/usr/bin/env bash
# =============================================================================
# Rust Regex Validator - Rust Pack
# Provides pack_validate_rust() for the pack-loader pipeline.
#
# Rules: RUST001-005, WARN-RUST001, plus NEST001, LOC001, GOD001 and PARAM001,
#   which this pack detects itself. See hooks/rust_structure.py and the
#   metrics_dialect note in pack.yml for why the shared extractor cannot read
#   Rust.
#
# Everything that needs to know what block it is inside, or what the line above
# said, lives in rust_structure.py: one pass over the file, one place where
# Rust's grammar is described. RUST001 and RUST005 stay here because they are
# greps, and because they need the ignore marker per line.
#
# Requires: add_violation(), add_warning(), line_has_ignore()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

# A rule that cannot run is not a rule that passed. Everything routed through
# rust_structure.py returns silently without python3, so say so once per process
# rather than reporting a file clean that was never read.
_RUST_PACK_PY3_WARNED=""
_rust_pack_has_python3() {
    command -v python3 >/dev/null 2>&1 && return 0
    if [[ -z "${_RUST_PACK_PY3_WARNED}" ]]; then
        _RUST_PACK_PY3_WARNED=1  # craftsman-ignore: WARN-SH001 - once per process, local would reset it
        echo "craftsman: python3 not found, every Rust rule except RUST001 and RUST005 was skipped" >&2
    fi
    return 1
}

_RUST_PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RUST_STRUCTURE_PY="${_RUST_PACK_DIR}/rust_structure.py"

# A test file, by any of the three conventions Rust uses. `#[cfg(test)]` inside
# a source file is handled by the scanner, which can see where the module ends.
_rust_is_test_file() {
    case "$1" in
        *_test.rs|*/tests/*|*/benches/*) return 0 ;;
    esac
    return 1
}

# Which rules are reported as findings and which as advice. Severity itself is
# the rules engine's decision: add_violation and add_warning both resolve it,
# and the advisory defaults are declared in hooks/lib/rules-engine.sh with a
# mirror in ci/craftsman-ci.sh.
_rust_emit_structure() {
    local file="$1" rule message
    _rust_pack_has_python3 || return 0
    [[ -f "$_RUST_STRUCTURE_PY" ]] || return 0
    while IFS='|' read -r rule message; do
        [[ -z "$rule" ]] && continue
        case "$rule" in
            RUST004|WARN-RUST001) add_warning "$rule" "$message" ;;
            *)                    add_violation "$rule" "$message" ;;
        esac
    done < <(python3 "$_RUST_STRUCTURE_PY" "$file" 2>/dev/null)
}

# RUST001 and RUST005: .unwrap() refuses the write, .expect() reports.
# The difference is the message: .expect("the schema is embedded") carries the
# invariant a reviewer checks, .unwrap() carries nothing at all. Both are
# exempt in test code, where a panic is how a failure is reported.
_check_unwrap_expect() {
    local file="$1"
    _rust_is_test_file "$file" && return 0
    local hit number content
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        number="${hit%%:*}"
        content="${hit#*:}"
        if echo "$content" | grep -qE '\.unwrap\(\)' 2>/dev/null; then
            line_has_ignore "$content" "RUST001" && continue
            add_violation "RUST001" "line ${number}: .unwrap() - propagate with ? or handle the error"
        else
            line_has_ignore "$content" "RUST005" && continue
            add_warning "RUST005" "line ${number}: .expect() - the message documents the panic, it does not prevent it"
        fi
    done < <(grep -nE '\.unwrap\(\)|\.expect\(' "$file" 2>/dev/null)
}

pack_validate_rust() {
    local file="$1"
    _rust_emit_structure "$file"
    _check_unwrap_expect "$file"
}
