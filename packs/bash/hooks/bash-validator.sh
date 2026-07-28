#!/usr/bin/env bash
# =============================================================================
# Bash/Shell Regex Validator - Bash Pack
# Provides pack_validate_bash() for the pack-loader pipeline.
#
# Rules: SH001-005, WARN-SH001
# Requires: add_violation(), add_warning(), line_has_ignore(), FILE_PATH
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

# A rule that cannot run is not a rule that passed. Every check below that
# needs python3 returned silently without it, so on a machine that has none the
# pack reported every file clean and nothing said otherwise. Same shape as the
# sqlite3 guard in metrics-db.sh. Announced once per process rather than once
# per rule, because the point is to be noticed, not to be noisy.
_SH_PACK_PY3_WARNED=""
_sh_pack_has_python3() {
    command -v python3 >/dev/null 2>&1 && return 0
    if [[ -z "${_SH_PACK_PY3_WARNED}" ]]; then
        _SH_PACK_PY3_WARNED=1
        echo "craftsman: python3 not found, SH002 and WARN-SH001 were not run" >&2
    fi
    return 1
}

_SH_PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Conventional short variable names allowed in shell scripts
_SH_ALLOWED_SHORT_VARS='(i|j|k|n|f|s|v|fd|IFS|FS|NR|NF|RS|OFS|ORS|OPTARG|OPTIND)'

# One function per rule. The dispatcher below was a single 138 line body,
# which is the smell its own SH002 reports on other people's code.
pack_validate_bash() {
    local file="$1"
    _sh_check_safety_options "$file"
    _sh_check_function_length "$file"
    _sh_check_short_names "$file"
    _sh_check_eval "$file"
    _sh_check_unquoted_paths "$file"
    _sh_check_missing_local "$file"
}

_sh_check_safety_options() {
    local file="$1"
    # SH001: Missing safety options (set -e, set -u, or set -o pipefail)
    # Check first 10 lines for set options or shebang with bash
    local has_set_e=false
    local has_set_u=false
    local head_content
    # The whole file, not the first 20 lines. A script whose header explains
    # why it exists pushes its `set -u` past line 20 and was then reported as
    # missing something it declares: the rule taxed the documentation the
    # doctrine asks for. Where the option sits does not change whether it is
    # set, so scanning everything cannot false-positive.
    head_content=$(cat "$file" 2>/dev/null)

    if echo "$head_content" | grep -qE '(set\s+-[a-z]*e|set\s+-o\s+errexit)' 2>/dev/null; then
        has_set_e=true
    fi
    if echo "$head_content" | grep -qE '(set\s+-[a-z]*u|set\s+-o\s+nounset)' 2>/dev/null; then
        has_set_u=true
    fi

    # Only check files with bash/sh shebang (not sourced libraries)
    if head -1 "$file" 2>/dev/null | grep -qE '^#!/' 2>/dev/null; then
        if [[ "$has_set_u" == false ]]; then
            add_warning "SH001" "Missing 'set -u' (nounset) - unbound variables won't be caught"
        fi
    fi
}

_sh_check_function_length() {
    local file="$1"
    # SH002. The measurement lives in its own file: it has to tell a shell
    # brace from a brace inside an embedded python or awk snippet, and that
    # logic cannot survive being escaped through a double-quoted bash string,
    # which is how it came to report lengths no function had.
    _sh_pack_has_python3 || return 0
    local function_warning
    while IFS= read -r function_warning; do
        [[ -z "$function_warning" ]] && continue
        add_violation "SH002" "$function_warning"
    done < <(python3 "${_SH_PACK_DIR}/bash_functions.py" length "$file" 2>/dev/null)
}

_sh_check_short_names() {
    local file="$1"
    # SH003: Single-char variable names in assignments (excluding conventional and loop vars)
    local short_var_line
    while IFS= read -r short_var_line; do
        [[ -z "$short_var_line" ]] && continue
        local lineno="${short_var_line%%:*}"
        add_warning "SH003" "line ${lineno}: Short variable name - use descriptive names"
    done < <(grep -nE '^\s*[a-z]{1,2}=' "$file" 2>/dev/null \
        | grep -vE "^\s*${_SH_ALLOWED_SHORT_VARS}=" \
        | grep -vE '(^\s*#|^\s*if |^\s*for |^\s*while )' \
        | head -5)
}

_sh_check_eval() {
    local file="$1"
    # SH004: eval usage (security risk - command injection vector)
    local eval_line
    while IFS= read -r eval_line; do
        [[ -z "$eval_line" ]] && continue
        add_violation "SH004" "line ${eval_line}: 'eval' found - security risk, use alternatives"
    done < <(grep -nE '^\s*eval\s' "$file" 2>/dev/null | cut -d: -f1)
}

_sh_check_unquoted_paths() {
    local file="$1"
    # SH005: Unquoted variable in dangerous contexts (rm, mv, cp, cat with variable paths)
    local unquoted_line
    while IFS= read -r unquoted_line; do
        [[ -z "$unquoted_line" ]] && continue
        local lineno="${unquoted_line%%:*}"
        add_warning "SH005" "line ${lineno}: Potentially unquoted variable in file operation"
    done < <(grep -nE '(rm|mv|cp|cat|chmod|chown)\s+(-[a-z]+\s+)*\$[a-zA-Z_]' "$file" 2>/dev/null \
        | grep -vE '"\$' \
        | head -5)
}

_sh_check_missing_local() {
    local file="$1"
    # WARN-SH001, through the same scanner as SH002: it carried its own copy of
    # the brace counting and therefore the same miscount.
    _sh_pack_has_python3 || return 0
    local no_local_warning
    while IFS= read -r no_local_warning; do
        [[ -z "$no_local_warning" ]] && continue
        add_warning "WARN-SH001" "$no_local_warning"
    done < <(python3 "${_SH_PACK_DIR}/bash_functions.py" locals "$file" 2>/dev/null)
}
