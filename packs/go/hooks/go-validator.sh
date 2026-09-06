#!/usr/bin/env bash
# =============================================================================
# Go Regex Validator - Go Pack
# Provides pack_validate_go() for the pack-loader pipeline.
#
# Rules: GO001-005, WARN-GO001, plus the core Structure rules (NEST001, LOC001,
#   GOD001, PARAM001) which this pack detects itself, see hooks/go_structure.py
#   and the metrics_dialect note in pack.yml.
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
        echo "craftsman: python3 not found, GO001, GO002, WARN-GO001, NEST001, LOC001, GOD001 and PARAM001 were not run" >&2
    fi
    return 1
}

_GO_PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GO_STRUCTURE_PY="${_GO_PACK_DIR}/go_structure.py"

# Rules the scanner owns, and how each one is reported. Severity is the rules
# engine's decision; add_violation and add_warning both resolve it, so the split
# here is only between "this is a finding" and "this is advice".
_go_emit_structure() {
    local file="$1" rule message
    _go_pack_has_python3 || return 0
    [[ -f "$_GO_STRUCTURE_PY" ]] || return 0
    while IFS='|' read -r rule message; do
        [[ -z "$rule" ]] && continue
        case "$rule" in
            WARN-GO001) add_warning "$rule" "$message" ;;
            *)          add_violation "$rule" "$message" ;;
        esac
    done < <(python3 "$_GO_STRUCTURE_PY" "$file" 2>/dev/null)
}

# GO003: an exported symbol with no doc comment on the line above it.
# Test files are exempt: nobody documents TestXxx, and golint does not either.
_check_go003() {
    local file="$1"
    case "$file" in *_test.go) return 0 ;; esac
    local previous="" line number=0
    while IFS= read -r line; do
        number=$((number + 1))
        if echo "$line" | grep -qE '^(func|type|var|const) [A-Z]|^func \([^)]*\) [A-Z]' 2>/dev/null; then
            if ! echo "$previous" | grep -qE '^\s*//' 2>/dev/null; then
                if ! line_has_ignore "$line" "GO003"; then
                    local symbol
                    symbol=$(echo "$line" | sed -E 's/^func \([^)]*\) /func /; s/^(func|type|var|const) ([A-Za-z0-9_]+).*/\2/')
                    add_warning "GO003" "line ${number}: exported ${symbol} has no doc comment"
                fi
            fi
        fi
        previous="$line"
    done < "$file"
}

# GO004: an error dropped into the blank identifier.
# The error is conventionally the last result, so `x, _ := f()` and `_ = f()`
# are the two shapes that discard it. `_, x := f()` discards the first value,
# which is usually a legitimate "I only want the second one".
_check_go004() {
    local file="$1"
    local discard_line
    while IFS= read -r discard_line; do
        [[ -z "$discard_line" ]] && continue
        local number="${discard_line%%:*}"
        local content="${discard_line#*:}"
        line_has_ignore "$content" "GO004" && continue
        add_warning "GO004" "line ${number}: result dropped into _ - handle the error or let it travel"
    done < <(grep -nE ',[[:space:]]*_[[:space:]]*:?=|^[[:space:]]*_[[:space:]]*=[[:space:]]*[A-Za-z_].*\(' "$file" 2>/dev/null)
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
    _check_go003 "$file"
    _check_go004 "$file"
    _check_go005 "$file"
}
