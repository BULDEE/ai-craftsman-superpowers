#!/usr/bin/env bash
# =============================================================================
# Rust Regex Validator — Rust Pack
# Provides pack_validate_rust() for the pack-loader pipeline.
#
# Rules: RUST001-003, WARN-RUST001
# Requires: add_violation(), add_warning(), line_has_ignore()
# =============================================================================

pack_validate_rust() {
    local file="$1"

    # RUST001: No unwrap() in production code (except tests)
    if [[ "$file" != *"test"* && "$file" != *"_test.rs"* ]]; then
        local ln_num=0
        while IFS= read -r line; do
            ln_num=$((ln_num + 1))
            if echo "$line" | grep -qE '\.unwrap\(\)' 2>/dev/null; then
                if ! line_has_ignore "$line" "allow-unwrap"; then
                    add_violation "RUST001" ".unwrap() found — use ? operator or proper error handling (line $ln_num)"
                fi
            fi
        done < "$file"
    fi

    # RUST002: No panic! in library code
    if [[ "$file" != *"main.rs"* && "$file" != *"test"* ]]; then
        if grep -qE 'panic!\(' "$file" 2>/dev/null; then
            add_violation "RUST002" "panic!() in library code — return Result instead"
        fi
    fi

    # RUST003: No clone() without justification
    local clone_count
    clone_count=$(grep -cE '\.clone\(\)' "$file" 2>/dev/null; true)
    clone_count=${clone_count:-0}
    if [[ "$clone_count" -gt 3 ]]; then
        add_warning "RUST003" "Found $clone_count .clone() calls — review ownership patterns"
    fi

    # WARN-RUST001: Function too long (>40 lines for Rust)
    local func_start=0
    local brace_depth=0
    local in_func=false
    local ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE '^\s*(pub\s+)?(async\s+)?fn\s+' 2>/dev/null; then
            in_func=true
            func_start=$ln_num
            brace_depth=0
        fi
        if [[ "$in_func" == true ]]; then
            local opens closes
            opens=$(echo "$line" | tr -cd '{' | wc -c | tr -d ' ')
            closes=$(echo "$line" | tr -cd '}' | wc -c | tr -d ' ')
            brace_depth=$((brace_depth + opens - closes))
            if [[ $brace_depth -le 0 && $func_start -gt 0 ]]; then
                local func_len=$((ln_num - func_start))
                if [[ $func_len -gt 40 ]]; then
                    add_warning "WARN-RUST001" "Function at line $func_start is $func_len lines — consider extracting"
                fi
                in_func=false
            fi
        fi
    done < "$file"
}
