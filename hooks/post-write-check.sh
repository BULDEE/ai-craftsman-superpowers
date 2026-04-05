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
# craftsman-ignore: SH001
# =============================================================================
set -uo pipefail

# Fail-open trap: if hook crashes, pass instead of blocking all writes
trap 'echo "WARNING: post-write-check.sh failed at line $LINENO" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load helpers
source "${SCRIPT_DIR}/lib/metrics-db.sh"
source "${SCRIPT_DIR}/lib/static-analysis.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/rules-engine.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
source "${SCRIPT_DIR}/lib/mjolnir.sh"
rules_init "$PWD" "${HOME}/.claude"

# Python3 availability — skip correction learning features if missing
HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

# Session state for correction learning
SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

_write_session_state() {
    $HAS_PYTHON3 || return 0
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

    # Atomically record violation with cross-file pattern tracking
    python3 "$SCRIPT_DIR/lib/session_state.py" record-violation \
        "$SESSION_STATE" "$file_pattern" "$dir_bucket" "$rules_json" 2>&1 || echo "WARNING: session state write failed" >&2
}

# Detect cross-file patterns: same rule in 3+ files → suggest project-wide fix
_detect_cross_file_patterns() {
    $HAS_PYTHON3 || return 0
    [[ ! -f "$SESSION_STATE" ]] && return

    python3 "$SCRIPT_DIR/lib/session_state.py" detect-patterns "$SESSION_STATE" 2>&1 || echo "WARNING: cross-file pattern detection failed" >&2
}

_check_corrections() {
    $HAS_PYTHON3 || return 0
    local file="$1"
    local file_pattern
    file_pattern=$(metrics_file_pattern "$file")

    [[ ! -f "$SESSION_STATE" ]] && return

    local prev_rules
    prev_rules=$(python3 "$SCRIPT_DIR/lib/session_state.py" get-previous-violations \
        "$SESSION_STATE" "$file_pattern" 2>/dev/null) || return

    [[ -z "$prev_rules" ]] && return

    for prev_rule in $prev_rules; do
        if echo -e "$CRITICAL_VIOLATIONS" | grep -q "^${prev_rule}:"; then
            : # Still violated, do nothing
        elif file_has_ignore "$prev_rule" 2>/dev/null; then
            metrics_record_correction "$prev_rule" "$file_pattern" "ignored" "craftsman-ignore added" 2>/dev/null || true
        else
            metrics_record_correction "$prev_rule" "$file_pattern" "fixed" "" 2>/dev/null || true
            MJ_CORRECTION=$(mjolnir_line "violation_corrected")
            [[ -n "$MJ_CORRECTION" ]] && echo "$MJ_CORRECTION" >&2
        fi
    done
}

# Init metrics DB (creates tables if needed, idempotent)
metrics_init 2>/dev/null || true

# Init pack loader (discovers and sources pack validators)
pack_loader_init

# Read tool input from stdin (JSON from Claude Code)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Validate file path contains only safe characters
[[ "$FILE_PATH" =~ ^[a-zA-Z0-9_./@:\ -]+$ ]] || exit 0

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

_record_violation_output() {
    local rule="$1"
    local message="$2"
    local severity="$3"

    if [[ "$severity" == "block" ]]; then
        CRITICAL_VIOLATIONS="${CRITICAL_VIOLATIONS}${rule}: ${message}\n"
        ((CRITICAL_COUNT++)) || true
    else
        WARNING_VIOLATIONS="${WARNING_VIOLATIONS}${rule}: ${message}\n"
        ((WARNING_COUNT++)) || true
    fi
}

