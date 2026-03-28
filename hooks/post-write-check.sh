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
source "${SCRIPT_DIR}/lib/rules-engine.sh"
rules_init "$PWD" "${HOME}/.claude"

# Session state for correction learning
SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

_write_session_state() {
    local file="$1"
    local file_pattern
    file_pattern=$(metrics_file_pattern "$file")
    mkdir -p "$(dirname "$SESSION_STATE")"

    # Extract directory bucket for cross-file pattern grouping
    local dir_bucket
    dir_bucket=$(dirname "$file" | sed -E "s|${PWD}/||")

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

    # Merge into existing session state (including cross-file pattern tracking)
    if [[ -f "$SESSION_STATE" ]]; then
        python3 -c "
import json, sys
sf, fp, dir_b, rj = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
with open(sf) as f:
    state = json.load(f)
state.setdefault('blocked_violations', {})[fp] = rj

# Cross-file pattern tracking: group rule violations by directory
patterns = state.setdefault('patterns', {})
for rule in rj:
    dir_patterns = patterns.setdefault(rule, {})
    files_in_dir = dir_patterns.setdefault(dir_b, [])
    if fp not in files_in_dir:
        files_in_dir.append(fp)

with open(sf, 'w') as f:
    json.dump(state, f)
" "$SESSION_STATE" "$file_pattern" "$dir_bucket" "$rules_json" 2>/dev/null || true
    else
        python3 -c "
import json, sys
sf, fp, dir_b, rj = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
patterns = {}
for rule in rj:
    patterns.setdefault(rule, {}).setdefault(dir_b, []).append(fp)
with open(sf, 'w') as f:
    json.dump({'blocked_violations': {fp: rj}, 'patterns': patterns}, f)
" "$SESSION_STATE" "$file_pattern" "$dir_bucket" "$rules_json" 2>/dev/null || true
    fi
}

