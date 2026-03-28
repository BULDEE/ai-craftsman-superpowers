#!/usr/bin/env bash
# =============================================================================
# Static Analysis Wrappers (Level 2 & 3)
# Graceful degradation: returns empty string if tools not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/static-analysis.sh"
#   errors=$(sa_phpstan "/path/to/file.php")
#   errors=$(sa_eslint "/path/to/file.ts")
#   errors=$(sa_layer_check "/path/to/file.php")
# =============================================================================

sa_phpstan() {
    local file="$1"
    local phpstan=""
    if [[ -f "vendor/bin/phpstan" ]]; then
        phpstan="vendor/bin/phpstan"
    elif command -v phpstan &>/dev/null; then
        phpstan="phpstan"
    else
        return 0
    fi
    local output
    output=$($phpstan analyse "$file" --level=max --no-progress --error-format=raw 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output"
}

sa_eslint() {
    local file="$1"
    local eslint=""
    if [[ -f "node_modules/.bin/eslint" ]]; then
        eslint="node_modules/.bin/eslint"
    elif command -v npx &>/dev/null && [[ -f "node_modules/eslint/package.json" ]]; then
        eslint="npx eslint"
    else
        return 0
    fi
    local output
    output=$($eslint "$file" --format=compact --no-color 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output" | grep -i "error" || true
}

sa_deptrac() {
    local file="$1"
    local deptrac=""
    if [[ -f "vendor/bin/deptrac" ]]; then
        deptrac="vendor/bin/deptrac"
    elif command -v deptrac &>/dev/null; then
        deptrac="deptrac"
    else
        return 0
    fi
    local output
    output=$($deptrac analyse --no-progress --formatter=compact 2>/dev/null) || true
    if [[ -n "$output" ]] && echo "$output" | grep -q "$(basename "$file")"; then
        echo "$output" | grep "$(basename "$file")"
    fi
}

sa_depcruise() {
    local file="$1"
    if ! command -v npx &>/dev/null || ! [[ -f "node_modules/dependency-cruiser/package.json" ]]; then
        return 0
    fi
    local output
    output=$(npx depcruise "$file" --output-type err 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output"
}

sa_analyze_file() {
    local file="$1"
    local ext="${file##*.}"
    local errors=""
    case "$ext" in
        php)
            local phpstan_out
            phpstan_out=$(sa_phpstan "$file")
            [[ -n "$phpstan_out" ]] && errors="${errors}${phpstan_out}\n"
            local deptrac_out
            deptrac_out=$(sa_deptrac "$file")
            [[ -n "$deptrac_out" ]] && errors="${errors}${deptrac_out}\n"
            ;;
        ts|tsx)
            local eslint_out
            eslint_out=$(sa_eslint "$file")
            [[ -n "$eslint_out" ]] && errors="${errors}${eslint_out}\n"
            local depcruise_out
            depcruise_out=$(sa_depcruise "$file")
            [[ -n "$depcruise_out" ]] && errors="${errors}${depcruise_out}\n"
            ;;
    esac
    [[ -n "$errors" ]] && echo -e "$errors"
}
