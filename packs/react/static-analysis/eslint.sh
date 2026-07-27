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
    errors="$(_pack_sa_eslint_run "$file")$(_pack_sa_depcruise_run "$file")"
    [[ -n "$errors" ]] && echo -e "$errors"
}

# Deliberately NOT pinned to a safe config, unlike phpstan next door.
# phpstan is pinned because its bootstrapFiles key runs PHP while the
# config is merely being read, before any analysis is asked for. An eslint
# flat config is executable JavaScript by design, and running the
# project's rules IS what level 2 is for here: pinning a neutral config
# would leave eslint enforcing nothing. The consent gate is
# config_trust_project_tools, machine-owner only and off by default, and
# the plugin's own TS rules run at level 1 regardless.
_pack_sa_eslint_run() {
    local file="$1"
    local errors=""

    local eslint=""
    if [[ -f "node_modules/.bin/eslint" ]]; then
        eslint="node_modules/.bin/eslint"
    elif command -v npx &>/dev/null && [[ -f "node_modules/eslint/package.json" ]]; then
        eslint="npx eslint"
    fi
    [[ -n "$eslint" ]] || return 0

    local output
    output=$(sa_timeout "$SA_BUDGET_FILE_SECONDS" $eslint "$file" --format=compact --no-color 2>/dev/null) || true
    [[ -n "$output" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | grep -qi "error" || continue
        local lineno msg code
        lineno=$(echo "$line" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1)
        msg=$(echo "$line" | sed -E 's/^.*Error - //')
        code=$(_pack_sa_eslint_map_error "$line")
        errors="${errors}${code}:${lineno:-0}:${msg}\n"
    done <<< "$output"
    printf '%s' "$errors"
}

_pack_sa_depcruise_run() {
    local file="$1"
    local errors=""
    command -v npx &>/dev/null && [[ -f "node_modules/dependency-cruiser/package.json" ]] || return 0

    local output
    output=$(sa_timeout "$SA_BUDGET_PROJECT_SECONDS" npx depcruise "$file" --output-type err 2>/dev/null) || true
    [[ -n "$output" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        errors="${errors}ESLINT003:0:${line}\n"
    done <<< "$output"
    printf '%s' "$errors"
}
