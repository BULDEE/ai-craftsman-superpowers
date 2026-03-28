#!/usr/bin/env bash
# =============================================================================
# Post-Write/Edit Validation Hook for Claude Code
# Validates written or edited files against craftsman coding standards.
#
# TRIGGERS: PostToolUse for Write and Edit tools
# EXIT CODES: 0 = pass (or warning), 2 = blocking violation
# OUTPUT: JSON with hookSpecificOutput or systemMessage
#
# Three validation levels:
#   Level 1: Regex (always, <50ms) — strict_types, final, any, setters
#   Level 2: Static analysis (if tools installed, <2s) — PHPStan, ESLint
#   Level 3: Architecture (if tools installed, <2s) — deptrac, dependency-cruiser
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load helpers
source "${SCRIPT_DIR}/lib/metrics-db.sh"
source "${SCRIPT_DIR}/lib/static-analysis.sh"
source "${SCRIPT_DIR}/lib/config.sh"

# Session state for correction learning
SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

_write_session_state() {
    local file="$1"
    local file_pattern
    file_pattern=$(metrics_file_pattern "$file")
    mkdir -p "$(dirname "$SESSION_STATE")"

    # Collect current blocked rules for this file
    local rules_json="["
    local first=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local r="${line%%:*}"
        if [[ "$first" == true ]]; then
            rules_json="${rules_json}\"${r}\""
            first=false
        else
            rules_json="${rules_json},\"${r}\""
        fi
    done <<< "$(echo -e "$CRITICAL_VIOLATIONS")"
    rules_json="${rules_json}]"

    # Merge into existing session state
    if [[ -f "$SESSION_STATE" ]]; then
        python3 -c "
import json, sys
sf, fp, rj = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
with open(sf) as f:
    state = json.load(f)
state.setdefault('blocked_violations', {})[fp] = rj
with open(sf, 'w') as f:
    json.dump(state, f)
" "$SESSION_STATE" "$file_pattern" "$rules_json" 2>/dev/null || true
    else
        python3 -c "
import json, sys
sf, fp, rj = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
with open(sf, 'w') as f:
    json.dump({'blocked_violations': {fp: rj}}, f)
" "$SESSION_STATE" "$file_pattern" "$rules_json" 2>/dev/null || true
    fi
}

_check_corrections() {
    local file="$1"
    local file_pattern
    file_pattern=$(metrics_file_pattern "$file")

    [[ ! -f "$SESSION_STATE" ]] && return

    local prev_rules
    prev_rules=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
rules = state.get('blocked_violations', {}).get(sys.argv[2], [])
print(' '.join(rules))
" "$SESSION_STATE" "$file_pattern" 2>/dev/null) || return

    [[ -z "$prev_rules" ]] && return

    for prev_rule in $prev_rules; do
        if echo -e "$CRITICAL_VIOLATIONS" | grep -q "^${prev_rule}:"; then
            : # Still violated, do nothing
        elif file_has_ignore "$prev_rule" 2>/dev/null; then
            metrics_record_correction "$prev_rule" "$file_pattern" "ignored" "craftsman-ignore added" 2>/dev/null || true
        else
            metrics_record_correction "$prev_rule" "$file_pattern" "fixed" "" 2>/dev/null || true
        fi
    done
}

# Init metrics DB (creates tables if needed, idempotent)
metrics_init 2>/dev/null || true

# Read tool input from stdin (JSON from Claude Code)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit silently if no file path or file doesn't exist
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Get file extension
EXT="${FILE_PATH##*.}"
FILE_PATTERN=$(metrics_file_pattern "$FILE_PATH")

# Violation accumulators
CRITICAL_VIOLATIONS=""
CRITICAL_COUNT=0
WARNING_VIOLATIONS=""
WARNING_COUNT=0

# =============================================================================
# craftsman-ignore support
# =============================================================================
line_has_ignore() {
    local line="$1"
    local rule="$2"
    # Exact rule match (with possible spaces around it)
    echo "$line" | grep -qE "craftsman-ignore:\s*${rule}(\s|$|,)" && return 0
    # Blanket ignore (no specific rule)
    echo "$line" | grep -qE "craftsman-ignore\s*$" && return 0
    return 1
}

