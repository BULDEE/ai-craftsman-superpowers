#!/usr/bin/env bash
# =============================================================================
# Go Regex Validator - Go Pack
# Provides pack_validate_go() for the pack-loader pipeline.
#
# Rules: GO001-006, WARN-GO001, plus NEST001, LOC001 and PARAM001, which this
#   pack detects itself. See hooks/go_structure.py and the metrics_dialect note
#   in pack.yml for why the shared extractor cannot read Go.
#
# Everything that needs to know what function it is inside, or what the line
# above said, lives in go_structure.py: one pass over the file, one place where
# Go's grammar is described. Only GO005 stays here, because "is there a line
# that reads `func init()`" is a grep and nothing more.
#
# Requires: add_violation(), add_warning(), line_has_ignore()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

# A rule that cannot run is not a rule that passed. Everything routed through
# go_structure.py returns silently without python3, so say so once per process
# rather than reporting a file clean that was never read. Same shape as the
# guard in packs/python/hooks/python-validator.sh.
_GO_PACK_PY3_WARNED=""
_go_pack_has_python3() {
    command -v python3 >/dev/null 2>&1 && return 0
    if [[ -z "${_GO_PACK_PY3_WARNED}" ]]; then
        _GO_PACK_PY3_WARNED=1  # craftsman-ignore: WARN-SH001 - once per process, local would reset it
        echo "craftsman: python3 not found, every Go rule except GO005 was skipped" >&2
    fi
    return 1
}

_GO_PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GO_STRUCTURE_PY="${_GO_PACK_DIR}/go_structure.py"

# Which rules are reported as findings and which as advice. Severity itself is
# the rules engine's decision: add_violation and add_warning both resolve it,
# and the advisory defaults are declared in hooks/lib/rules-engine.sh with a
# mirror in ci/craftsman-ci.sh.
_go_emit_structure() {
    local file="$1" rule message
    _go_pack_has_python3 || return 0
    [[ -f "$_GO_STRUCTURE_PY" ]] || return 0
    while IFS='|' read -r rule message; do
        [[ -z "$rule" ]] && continue
        case "$rule" in
            GO003|GO004|GO006|WARN-GO001) add_warning "$rule" "$message" ;;
            *)                            add_violation "$rule" "$message" ;;
        esac
    done < <(python3 "$_GO_STRUCTURE_PY" "$file" 2>/dev/null)
}

# GO005: init() runs before anyone asked, in an order the language chooses.
_check_go005() {
    local file="$1"
    local init_line
    while IFS= read -r init_line; do
        [[ -z "$init_line" ]] && continue
        add_warning "GO005" "line ${init_line%%:*}: init() - initialise explicitly from main or a constructor"
    done < <(grep -nE '^func init\(\)' "$file" 2>/dev/null)
}

pack_validate_go() {
    local file="$1"
    _go_emit_structure "$file"
    _check_go005 "$file"
}
