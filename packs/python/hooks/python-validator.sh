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

pack_validate_python() {
    local file="$1"

    # PY001: Single-char or 2-char variable names (excluding conventional: i, j, k, x, y, f, e, n, ok, id, os, re, io, db)
    local line_number
    while IFS= read -r line_number; do
        [[ -z "$line_number" ]] && continue
        add_violation "PY001" "line ${line_number}: Single/double-char variable name — use descriptive names"
    done < <(grep -nE '^\s+((for)\s+)?[a-z]{1,2}\s*[=,\s]' "$file" 2>/dev/null \
        | grep -vE '\b(i|j|k|x|y|f|e|n|ok|id|os|re|io|db|if|in|is|or|as|do|to|up|no)\b\s*[=,\s]' \
        | grep -vE '(import|from|#|def |class |return |elif )' \
        | cut -d: -f1)

    # PY002: Function longer than 25 lines (SRP indicator)
    if command -v python3 >/dev/null 2>&1; then
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
    fi

    # PY003: Missing type hints on public functions
    local function_line
    while IFS= read -r function_line; do
        [[ -z "$function_line" ]] && continue
        local lineno="${function_line%%:*}"
        local content="${function_line#*:}"
        # Skip private/protected functions (start with _)
        if echo "$content" | grep -qE '^\s*def\s+[^_]' 2>/dev/null; then
            # Check for missing return type hint (no ->)
            if ! echo "$content" | grep -q '\->' 2>/dev/null; then
                add_warning "PY003" "line ${lineno}: Public function missing return type hint"
            fi
        fi
    done < <(grep -nE '^\s*def\s+' "$file" 2>/dev/null)

    # PY004: Bare except (catches everything including KeyboardInterrupt)
    local bare_except_line
    while IFS= read -r bare_except_line; do
        [[ -z "$bare_except_line" ]] && continue
        add_violation "PY004" "line ${bare_except_line}: Bare 'except:' — catch specific exceptions"
    done < <(grep -nE '^\s*except\s*:' "$file" 2>/dev/null | cut -d: -f1)

    # PY005: Mutable default arguments (list, dict, set as default)
    local mutable_default_line
    while IFS= read -r mutable_default_line; do
        [[ -z "$mutable_default_line" ]] && continue
        add_violation "PY005" "line ${mutable_default_line}: Mutable default argument — use None + assignment"
    done < <(grep -nE 'def\s+\w+\(.*=\s*(\[\]|\{\}|set\(\))' "$file" 2>/dev/null | cut -d: -f1)

    # WARN-PY001: Max 3 parameters
    if grep -qE 'def\s+\w+\(([^,]+,){3,}' "$file" 2>/dev/null; then
        add_warning "WARN-PY001" "Function with 4+ parameters — consider refactoring to dataclass/object"
    fi
}