file_has_ignore() {
    local rule="$1"
    grep -qE "craftsman-ignore:\s*${rule}(\s|$|,)" "$FILE_PATH" 2>/dev/null && return 0
    return 1
}

add_critical() {
    local rule="$1"
    local message="$2"
    local ignored=0

    if file_has_ignore "$rule"; then
        ignored=1
    fi

    if [[ $ignored -eq 0 ]]; then
        CRITICAL_VIOLATIONS="${CRITICAL_VIOLATIONS}${rule}: ${message}\n"
        ((CRITICAL_COUNT++)) || true
    fi

    # Always record in metrics (even if ignored)
    metrics_record_violation "$rule" "$FILE_PATTERN" "critical" $((1 - ignored)) "$ignored" 2>/dev/null || true
}

add_warning() {
    local rule="$1"
    local message="$2"
    metrics_record_violation "$rule" "$FILE_PATTERN" "warning" 0 0 2>/dev/null || true
    WARNING_VIOLATIONS="${WARNING_VIOLATIONS}${rule}: ${message}\n"
    ((WARNING_COUNT++)) || true
}

# =============================================================================
# Level 1: Regex Validation (always runs, <50ms)
# =============================================================================
validate_php_regex() {
    local file="$1"

    # PHP001: declare(strict_types=1) required
    if ! grep -q "declare(strict_types=1)" "$file" 2>/dev/null; then
        add_critical "PHP001" "Missing declare(strict_types=1)"
    fi

    # PHP002: Classes must be final (except interface/trait/abstract)
    if grep -q "^class " "$file" 2>/dev/null; then
        if ! grep -q "final class" "$file" 2>/dev/null; then
            if ! grep -qE "(interface |trait |abstract class )" "$file" 2>/dev/null; then
                add_critical "PHP002" "Class should be final"
            fi
        fi
    fi

    # PHP003: No public setters (check each line for craftsman-ignore)
    while IFS= read -r line; do
        if echo "$line" | grep -qE "public function set[A-Z]" 2>/dev/null; then
            if ! line_has_ignore "$line" "no-setter"; then
                add_critical "PHP003" "Public setter found — use behavioral methods"
            else
                metrics_record_violation "PHP003" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # PHP004: No new DateTime()
    if grep -q "new DateTime()" "$file" 2>/dev/null || grep -q "new \\\\DateTime()" "$file" 2>/dev/null; then
        add_critical "PHP004" "new DateTime() found — inject Clock instead"
    fi

    # PHP005: No empty catch blocks
    if grep -A1 "catch" "$file" 2>/dev/null | grep -qE "^\s*\}\s*$" 2>/dev/null; then
        add_warning "PHP005" "Possible empty catch block"
    fi

    # WARN-PHP001: Max 3 parameters
    if grep -qE "function\s+\w+\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-PHP001" "Method with 4+ parameters — consider refactoring to object"
    fi
}

validate_typescript_regex() {
    local file="$1"

    # TS001: No 'any' type (check per line for craftsman-ignore)
    while IFS= read -r line; do
        if echo "$line" | grep -qE ": any[^a-zA-Z]|<any>|: any$" 2>/dev/null; then
            if ! line_has_ignore "$line" "no-any"; then
                add_critical "TS001" "'any' type found — use proper types or 'unknown'"
            else
                metrics_record_violation "TS001" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # TS002: No default exports
    if grep -q "export default" "$file" 2>/dev/null; then
        add_critical "TS002" "Default export found — use named exports"
    fi

    # TS003: No non-null assertion (!) — exclude != and !==
    if grep -qE "[a-zA-Z0-9_\)]+\![^=\.]" "$file" 2>/dev/null; then
        add_critical "TS003" "Non-null assertion (!) found — handle null explicitly"
    fi

    # WARN-TS001: Max 3 parameters
    if grep -qE "(function\s+\w+|=>)\s*\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-TS001" "Function with 4+ parameters — consider refactoring to object"
    fi
}

# =============================================================================
# Level 2: Static Analysis (if tools installed, <2s timeout)
# =============================================================================
validate_static_analysis() {
    local file="$1"
    local errors
    errors=$(timeout 2 bash -c "source '${SCRIPT_DIR}/lib/static-analysis.sh'; sa_analyze_file '$file'" 2>/dev/null) || true

    if [[ -n "$errors" ]]; then
        local error_count
        error_count=$(echo "$errors" | grep -c "." || echo 0)
        add_warning "STATIC" "Static analysis found $error_count issue(s) — run locally for details"
    fi
}

