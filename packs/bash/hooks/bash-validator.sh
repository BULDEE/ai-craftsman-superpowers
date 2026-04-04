#!/usr/bin/env bash
# =============================================================================
# Bash/Shell Regex Validator — Bash Pack
# Provides pack_validate_bash() for the pack-loader pipeline.
#
# Rules: SH001-005, WARN-SH001
# Requires: add_violation(), add_warning(), line_has_ignore(), FILE_PATH
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail — it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

# Conventional short variable names allowed in shell scripts
_SH_ALLOWED_SHORT_VARS='(i|j|k|n|f|s|v|fd|IFS|FS|NR|NF|RS|OFS|ORS|OPTARG|OPTIND)'

pack_validate_bash() {
    local file="$1"

    # SH001: Missing safety options (set -e, set -u, or set -o pipefail)
    # Check first 10 lines for set options or shebang with bash
    local has_set_e=false
    local has_set_u=false
    local head_content
    head_content=$(head -20 "$file" 2>/dev/null)

    if echo "$head_content" | grep -qE '(set\s+-[a-z]*e|set\s+-o\s+errexit)' 2>/dev/null; then
        has_set_e=true
    fi
    if echo "$head_content" | grep -qE '(set\s+-[a-z]*u|set\s+-o\s+nounset)' 2>/dev/null; then
        has_set_u=true
    fi

    # Only check files with bash/sh shebang (not sourced libraries)
    if head -1 "$file" 2>/dev/null | grep -qE '^#!/' 2>/dev/null; then
        if [[ "$has_set_u" == false ]]; then
            add_warning "SH001" "Missing 'set -u' (nounset) — unbound variables won't be caught"
        fi
    fi

    # SH002: Function longer than 30 lines (more lenient than Python — shell functions tend to be longer)
    if command -v python3 >/dev/null 2>&1; then
        local function_warning
        while IFS= read -r function_warning; do
            [[ -z "$function_warning" ]] && continue
            add_violation "SH002" "$function_warning"
        done < <(python3 -c "
import re, sys
lines = open(sys.argv[1]).readlines()
func_pattern = re.compile(r'^\s*(\w[\w_-]*)\s*\(\)\s*\{?\s*$|^(\w[\w_-]*)\(\)\s*\{')
brace_func = re.compile(r'^\s*(\w[\w_-]*)\s*\(\)\s*\{')
current_func = None
func_start = 0
brace_depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    match = func_pattern.match(stripped) or brace_func.match(stripped)
    if match and brace_depth == 0:
        func_name = match.group(1) or match.group(2)
        if current_func and (i - func_start) > 30:
            print(f'line {func_start}: function {current_func}() is {i - func_start} lines — consider extracting')
        current_func = func_name
        func_start = i
        brace_depth = stripped.count('{') - stripped.count('}')
    elif current_func:
        brace_depth += stripped.count('{') - stripped.count('}')
        if brace_depth <= 0 and current_func:
            length = i - func_start + 1
            if length > 30:
                print(f'line {func_start}: function {current_func}() is {length} lines — consider extracting')
            current_func = None
            brace_depth = 0
if current_func:
    length = len(lines) - func_start + 1
    if length > 30:
        print(f'line {func_start}: function {current_func}() is {length} lines — consider extracting')
" "$file" 2>/dev/null)
    fi

    # SH003: Single-char variable names in assignments (excluding conventional and loop vars)
    local short_var_line
    while IFS= read -r short_var_line; do
        [[ -z "$short_var_line" ]] && continue
        local lineno="${short_var_line%%:*}"
        add_warning "SH003" "line ${lineno}: Short variable name — use descriptive names"
    done < <(grep -nE '^\s*[a-z]{1,2}=' "$file" 2>/dev/null \
        | grep -vE "^\s*${_SH_ALLOWED_SHORT_VARS}=" \
        | grep -vE '(^\s*#|^\s*if |^\s*for |^\s*while )' \
        | head -5)

    # SH004: eval usage (security risk — command injection vector)
    local eval_line
    while IFS= read -r eval_line; do
        [[ -z "$eval_line" ]] && continue
        add_violation "SH004" "line ${eval_line}: 'eval' found — security risk, use alternatives"
    done < <(grep -nE '^\s*eval\s' "$file" 2>/dev/null | cut -d: -f1)

    # SH005: Unquoted variable in dangerous contexts (rm, mv, cp, cat with variable paths)
    local unquoted_line
    while IFS= read -r unquoted_line; do
        [[ -z "$unquoted_line" ]] && continue
        local lineno="${unquoted_line%%:*}"
        add_warning "SH005" "line ${lineno}: Potentially unquoted variable in file operation"
    done < <(grep -nE '(rm|mv|cp|cat|chmod|chown)\s+(-[a-z]+\s+)*\$[a-zA-Z_]' "$file" 2>/dev/null \
        | grep -vE '"\$' \
        | head -5)

    # WARN-SH001: Function without local variable declarations
    if command -v python3 >/dev/null 2>&1; then
        local no_local_warning
        while IFS= read -r no_local_warning; do
            [[ -z "$no_local_warning" ]] && continue
            add_warning "WARN-SH001" "$no_local_warning"
        done < <(python3 -c "
import re, sys
lines = open(sys.argv[1]).readlines()
func_start_re = re.compile(r'^\s*(\w[\w_-]*)\s*\(\)\s*\{')
in_func = False
func_name = ''
func_line = 0
has_local = False
has_assignment = False
depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    match = func_start_re.match(stripped)
    if match and depth == 0:
        if in_func and has_assignment and not has_local:
            print(f'line {func_line}: function {func_name}() assigns variables without local declarations')
        in_func = True
        func_name = match.group(1)
        func_line = i
        has_local = False
        has_assignment = False
        depth = stripped.count('{') - stripped.count('}')
    elif in_func:
        depth += stripped.count('{') - stripped.count('}')
        if 'local ' in stripped:
            has_local = True
        if re.match(r'^\s*[a-zA-Z_]\w*=', stripped) and not stripped.startswith('#'):
            has_assignment = True
        if depth <= 0:
            if has_assignment and not has_local:
                print(f'line {func_line}: function {func_name}() assigns variables without local declarations')
            in_func = False
            depth = 0
" "$file" 2>/dev/null)
    fi
}
