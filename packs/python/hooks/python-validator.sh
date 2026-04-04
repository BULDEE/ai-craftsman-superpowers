#!/usr/bin/env bash
# =============================================================================
# Python Regex Validator — Python Pack
# Provides pack_validate_python() for the pack-loader pipeline.
#
# Rules: PY001-005, WARN-PY001
# Requires: add_violation(), add_warning(), line_has_ignore(), FILE_PATH
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail — it would affect the sourcing script.
# craftsman-ignore: SH001
# =============================================================================

_check_py001() {
    local file="$1"
    local line_number
    while IFS= read -r line_number; do
        [[ -z "$line_number" ]] && continue
        add_violation "PY001" "line ${line_number}: Single/double-char variable name — use descriptive names"
    done < <(grep -nE '^\s+((for)\s+)?[a-z]{1,2}\s*[=,[:space:]]' "$file" 2>/dev/null \
        | grep -vE '\b(i|j|k|x|y|f|e|n|ok|id|os|re|io|db|if|in|is|or|as|do|to|up|no)\b\s*[=,[:space:]]' \
        | grep -vE '(import|from|#|def |class |return |elif )' \
        | cut -d: -f1)
}

_check_py002() {
    local file="$1"
    command -v python3 >/dev/null 2>&1 || return 0
    local warning_message
    while IFS= read -r warning_message; do
        [[ -z "$warning_message" ]] && continue
        add_violation "PY002" "$warning_message"
    done < <(python3 -c "
import ast, sys
try:
    tree = ast.parse(open(sys.argv[1]).read())
except SyntaxError:
    sys.exit(0)
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        body_lines = node.end_lineno - node.lineno
        if body_lines > 25:
            print(f'line {node.lineno}: function {node.name}() is {body_lines} lines — consider extracting')
" "$file" 2>/dev/null)
}

_check_py003() {
    local file="$1"
    local function_line
    while IFS= read -r function_line; do
        [[ -z "$function_line" ]] && continue
        local lineno="${function_line%%:*}"
        local content="${function_line#*:}"
        if echo "$content" | grep -qE '^\s*def\s+[^_]' 2>/dev/null; then
            if ! echo "$content" | grep -q '\->' 2>/dev/null; then
                add_warning "PY003" "line ${lineno}: Public function missing return type hint"
            fi
        fi
    done < <(grep -nE '^\s*def\s+' "$file" 2>/dev/null)
}

_check_py004() {
    local file="$1"
    local bare_except_line
    while IFS= read -r bare_except_line; do
        [[ -z "$bare_except_line" ]] && continue
        add_violation "PY004" "line ${bare_except_line}: Bare 'except:' — catch specific exceptions"
    done < <(grep -nE '^\s*except\s*:' "$file" 2>/dev/null | cut -d: -f1)
}

_check_py005() {
    local file="$1"
    local mutable_default_line
    while IFS= read -r mutable_default_line; do
        [[ -z "$mutable_default_line" ]] && continue
        add_violation "PY005" "line ${mutable_default_line}: Mutable default argument — use None + assignment"
    done < <(grep -nE 'def\s+\w+\(.*=\s*(\[\]|\{\}|set\(\))' "$file" 2>/dev/null | cut -d: -f1)
}

_check_warn_py001() {
    local file="$1"
    if grep -qE 'def\s+\w+\(([^,]+,){3,}' "$file" 2>/dev/null; then
        add_warning "WARN-PY001" "Function with 4+ parameters — consider refactoring to dataclass/object"
    fi
}

pack_validate_python() {
    local file="$1"
    _check_py001 "$file"
    _check_py002 "$file"
    _check_py003 "$file"
    _check_py004 "$file"
    _check_py005 "$file"
    _check_warn_py001 "$file"
}