# =============================================================================
# Layer Validation (checks BOTH path AND namespace)
# =============================================================================
validate_layer_regex() {
    local file="$1"

    local is_domain=false
    local is_application=false
    local is_domain_ts=false

    # PHP: Check path OR namespace
    if [[ "$file" == *"/Domain/"* ]] || grep -qE "namespace\s+App\\\\Domain" "$file" 2>/dev/null; then
        is_domain=true
    fi
    if [[ "$file" == *"/Application/"* ]] || grep -qE "namespace\s+App\\\\Application" "$file" 2>/dev/null; then
        is_application=true
    fi
    # TypeScript: Check path
    if [[ "$file" == *"/domain/"* ]]; then
        is_domain_ts=true
    fi

    # Domain must not import Infrastructure
    if [[ "$is_domain" == true ]] && [[ "$EXT" == "php" ]]; then
        if grep -qE "use\s+App\\\\Infrastructure" "$file" 2>/dev/null; then
            add_critical "LAYER001" "Domain imports Infrastructure — DDD layer violation"
        fi
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_critical "LAYER002" "Domain imports Presentation — DDD layer violation"
        fi
    fi

    # Application must not import Presentation
    if [[ "$is_application" == true ]] && [[ "$EXT" == "php" ]]; then
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_critical "LAYER003" "Application imports Presentation — DDD layer violation"
        fi
    fi

    # TypeScript: domain must not import infrastructure
    if [[ "$is_domain_ts" == true ]] && [[ "$EXT" == "ts" || "$EXT" == "tsx" ]]; then
        if grep -qE "from\s+['\"].*infrastructure" "$file" 2>/dev/null; then
            add_critical "LAYER001" "domain imports infrastructure — layer violation"
        fi
    fi
}

# =============================================================================
# Run Validation
# =============================================================================

case "$EXT" in
    php)
        if config_php_enabled; then
            validate_php_regex "$FILE_PATH"
            validate_layer_regex "$FILE_PATH"
            validate_static_analysis "$FILE_PATH"
        fi
        ;;
    ts|tsx)
        if config_ts_enabled; then
            validate_typescript_regex "$FILE_PATH"
            validate_layer_regex "$FILE_PATH"
            validate_static_analysis "$FILE_PATH"
        fi
        ;;
esac

# Check for corrections (violation fixed since last block)
_check_corrections "$FILE_PATH"

# =============================================================================
# Output Decision
# =============================================================================

if [[ $CRITICAL_COUNT -gt 0 ]]; then
    # Check if ANY critical violation should actually block based on config
    local_should_block=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local_rule="${line%%:*}"
        if config_should_block "$local_rule"; then
            local_should_block=true
            break
        fi
    done <<< "$(echo -e "$CRITICAL_VIOLATIONS")"

    if [[ "$local_should_block" == true ]]; then
        # Write session state for correction learning
        _write_session_state "$FILE_PATH"
        jq -n --arg violations "$(echo -e "$CRITICAL_VIOLATIONS")" \
               --arg count "$CRITICAL_COUNT" \
        '{
            hookSpecificOutput: {
                hookEventName: "PostToolUse",
                additionalContext: ("BLOCKED: " + $count + " critical violation(s):\n" + $violations + "\nFix these before proceeding. Use // craftsman-ignore: <rule> to suppress if justified.")
            }
        }'
        exit 2
    else
        # Downgrade to warnings
        WARNING_VIOLATIONS="${CRITICAL_VIOLATIONS}${WARNING_VIOLATIONS}"
        WARNING_COUNT=$((WARNING_COUNT + CRITICAL_COUNT))
        CRITICAL_COUNT=0
    fi
fi

if [[ $WARNING_COUNT -gt 0 ]]; then
    jq -n --arg warnings "$(echo -e "$WARNING_VIOLATIONS")" \
           --arg count "$WARNING_COUNT" \
    '{
        systemMessage: ("WARNINGS: " + $count + " issue(s) detected:\n" + $warnings)
    }'
    exit 0
fi

exit 0