# Detect cross-file patterns: same rule in 3+ files → suggest project-wide fix
_detect_cross_file_patterns() {
    [[ ! -f "$SESSION_STATE" ]] && return

    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
patterns = state.get('patterns', {})
suggestions = []
for rule, dir_map in patterns.items():
    # Count total unique files across all dirs for this rule
    all_files = set()
    for files in dir_map.values():
        all_files.update(files)
    if len(all_files) >= 3:
        suggestions.append('PATTERN:' + rule + ':' + str(len(all_files)) + ' files')
    # Check per-directory grouping
    for dir_b, files in dir_map.items():
        if len(files) >= 2 and dir_b not in ('', '.'):
            suggestions.append('DIR_PATTERN:' + rule + ':' + dir_b + ':' + str(len(files)) + ' files')
for s in suggestions:
    print(s)
" "$SESSION_STATE" 2>/dev/null || true
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
# craftsman-ignore support (single rule and multi-rule: PHP001, TS001, LAYER001)
# =============================================================================
line_has_ignore() {
    local line="$1"
    local rule="$2"
    # Multi-rule or single rule: "craftsman-ignore: PHP001, TS001, LAYER001"
    # Check if the specific rule appears in the comma-separated list
    if echo "$line" | grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" 2>/dev/null; then
        return 0
    fi
    # Blanket ignore (no specific rule — just "craftsman-ignore" with no colon or empty list)
    if echo "$line" | grep -qE "craftsman-ignore\s*$" 2>/dev/null; then
        return 0
    fi
    return 1
}

file_has_ignore() {
    local rule="$1"
    # Multi-rule or single rule anywhere in the file
    if grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" "$FILE_PATH" 2>/dev/null; then
        return 0
    fi
    return 1
}

add_violation() {
    local rule="$1"
    local message="$2"
    local file_path="${3:-$FILE_PATH}"
    local ignored=0

    # Check rules engine severity
    local severity
    severity=$(rules_severity_for_file "$file_path" "$rule")

    # If ignored by rules engine, skip entirely
    if [[ "$severity" == "ignore" ]]; then
        return
    fi

    # Check craftsman-ignore in file
    if file_has_ignore "$rule"; then
        ignored=1
    fi

    if [[ $ignored -eq 0 ]]; then
        if [[ "$severity" == "block" ]]; then
            CRITICAL_VIOLATIONS="${CRITICAL_VIOLATIONS}${rule}: ${message}\n"
            ((CRITICAL_COUNT++)) || true
        else
            WARNING_VIOLATIONS="${WARNING_VIOLATIONS}${rule}: ${message}\n"
            ((WARNING_COUNT++)) || true
        fi
    fi

    # Always record in metrics
    local metric_severity="critical"
    [[ "$severity" == "warn" ]] && metric_severity="warning"
    metrics_record_violation "$rule" "$FILE_PATTERN" "$metric_severity" $((1 - ignored)) "$ignored" 2>/dev/null || true
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
        add_violation "PHP001" "Missing declare(strict_types=1)"
    fi

    # PHP002: Classes must be final (except interface/trait/abstract)
    if grep -q "^class " "$file" 2>/dev/null; then
        if ! grep -q "final class" "$file" 2>/dev/null; then
            if ! grep -qE "(interface |trait |abstract class )" "$file" 2>/dev/null; then
                add_violation "PHP002" "Class should be final"
            fi
        fi
    fi

    # PHP003: No public setters (check each line for craftsman-ignore)
    while IFS= read -r line; do
        if echo "$line" | grep -qE "public function set[A-Z]" 2>/dev/null; then
            if ! line_has_ignore "$line" "no-setter"; then
                add_violation "PHP003" "Public setter found — use behavioral methods"
            else
                metrics_record_violation "PHP003" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # PHP004: No new DateTime()
    if grep -q "new DateTime()" "$file" 2>/dev/null || grep -q "new \\\\DateTime()" "$file" 2>/dev/null; then
        add_violation "PHP004" "new DateTime() found — inject Clock instead"
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
                add_violation "TS001" "'any' type found — use proper types or 'unknown'"
            else
                metrics_record_violation "TS001" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # TS002: No default exports
    if grep -q "export default" "$file" 2>/dev/null; then
        add_violation "TS002" "Default export found — use named exports"
    fi

    # TS003: No non-null assertion (!) — exclude != and !==
    if grep -qE "[a-zA-Z0-9_\)]+\![^=\.]" "$file" 2>/dev/null; then
        add_violation "TS003" "Non-null assertion (!) found — handle null explicitly"
    fi

    # WARN-TS001: Max 3 parameters
    if grep -qE "(function\s+\w+|=>)\s*\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-TS001" "Function with 4+ parameters — consider refactoring to object"
    fi
}

# =============================================================================
# Level 2: Static Analysis (if tools installed, <2s timeout)
# Parses structured output: CODE:LINE:MESSAGE
# =============================================================================
validate_static_analysis() {
    local file="$1"
    local errors
    errors=$(timeout 2 bash -c "source '${SCRIPT_DIR}/lib/static-analysis.sh'; sa_analyze_file '$file'" 2>/dev/null) || true

    [[ -z "$errors" ]] && return

    while IFS= read -r err_line; do
        [[ -z "$err_line" ]] && continue
        local sa_code sa_lineno sa_msg
        sa_code=$(echo "$err_line" | cut -d: -f1)
        sa_lineno=$(echo "$err_line" | cut -d: -f2)
        sa_msg=$(echo "$err_line" | cut -d: -f3-)
        # Strip leading whitespace from message
        sa_msg="${sa_msg#"${sa_msg%%[![:space:]]*}"}"

        if [[ -n "$sa_lineno" && "$sa_lineno" -gt 0 ]] 2>/dev/null; then
            add_warning "${sa_code}" "line ${sa_lineno}: ${sa_msg}"
        else
            add_warning "${sa_code}" "${sa_msg}"
        fi
    done <<< "$errors"
}

# =============================================================================
# Level 3: deptrac layer check (if installed, <2s)
# Runs separately so it can produce DEPTRAC001 violations
# =============================================================================
validate_deptrac() {
    local file="$1"
    [[ "${file##*.}" != "php" ]] && return
    local errors
    errors=$(timeout 2 bash -c "source '${SCRIPT_DIR}/lib/static-analysis.sh'; sa_deptrac_structured '$file'" 2>/dev/null) || true

    [[ -z "$errors" ]] && return

    while IFS= read -r err_line; do
        [[ -z "$err_line" ]] && continue
        local sa_code sa_lineno sa_msg
        sa_code=$(echo "$err_line" | cut -d: -f1)
        sa_lineno=$(echo "$err_line" | cut -d: -f2)
        sa_msg=$(echo "$err_line" | cut -d: -f3-)
        sa_msg="${sa_msg#"${sa_msg%%[![:space:]]*}"}"
        add_warning "${sa_code}" "deptrac: line ${sa_lineno}: ${sa_msg}"
    done <<< "$errors"
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
            add_violation "LAYER001" "Domain imports Infrastructure — DDD layer violation"
        fi
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_violation "LAYER002" "Domain imports Presentation — DDD layer violation"
        fi
    fi

    # Application must not import Presentation
    if [[ "$is_application" == true ]] && [[ "$EXT" == "php" ]]; then
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            add_violation "LAYER003" "Application imports Presentation — DDD layer violation"
        fi
    fi

    # TypeScript: domain must not import infrastructure
    if [[ "$is_domain_ts" == true ]] && [[ "$EXT" == "ts" || "$EXT" == "tsx" ]]; then
        if grep -qE "from\s+['\"].*infrastructure" "$file" 2>/dev/null; then
            add_violation "LAYER001" "domain imports infrastructure — layer violation"
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
            validate_deptrac "$FILE_PATH"
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

# =============================================================================
# Custom Rules Validation (from .craft-config.yml rules section)
# =============================================================================
_validate_custom_rules() {
    local file="$1"
    local ext="${file##*.}"
    local language=""
    case "$ext" in
        php) language="php" ;;
        ts|tsx) language="typescript" ;;
        js|jsx) language="javascript" ;;
        *) return ;;
    esac

    local custom_rules
    custom_rules=$(rules_custom_list "$language")
    [[ -z "$custom_rules" ]] && return

    while IFS= read -r rule_id; do
        [[ -z "$rule_id" ]] && continue
        local pattern msg
        pattern=$(rules_pattern "$rule_id")
        msg=$(rules_message "$rule_id")
        [[ -z "$pattern" ]] && continue
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            add_violation "$rule_id" "$msg" "$file"
        fi
    done <<< "$custom_rules"
}
_validate_custom_rules "$FILE_PATH"

