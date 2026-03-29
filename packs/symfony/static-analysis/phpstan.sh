#!/usr/bin/env bash
# =============================================================================
# Symfony Pack: PHPStan + Deptrac Static Analysis (Level 2 & 3)
# Graceful degradation: returns empty string if tools not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/symfony/static-analysis/phpstan.sh"
#   errors=$(pack_sa_php "/path/to/file.php")
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: map PHPStan error to craftsman violation code
# Format: "PHPSTAN<level>" — e.g. PHPSTAN001 for undefined var, PHPSTAN002 etc.
# PHPStan raw format: "path/to/file.php:42:message"
# ---------------------------------------------------------------------------
_pack_sa_phpstan_map_error() {
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
# pack_sa_php: Combined PHPStan + Deptrac analysis
# Returns: "CODE:LINE:MESSAGE" per line
# ---------------------------------------------------------------------------
pack_sa_php() {
    local file="$1"
    local errors=""

    # PHPStan analysis
    local phpstan=""
    if [[ -f "vendor/bin/phpstan" ]]; then
        phpstan="vendor/bin/phpstan"
    elif command -v phpstan &>/dev/null; then
        phpstan="phpstan"
    fi

    if [[ -n "$phpstan" ]]; then
        local output
        output=$(timeout 2 $phpstan analyse "$file" --level=max --no-progress --error-format=raw 2>/dev/null) || true
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # PHPStan raw format: "path/file.php:LINE MESSAGE"
                local lineno msg
                lineno=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
                msg=$(echo "$line" | sed -E 's/^[^:]+:[0-9]+//')
                local code
                code=$(_pack_sa_phpstan_map_error "$line")
                errors="${errors}${code}:${lineno:-0}:${msg}\n"
            done <<< "$output"
        fi
    fi

    # Deptrac analysis
    local deptrac=""
    if [[ -f "vendor/bin/deptrac" ]]; then
        deptrac="vendor/bin/deptrac"
    elif command -v deptrac &>/dev/null; then
        deptrac="deptrac"
    fi

    if [[ -n "$deptrac" ]]; then
        local output
        output=$(timeout 2 $deptrac analyse --no-progress --formatter=compact 2>/dev/null) || true
        if [[ -n "$output" ]]; then
            local basename_file
            basename_file=$(basename "$file")

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                echo "$line" | grep -q "$basename_file" || continue
                local lineno msg
                lineno=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
                msg="$line"
                errors="${errors}DEPTRAC001:${lineno:-0}:${msg}\n"
            done <<< "$output"
        fi
    fi

    [[ -n "$errors" ]] && echo -e "$errors"
}
