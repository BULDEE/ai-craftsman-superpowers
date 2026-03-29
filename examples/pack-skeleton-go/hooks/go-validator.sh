#!/usr/bin/env bash
# =============================================================================
# Go Regex Validator — Go Pack
# Provides pack_validate_go() for the pack-loader pipeline.
#
# Rules: GO001-003, WARN-GO001
# Requires: add_violation(), add_warning(), line_has_ignore(), metrics_record_violation()
# =============================================================================

pack_validate_go() {
    local file="$1"

    # GO001: No naked returns in functions with named return values
    # (simplified — real implementation would use AST)
    if grep -qE '^\s+return$' "$file" 2>/dev/null; then
        if grep -qE 'func.*\)\s*\(' "$file" 2>/dev/null; then
            add_warning "GO001" "Naked return found — consider explicit returns for clarity"
        fi
    fi

    # GO002: Error not checked (simplistic regex — catches common pattern)
    local ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        # Pattern: assignment without error variable (e.g., "result := doSomething()" without ", err")
        if echo "$line" | grep -qE ':=.*\(.*\)' 2>/dev/null; then
            if ! echo "$line" | grep -qE ', err' 2>/dev/null; then
                if echo "$line" | grep -qE '(Open|Read|Write|Close|Exec|Query|Parse|Decode|Encode|Marshal|Unmarshal)\(' 2>/dev/null; then
                    if ! line_has_ignore "$line" "no-err-check"; then
                        add_violation "GO002" "Possible unchecked error on I/O operation (line $ln_num)"
                    fi
                fi
            fi
        fi
    done < "$file"

    # GO003: No init() functions (prefer explicit initialization)
    if grep -qE '^func init\(\)' "$file" 2>/dev/null; then
        add_violation "GO003" "init() function found — prefer explicit initialization"
    fi

    # WARN-GO001: Function too long (>50 lines)
    local func_start=0
    local in_func=false
    ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE '^func ' 2>/dev/null; then
            in_func=true
            func_start=$ln_num
        fi
        if [[ "$in_func" == true ]] && echo "$line" | grep -qE '^\}$' 2>/dev/null; then
            local func_len=$((ln_num - func_start))
            if [[ $func_len -gt 50 ]]; then
                add_warning "WARN-GO001" "Function starting at line $func_start is $func_len lines — consider splitting"
            fi
            in_func=false
        fi
    done < "$file"
}