# Check for corrections (violation fixed since last block)
_check_corrections "$FILE_PATH"

# =============================================================================
# Output Decision
# =============================================================================

if [[ $CRITICAL_COUNT -gt 0 ]]; then
    # Rules engine already routed block vs warn — CRITICAL_VIOLATIONS only contains blocking rules
    _write_session_state "$FILE_PATH"

    # Check for cross-file patterns and append actionable suggestion
    PATTERN_SUGGESTIONS=$(_detect_cross_file_patterns 2>/dev/null) || true
    local pattern_msg=""
    if [[ -n "$PATTERN_SUGGESTIONS" ]]; then
        while IFS= read -r ps_line; do
            [[ -z "$ps_line" ]] && continue
            if [[ "$ps_line" == PATTERN:* ]]; then
                local ps_rule ps_count
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_count=$(echo "$ps_line" | cut -d: -f3)
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} — consider a project-wide fix or global craftsman-ignore.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
                local ps_rule ps_dir ps_count
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_dir=$(echo "$ps_line" | cut -d: -f3)
                ps_count=$(echo "$ps_line" | cut -d: -f4)
                pattern_msg="${pattern_msg}DIRECTORY PATTERN: ${ps_rule} in ${ps_dir}/ (${ps_count}) — apply fix directory-wide.\n"
            fi
        done <<< "$PATTERN_SUGGESTIONS"
    fi

    jq -n --arg violations "$(echo -e "$CRITICAL_VIOLATIONS")" \
           --arg count "$CRITICAL_COUNT" \
           --arg patterns "$(echo -e "$pattern_msg")" \
    '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("BLOCKED: " + $count + " critical violation(s):\n" + $violations + "\nFix these before proceeding. Use // craftsman-ignore: <rule> to suppress if justified." + (if $patterns != "" then "\n" + $patterns else "" end))
        }
    }'
    exit 2
fi

if [[ $WARNING_COUNT -gt 0 ]]; then
    # Append cross-file pattern suggestions to warnings too
    PATTERN_SUGGESTIONS=$(_detect_cross_file_patterns 2>/dev/null) || true
    local pattern_msg=""
    if [[ -n "$PATTERN_SUGGESTIONS" ]]; then
        while IFS= read -r ps_line; do
            [[ -z "$ps_line" ]] && continue
            if [[ "$ps_line" == PATTERN:* ]]; then
                local ps_rule ps_count
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_count=$(echo "$ps_line" | cut -d: -f3)
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} — consider a project-wide fix.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
                local ps_rule ps_dir ps_count
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_dir=$(echo "$ps_line" | cut -d: -f3)
                ps_count=$(echo "$ps_line" | cut -d: -f4)
                pattern_msg="${pattern_msg}DIRECTORY PATTERN: ${ps_rule} in ${ps_dir}/ (${ps_count}).\n"
            fi
        done <<< "$PATTERN_SUGGESTIONS"
    fi

    jq -n --arg warnings "$(echo -e "$WARNING_VIOLATIONS")" \
           --arg count "$WARNING_COUNT" \
           --arg patterns "$(echo -e "$pattern_msg")" \
    '{
        systemMessage: ("WARNINGS: " + $count + " issue(s) detected:\n" + $warnings + (if $patterns != "" then $patterns else "" end))
    }'
    exit 0
fi

exit 0
