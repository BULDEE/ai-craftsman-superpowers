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
#   structured=$(sa_phpstan_structured "/path/to/file.php")
#   structured=$(sa_eslint_structured "/path/to/file.ts")
#   structured=$(sa_deptrac_structured "/path/to/file.php")
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: map PHPStan error to craftsman violation code
# Format: "PHPSTAN<level>" — e.g. PHPSTAN001 for undefined var, PHPSTAN002 etc.
# PHPStan raw format: "path/to/file.php:42:message"
# ---------------------------------------------------------------------------
_sa_map_phpstan_error() {
    local line="$1"
    local rule="PHPSTAN001"
    # Heuristics: assign specific codes based on common error patterns
    if echo "$line" | grep -qi "undefined variable\|Undefined variable"; then
        rule="PHPSTAN002"
    elif echo "$line" | grep -qi "call to undefined\|Call to undefined"; then
        rule="PHPSTAN003"
    elif echo "$line" | grep -qi "Cannot access\|cannot access"; then
        rule="PHPSTAN004"
    elif echo "$line" | grep -qi "does not exist\|not found"; then
        rule="PHPSTAN005"
    fi
    echo "$rule"
}

# ---------------------------------------------------------------------------
# Internal: map ESLint error to craftsman violation code
# ESLint compact format: "file:line:col: Error - message (rule-id)"
# ---------------------------------------------------------------------------
_sa_map_eslint_error() {
    local line="$1"
    local rule_id
    rule_id=$(echo "$line" | grep -oE '\(([a-zA-Z0-9@/_-]+)\)$' | tr -d '()')
    if [[ -n "$rule_id" ]]; then
        # Normalize rule-id to ESLINT code
        case "$rule_id" in
            "@typescript-eslint/no-explicit-any"|"no-explicit-any") echo "ESLINT001" ;;
            "@typescript-eslint/no-unsafe-*"|"no-unsafe-assignment") echo "ESLINT002" ;;
            "import/no-cycle"|"import/no-restricted-paths") echo "ESLINT003" ;;
            "no-unused-vars"|"@typescript-eslint/no-unused-vars") echo "ESLINT004" ;;
            *) echo "ESLINT001" ;;
        esac
    else
        echo "ESLINT001"
    fi
}

# ---------------------------------------------------------------------------
# PHPStan: raw output (backward compat)
# ---------------------------------------------------------------------------
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
    output=$(timeout 2 $phpstan analyse "$file" --level=max --no-progress --error-format=raw 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output"
}

# ---------------------------------------------------------------------------
# PHPStan: structured output — "PHPSTAN001:42:message"
# Returns one line per error: CODE:LINE:MESSAGE
# ---------------------------------------------------------------------------
sa_phpstan_structured() {
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
    output=$(timeout 2 $phpstan analyse "$file" --level=max --no-progress --error-format=raw 2>/dev/null) || true
    [[ -z "$output" ]] && return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # PHPStan raw format: "path/file.php:LINE MESSAGE"
        local lineno msg
        lineno=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        msg=$(echo "$line" | sed -E 's/^[^:]+:[0-9]+//')
        local code
        code=$(_sa_map_phpstan_error "$line")
        echo "${code}:${lineno:-0}:${msg}"
    done <<< "$output"
}

# ---------------------------------------------------------------------------
# ESLint: raw output (backward compat)
# ---------------------------------------------------------------------------
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
    output=$(timeout 2 $eslint "$file" --format=compact --no-color 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output" | grep -i "error" || true
}

# ---------------------------------------------------------------------------
# ESLint: structured output — "ESLINT001:42:message"
# Returns one line per error: CODE:LINE:MESSAGE
# ---------------------------------------------------------------------------
sa_eslint_structured() {
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
    output=$(timeout 2 $eslint "$file" --format=compact --no-color 2>/dev/null) || true
    [[ -z "$output" ]] && return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | grep -qi "error" || continue
        # ESLint compact: "file: line X, col Y, Error - msg (rule)"
        local lineno msg
        lineno=$(echo "$line" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1)
        msg=$(echo "$line" | sed -E 's/^.*Error - //')
        local code
        code=$(_sa_map_eslint_error "$line")
        echo "${code}:${lineno:-0}:${msg}"
    done <<< "$output"
}

# ---------------------------------------------------------------------------
# deptrac: raw output (backward compat)
# ---------------------------------------------------------------------------
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
    output=$(timeout 2 $deptrac analyse --no-progress --formatter=compact 2>/dev/null) || true
    if [[ -n "$output" ]] && echo "$output" | grep -q "$(basename "$file")"; then
        echo "$output" | grep "$(basename "$file")"
    fi
}

# ---------------------------------------------------------------------------
# deptrac: structured output — "DEPTRAC001:LINE:message" (Level 3)
# Returns one line per violation involving the given file.
# ---------------------------------------------------------------------------
sa_deptrac_structured() {
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
    output=$(timeout 2 $deptrac analyse --no-progress --formatter=compact 2>/dev/null) || true
    [[ -z "$output" ]] && return 0

    local basename_file
    basename_file=$(basename "$file")

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | grep -q "$basename_file" || continue
        local lineno msg
        lineno=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        msg="$line"
        echo "DEPTRAC001:${lineno:-0}:${msg}"
    done <<< "$output"
}

sa_depcruise() {
    local file="$1"
    if ! command -v npx &>/dev/null || ! [[ -f "node_modules/dependency-cruiser/package.json" ]]; then
        return 0
    fi
    local output
    output=$(timeout 2 npx depcruise "$file" --output-type err 2>/dev/null) || true
    [[ -n "$output" ]] && echo "$output"
}

sa_analyze_file() {
    local file="$1"
    local ext="${file##*.}"
    local errors=""
    case "$ext" in
        php)
            local phpstan_out
            phpstan_out=$(sa_phpstan_structured "$file")
            [[ -n "$phpstan_out" ]] && errors="${errors}${phpstan_out}\n"
            local deptrac_out
            deptrac_out=$(sa_deptrac_structured "$file")
            [[ -n "$deptrac_out" ]] && errors="${errors}${deptrac_out}\n"
            ;;
        ts|tsx)
            local eslint_out
            eslint_out=$(sa_eslint_structured "$file")
            [[ -n "$eslint_out" ]] && errors="${errors}${eslint_out}\n"
            local depcruise_out
            depcruise_out=$(sa_depcruise "$file")
            [[ -n "$depcruise_out" ]] && errors="${errors}ESLINT003:0:${depcruise_out}\n"
            ;;
    esac
    [[ -n "$errors" ]] && echo -e "$errors"
}
