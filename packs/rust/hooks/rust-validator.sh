#!/usr/bin/env bash
# =============================================================================
# Rust Validator - Rust Pack
# Provides pack_validate_rust() for the pack-loader pipeline.
#
# Rules: RUST001-005, WARN-RUST001, plus NEST001, LOC001, GOD001 and PARAM001,
#   which this pack detects itself. See hooks/rust_structure.py and the
#   metrics_dialect note in pack.yml for why the shared extractor cannot read
#   Rust.
#
# Every rule lives in rust_structure.py: one pass over the file, one place
# where Rust's grammar is described, one ignore filter. RUST001 and RUST005
# were written here first, on the grounds that they were greps needing the
# per-line ignore marker. Both halves were wrong: the scanner's drop_ignored
# already honours the marker for every rule it emits, and RUST002 and RUST003
# are line greps too. The split only meant that without python3 two rules ran,
# six did not, and the file was reported clean.
#
# Requires: add_violation(), add_warning()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

# A rule that cannot run is not a rule that passed, and here nothing at all can
# run without python3. Say so once per process, on stderr, rather than
# reporting every Rust file clean in silence.
_RUST_PACK_PY3_WARNED=""
_rust_pack_has_python3() {
    command -v python3 >/dev/null 2>&1 && return 0
    if [[ -z "${_RUST_PACK_PY3_WARNED}" ]]; then
        _RUST_PACK_PY3_WARNED=1  # craftsman-ignore: WARN-SH001 - once per process, local would reset it
        echo "craftsman: python3 not found, NO Rust rule was run on this file" >&2
    fi
    return 1
}

_RUST_PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RUST_STRUCTURE_PY="${_RUST_PACK_DIR}/rust_structure.py"

# Which rules are reported as findings and which as advice. Severity itself is
# the rules engine's decision: add_violation and add_warning both resolve it,
# and the advisory defaults are declared in pack.yml, with a fallback in
# hooks/lib/rules-engine.sh and its mirror in ci/craftsman-ci.sh.
pack_validate_rust() {
    local file="$1" rule message
    _rust_pack_has_python3 || return 0
    [[ -f "$_RUST_STRUCTURE_PY" ]] || return 0
    while IFS='|' read -r rule message; do
        [[ -z "$rule" ]] && continue
        case "$rule" in
            RUST004|RUST005|WARN-RUST001) add_warning "$rule" "$message" ;;
            *)                            add_violation "$rule" "$message" ;;
        esac
    done < <(_rust_structure_lines "$file")
}

# The scanner's stdout, and a warning once per process when it did not run.
# Its stderr used to be discarded and its exit code lost in the process
# substitution above, so a scanner that could not load the engine's brace walk
# (an external copy without CLAUDE_PLUGIN_ROOT) read as a clean file.
_RUST_PACK_SCAN_WARNED=""
_rust_structure_lines() {
    local file="$1" out status=0
    out=$(python3 "$_RUST_STRUCTURE_PY" "$file" 2>/dev/null) || status=$?
    if [[ "$status" -ne 0 && -z "$out" && -z "${_RUST_PACK_SCAN_WARNED}" ]]; then
        _RUST_PACK_SCAN_WARNED=1  # craftsman-ignore: WARN-SH001 - once per process, local would reset it
        echo "craftsman: rust structure scan did not run (exit ${status}), files are not clean, they are unread; set CLAUDE_PLUGIN_ROOT" >&2
    fi
    printf '%s\n' "$out"
}
