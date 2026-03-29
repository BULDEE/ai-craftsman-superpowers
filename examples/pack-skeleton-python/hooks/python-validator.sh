#!/usr/bin/env bash
# =============================================================================
# Python Regex Validator — Python Pack
# Provides pack_validate_python() for the pack-loader pipeline.
#
# Rules: PY001-003, WARN-PY001
# Requires: add_violation(), add_warning(), line_has_ignore()
# =============================================================================

pack_validate_python() {
    local file="$1"

    # PY001: No bare except
    local ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE '^\s*except\s*:' 2>/dev/null; then
            if ! line_has_ignore "$line" "allow-bare-except"; then
                add_violation "PY001" "Bare except found — catch specific exceptions (line $ln_num)"
            fi
        fi
    done < "$file"

    # PY002: No mutable default arguments
    ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE 'def\s+\w+\(.*=\s*(\[\]|\{\}|\bset\(\))' 2>/dev/null; then
            add_violation "PY002" "Mutable default argument found (line $ln_num) — use None and assign in body"
        fi
    done < "$file"

    # PY003: No wildcard imports
    if grep -qE '^\s*from\s+\S+\s+import\s+\*' "$file" 2>/dev/null; then
        add_violation "PY003" "Wildcard import found — use explicit imports"
    fi

    # WARN-PY001: Missing type hints on public functions
    ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        # Public function (no leading _) without return type annotation
        if echo "$line" | grep -qE '^\s*def\s+[a-zA-Z][a-zA-Z0-9_]*\(' 2>/dev/null; then
            if ! echo "$line" | grep -qE '\)\s*->' 2>/dev/null; then
                # Skip __init__, __str__, etc.
                if ! echo "$line" | grep -qE 'def\s+__' 2>/dev/null; then
                    add_warning "WARN-PY001" "Public function at line $ln_num missing return type hint"
                fi
            fi
        fi
    done < "$file"
}
