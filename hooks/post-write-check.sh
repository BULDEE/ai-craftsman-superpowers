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
#   Level 1: Regex (always, <50ms) - strict_types, final, any, setters
#   Level 2: Static analysis (if tools installed, <2s) - PHPStan, ESLint
#   Level 3: Architecture (if tools installed, <2s) - deptrac, dependency-cruiser
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
source "${SCRIPT_DIR}/lib/structural.sh"
rules_init "$PWD" "${HOME}/.claude"

# Python3 availability - skip correction learning features if missing
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

# Refuse the characters that are dangerous where the path is interpolated,
# rather than allow-listing an alphabet. The allowlist excluded [ ] ( ) + , and
# everything non-ASCII, and a path it rejected skipped validation in silence:
# every Next.js App Router dynamic route (app/[slug]/page.tsx) and route group
# (app/(marketing)/page.tsx) was unvalidated, as was any path with an accent.
# Verified beforehand that every downstream use of FILE_PATH is quoted, which
# is what makes the narrower set sufficient.
if [[ "$FILE_PATH" == *[\$\`\;\|\&\<\>\\\"\']* || "$FILE_PATH" == *$'\n'* ]]; then
    echo "craftsman: not validating ${FILE_PATH}, the path contains a shell metacharacter" >&2
    exit 0
fi

# Exit silently if no file path or file doesn't exist
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Write/Edit exposure counter: one line per validated write. Read by
# session-metrics.sh at SessionEnd into sessions.writes_count (denominator
# for violations-per-write benchmarks). Append is atomic enough for hook
# concurrency; no locking needed.
echo "1" >> "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-writes" 2>/dev/null || true

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
    # Blanket ignore (no specific rule - just "craftsman-ignore" with no colon or empty list)
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

# Record one violation to the metrics DB.
#
# `blocked` must mean blocked. It was $((1 - ignored)) - independent of
# severity - so advisory rules recorded blocked=1 and the dashboard reported
# 100% blocking for rules that never stop a write. `ignored` already carries
# suppression; the two are separate facts.
_record_violation_metric() {
    local rule="$1" severity="$2" ignored="$3"

    local metric_severity="critical"
    [[ "$severity" == "warn" ]] && metric_severity="warning"

    local metric_blocked=0
    [[ "$severity" == "block" && "$ignored" -eq 0 ]] && metric_blocked=1

    metrics_record_violation "$rule" "$FILE_PATTERN" "$metric_severity" \
        "$metric_blocked" "$ignored" 2>/dev/null || true
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

    _record_violation_metric "$rule" "$severity" "$ignored"
}

# A validator calling add_warning is stating an intent, not a verdict. The
# verdict is the rules engine's, exactly as it is for add_violation: the rule's
# advisory default lives in _rules_is_advisory, and .craft-config.yml or a
# directory .craft-rules.yml can promote it to block or silence it.
#
# This used to write straight to WARNING_VIOLATIONS, bypassing severity
# resolution and craftsman-ignore alike. SH001 was declared a blocking rule in
# ci/doctrine-export.sh and emitted here as a warning, and no configuration in
# either direction could reach it.
add_warning() {
    add_violation "$@"
}

# =============================================================================
# Static Analysis Helper - parses structured CODE:LINE:MESSAGE output
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
# Run Validation - delegates to pack validators
# =============================================================================

# One call, whatever the language. The list of extensions, the validators to
# run and whether the language is enabled at all now come from the loaded
# packs' manifests. The literal case statement this replaces was duplicated
# across ten sites with no parity test, so a pack contributing a language the
# engine had not been taught about loaded successfully and validated nothing.
pack_dispatch_file "$FILE_PATH"

# Level 2/3 runs only for a language whose pack declared a static_analysis
# tool. Deriving it from "the language is known" would have started running
# ESLint on .js the moment JavaScript was claimed for custom rules.
_PWC_LANG=$(lang_for_file "$FILE_PATH")
if [[ -n "$_PWC_LANG" ]] && [[ -n "$(lang_capability "$_PWC_LANG" "static_analysis")" ]]; then
    _run_static_analysis "$FILE_PATH"
fi

# =============================================================================
# Custom Rules Validation (from .craft-config.yml rules section)
# =============================================================================
_validate_custom_rules() {
    local file="$1"
    local language
    language=$(lang_for_file "$file")
    [[ -z "$language" ]] && return

    local custom_rules
    custom_rules=$(rules_custom_list "$language")
    [[ -z "$custom_rules" ]] && return

    while IFS= read -r rule_id; do
        [[ -z "$rule_id" ]] && continue
        local pattern msg
        pattern=$(rules_pattern "$rule_id")
        msg=$(rules_message "$rule_id")
        [[ -z "$pattern" ]] && continue
        # -e: repo-supplied pattern, see rules-engine.sh for the flag-injection note
        if grep -qE -e "$pattern" "$file" 2>/dev/null; then
            add_violation "$rule_id" "$msg" "$file"
        fi
    done <<< "$custom_rules"
}
_validate_custom_rules "$FILE_PATH"

# Check for corrections (violation fixed since last block)
_check_corrections "$FILE_PATH"

# =============================================================================
# Structural ratchet (ADR-0025): a touched file may improve or stay equal,
# never regress. Inert until the project opts in via `ratchet.py init`.
# =============================================================================
if [[ -f "$PWD/.craftsman-baseline.json" ]] && command -v python3 >/dev/null 2>&1; then
    # Capture with an explicit || branch: a non-zero exit inside a command
    # substitution would otherwise fire the fail-open ERR trap before we can
    # read the status, silently skipping the whole check.
    RATCHET_EXIT=0
    RATCHET_OUT=$(python3 "${SCRIPT_DIR}/lib/ratchet.py" check "$FILE_PATH" \
        --baseline "$PWD/.craftsman-baseline.json" 2>/dev/null) || RATCHET_EXIT=$?
    if [[ $RATCHET_EXIT -eq 1 && -n "$RATCHET_OUT" ]]; then
        while IFS= read -r ratchet_line; do
            [[ -z "$ratchet_line" ]] && continue
            add_violation "RATCHET001" "structural regression: ${ratchet_line#RATCHET001 }"
        done <<< "$RATCHET_OUT"
    elif [[ $RATCHET_EXIT -eq 0 ]]; then
        python3 "${SCRIPT_DIR}/lib/ratchet.py" update "$FILE_PATH" \
            --baseline "$PWD/.craftsman-baseline.json" >/dev/null 2>&1 || true
    fi
fi

# =============================================================================
# Output Decision
# =============================================================================

if [[ $CRITICAL_COUNT -gt 0 ]]; then
    # Rules engine already routed block vs warn - CRITICAL_VIOLATIONS only contains blocking rules
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
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} - consider a project-wide fix or global craftsman-ignore.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_dir=$(echo "$ps_line" | cut -d: -f3)
                ps_count=$(echo "$ps_line" | cut -d: -f4)
                pattern_msg="${pattern_msg}DIRECTORY PATTERN: ${ps_rule} in ${ps_dir}/ (${ps_count}) - apply fix directory-wide.\n"
            fi
        done <<< "$PATTERN_SUGGESTIONS"
    fi

    # Human-readable message on stderr (shown in Claude Code UI)
    echo "🚫 BLOCKED by AI Craftsman - ${CRITICAL_COUNT} violation(s):" >&2
    while IFS= read -r vline; do
        [[ -n "$vline" ]] && echo "  ✗ $vline" >&2
    done <<< "$(echo -e "$CRITICAL_VIOLATIONS")"
    echo "Fix these or add: // craftsman-ignore: <RULE_ID>" >&2

    # OKF doctrine pointer (ADR-0024): route the first blocked rule to the
    # concept that explains it - deterministic frontmatter match, no index.
    FIRST_RULE=$(echo -e "$CRITICAL_VIOLATIONS" | head -1 | cut -d: -f1)
    if [[ -n "$FIRST_RULE" ]] && command -v python3 >/dev/null 2>&1; then
        DOCTRINE=$(python3 "${SCRIPT_DIR}/lib/knowledge_lookup.py" \
            "${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}/knowledge" by-rule "$FIRST_RULE" 2>/dev/null | head -2)
        if [[ -n "$DOCTRINE" ]]; then
            echo "Doctrine (knowledge/):" >&2
            echo "$DOCTRINE" | sed 's/^/  → /' >&2
            # Guided mode: same exigency, maximum teaching. The gate explains
            # itself at the moment of friction instead of assuming expertise.
            if config_guided; then
                DOCTRINE_TITLE=$(echo "$DOCTRINE" | head -1 | cut -f2)
                DOCTRINE_ID=$(echo "$DOCTRINE" | head -1 | cut -f1)
                echo "Why this matters: ${DOCTRINE_TITLE}. Fixing it now costs one edit; fixing it in six months costs an afternoon. Read: knowledge/${DOCTRINE_ID}.md" >&2
            fi
        fi
    fi
    if [[ -n "$pattern_msg" ]]; then
        echo -e "$pattern_msg" >&2
    fi

    # Structured JSON on stdout (consumed by Claude AI)
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
    pattern_msg=""
    if [[ -n "$PATTERN_SUGGESTIONS" ]]; then
        while IFS= read -r ps_line; do
            [[ -z "$ps_line" ]] && continue
            if [[ "$ps_line" == PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_count=$(echo "$ps_line" | cut -d: -f3)
                pattern_msg="${pattern_msg}PROJECT-WIDE PATTERN: ${ps_rule} found in ${ps_count} - consider a project-wide fix.\n"
            elif [[ "$ps_line" == DIR_PATTERN:* ]]; then
                ps_rule=$(echo "$ps_line" | cut -d: -f2)
                ps_dir=$(echo "$ps_line" | cut -d: -f3)
                ps_count=$(echo "$ps_line" | cut -d: -f4)
                pattern_msg="${pattern_msg}DIRECTORY PATTERN: ${ps_rule} in ${ps_dir}/ (${ps_count}).\n"
            fi
        done <<< "$PATTERN_SUGGESTIONS"
    fi

    # systemMessage reaches the user, additionalContext reaches Claude. Warnings
    # went out on systemMessage only, so the model saw every blocking violation
    # and none of the advisory ones - including the whole structural family,
    # which is advisory by design and therefore invisible to it.
    jq -n --arg warnings "$(echo -e "$WARNING_VIOLATIONS")" \
           --arg count "$WARNING_COUNT" \
           --arg patterns "$(echo -e "$pattern_msg")" \
    '(("WARNINGS: " + $count + " issue(s) detected:\n" + $warnings
       + (if $patterns != "" then $patterns else "" end))) as $body
     | {
        systemMessage: $body,
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $body
        }
    }'
    exit 0
fi

exit 0