add_violation() {
    local rule="$1"
    local message="$2"
    local file_path="${3:-$FILE_PATH}"
    local ignored=0

    local severity
    severity=$(rules_severity_for_file "$file_path" "$rule")

    if [[ "$severity" == "ignore" ]]; then
        return
    fi

    if file_has_ignore "$rule"; then
        ignored=1
    fi

    if [[ $ignored -eq 0 ]]; then
        _record_violation_output "$rule" "$message" "$severity"
    fi

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
# Static Analysis Helper — parses structured CODE:LINE:MESSAGE output
# =============================================================================
_run_static_analysis() {
    local file="$1"
    local errors
    errors=$(sa_analyze_file "$file" 2>/dev/null) || true
    [[ -z "$errors" ]] && return

    while IFS= read -r err_line; do
        [[ -z "$err_line" ]] && continue
        local sa_code sa_lineno sa_msg
        sa_code=$(echo "$err_line" | cut -d: -f1)
        sa_lineno=$(echo "$err_line" | cut -d: -f2)
        sa_msg=$(echo "$err_line" | cut -d: -f3-)
        sa_msg="${sa_msg#"${sa_msg%%[![:space:]]*}"}"
        if [[ -n "$sa_lineno" && "$sa_lineno" -gt 0 ]] 2>/dev/null; then
            add_warning "${sa_code}" "line ${sa_lineno}: ${sa_msg}"
        else
            add_warning "${sa_code}" "${sa_msg}"
        fi
    done <<< "$errors"
}

# =============================================================================
# Run Validation — delegates to pack validators
# =============================================================================

case "$EXT" in
    php)
        if config_php_enabled; then
            pack_run_validators "$FILE_PATH" "php"
            pack_run_validators "$FILE_PATH" "php_layers"
            _run_static_analysis "$FILE_PATH"
        fi
        ;;
    ts|tsx)
        if config_ts_enabled; then
            pack_run_validators "$FILE_PATH" "typescript"
            pack_run_validators "$FILE_PATH" "typescript_layers"
            _run_static_analysis "$FILE_PATH"
        fi
        ;;
    py)
        pack_run_validators "$FILE_PATH" "python"
        ;;
    sh|bash)
        pack_run_validators "$FILE_PATH" "bash"
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
        py) language="python" ;;
        sh|bash) language="bash" ;;
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
    pattern_msg=""
    if [[ -n "$PATTERN_SUGGESTIONS" ]]; then
        while IFS= read -r ps_line; do
            [[ -z "$ps_line" ]] && continue
            if [[ "$ps_line" == PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_count=$(echo "$ps_line" | cut -d: -f3)
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} — consider a project-wide fix or global craftsman-ignore.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_dir=$(echo "$ps_line" | cut -d: -f3)
                ps_count=$(echo "$ps_line" | cut -d: -f4)
                pattern_msg="${pattern_msg}DIRECTORY PATTERN: ${ps_rule} in ${ps_dir}/ (${ps_count}) — apply fix directory-wide.\n"
            fi
        done <<< "$PATTERN_SUGGESTIONS"
    fi

    MJ_LINE=$(mjolnir_line "violation_blocked")
    jq -n --arg violations "$(echo -e "$CRITICAL_VIOLATIONS")" \
           --arg count "$CRITICAL_COUNT" \
           --arg patterns "$(echo -e "$pattern_msg")" \
           --arg mj "$MJ_LINE" \
    '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: ("BLOCKED: " + $count + " critical violation(s):\n" + $violations + "\nFix these before proceeding. Use // craftsman-ignore: <rule> to suppress if justified." + (if $patterns != "" then "\n" + $patterns else "" end) + (if $mj != "" then "\n" + $mj else "" end))
        }
    }'
    exit 2
fi

if [[ $WARNING_COUNT -gt 0 ]]; then
    # Append cross-file pattern suggestions to warnings too
    PATTERN_SUGGESTIONS=$(_detect_cross_file_patterns 2>/dev/null) || true
    pattern_msg=""
    if [[ -n "$PATTERN_SUGGESTIONS" ]]; then
        while IFS= read -r ps_line; do
            [[ -z "$ps_line" ]] && continue
            if [[ "$ps_line" == PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_count=$(echo "$ps_line" | cut -d: -f3)
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} — consider a project-wide fix.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
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
