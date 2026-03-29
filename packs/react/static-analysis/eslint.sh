#!/usr/bin/env bash
# =============================================================================
# React Pack: ESLint + Dependency-Cruiser Static Analysis (Level 2 & 3)
# Graceful degradation: returns empty string if tools not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/react/static-analysis/eslint.sh"
#   errors=$(pack_sa_typescript "/path/to/file.ts")
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: map ESLint error to craftsman violation code
# ESLint compact format: "file:line:col: Error - message (rule-id)"
# ---------------------------------------------------------------------------
_pack_sa_eslint_map_error() {
    local line="$1"
    local rule_id
    rule_id=$(echo "$line" | grep -oE '\(([a-zA-Z0-9@/_-]+)\)$' | tr -d '()')
    if [[ -n "$rule_id" ]]; then
        # Normalize rule-id to ESLINT code
        case "$rule_id" in
            "@typescript-eslint/no-explicit-any"|"no-explicit-any") echo "ESLINT001" ;;
            "@typescript-eslint/no-unsafe-"*|"no-unsafe-assignment") echo "ESLINT002" ;;
            "import/no-cycle"|"import/no-restricted-paths") echo "ESLINT003" ;;
            "no-unused-vars"|"@typescript-eslint/no-unused-vars") echo "ESLINT004" ;;
            *) echo "ESLINT001" ;;
        esac
    else
        echo "ESLINT001"
    fi
}

# ---------------------------------------------------------------------------
# pack_sa_typescript: Combined ESLint + Dependency-Cruiser analysis
# Returns: "CODE:LINE:MESSAGE" per line
# ---------------------------------------------------------------------------
pack_sa_typescript() {
    local file="$1"
    local errors=""

    # ESLint analysis
    local eslint=""
    if [[ -f "node_modules/.bin/eslint" ]]; then
        eslint="node_modules/.bin/eslint"
    elif command -v npx &>/dev/null && [[ -f "node_modules/eslint/package.json" ]]; then
        eslint="npx eslint"
    fi

    if [[ -n "$eslint" ]]; then
        local output
        output=$(timeout 2 $eslint "$file" --format=compact --no-color 2>/dev/null) || true
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                echo "$line" | grep -qi "error" || continue
                # ESLint compact: "file: line X, col Y, Error - msg (rule)"
                local lineno msg
                lineno=$(echo "$line" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1)
                msg=$(echo "$line" | sed -E 's/^.*Error - //')
                local code
                code=$(_pack_sa_eslint_map_error "$line")
                errors="${errors}${code}:${lineno:-0}:${msg}\n"
            done <<< "$output"
        fi
    fi

    # Dependency-Cruiser analysis
    if command -v npx &>/dev/null && [[ -f "node_modules/dependency-cruiser/package.json" ]]; then
        local output
        output=$(timeout 2 npx depcruise "$file" --output-type err 2>/dev/null) || true
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                errors="${errors}ESLINT003:0:${line}\n"
            done <<< "$output"
        fi
    fi

    [[ -n "$errors" ]] && echo -e "$errors"
}
