#!/usr/bin/env bash
# =============================================================================
# Subagent Quality Gate - SubagentStop Hook
#
# For two releases this script promised "validates code produced by subagents"
# and recorded an agent_type and a timestamp. Nothing was validated, so the
# per-agent learning loop the marketing described did not exist.
#
# It now does what the header says: reads the subagent's transcript, finds the
# files it wrote, and runs them through the SAME pack validators the hooks and
# CI use - the agent is a front-end, parity applies. Every finding lands in the
# metrics DB tagged `subagent:<agent_type>`, so /craftsman:metrics can show
# which agent keeps producing which violation, and the findings are surfaced
# to the main loop as additionalContext.
#
# TRIGGERS: SubagentStop (observational, async)
# EXIT CODES: 0 always (non-blocking); Level 1 validators only, no static
# analysis - a Stop-time gate must stay cheap.
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "subagent-quality-gate" "standard,strict" || exit 0
source "${SCRIPT_DIR}/lib/metrics-db.sh"

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[[ -z "$AGENT_TYPE" ]] && exit 0

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

log_subagent_activity() {
    $HAS_PYTHON3 || return 0
    local lib_dir="${SCRIPT_DIR}/lib" timestamp item
    timestamp=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    item=$(jq -n --arg a "$AGENT_TYPE" --arg ts "$timestamp" \
        '{agent_type: $a, completed_at: $ts}')
    # stdout silenced too: increment prints the new counter value, and this
    # hook's stdout is a JSON channel.
    python3 "$lib_dir/session_state.py" append "$SESSION_STATE" subagent_activity "$item" 100 >/dev/null 2>&1 || true
    python3 "$lib_dir/session_state.py" increment "$SESSION_STATE" subagent_count >/dev/null 2>&1 || true
}

log_subagent_activity

# Without python3 or a transcript there is nothing to validate; the activity
# log above is still recorded, which is all the old script ever did.
$HAS_PYTHON3 || exit 0
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0

# --- Files the subagent wrote ------------------------------------------------
# One path per Write/Edit tool_use in the transcript, deduplicated, capped so a
# huge run cannot stall the Stop. The cap is reported, never silent.
TOUCHED_FILES=$(jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use" and (.name == "Write" or .name == "Edit" or .name == "MultiEdit"))
    | .input.file_path // empty
' "$TRANSCRIPT_PATH" 2>/dev/null | sort -u) || TOUCHED_FILES=""

[[ -z "$TOUCHED_FILES" ]] && exit 0

FILE_CAP=20
TOTAL_TOUCHED=$(echo "$TOUCHED_FILES" | grep -c . || echo 0)
TOUCHED_FILES=$(echo "$TOUCHED_FILES" | head -"$FILE_CAP")

# --- Same validation path as hooks and CI ------------------------------------
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/rules-engine.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
metrics_init 2>/dev/null || true
# The plugin root is two levels up from this script; CLAUDE_PLUGIN_ROOT is
# absent outside the harness (tests, CI), and without it pack_loader_init
# silently loads nothing and the gate reports a clean pass it never ran.
pack_loader_init "${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}/packs"

# Findings tagged with the agent that produced them; the `source` column is
# how /craftsman:metrics separates subagent work from the main session.
export CRAFTSMAN_METRICS_SOURCE="subagent:${AGENT_TYPE}"

FINDINGS=""
FINDING_COUNT=0
FILE_PATH=""
FILE_PATTERN=""

# The pack validators call these; identical contracts to post-write-check.
line_has_ignore() {
    local line="$1" rule="$2"
    echo "$line" | grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" 2>/dev/null && return 0
    echo "$line" | grep -qE "craftsman-ignore\s*$" 2>/dev/null && return 0
    return 1
}

file_has_ignore() {
    grep -qE "craftsman-ignore:\s*[^#]*\b${1}\b" "$FILE_PATH" 2>/dev/null
}

record_finding() {
    local rule="$1" message="$2" severity="$3"
    local metric_severity="critical"
    [[ "$severity" != "block" ]] && metric_severity="warning"
    metrics_record_violation "$rule" "$FILE_PATTERN" "$metric_severity" 0 0 2>/dev/null || true
    FINDINGS="${FINDINGS}${FILE_PATH}: ${rule}: ${message}\n"
    FINDING_COUNT=$((FINDING_COUNT + 1))
}

add_violation() {
    local rule="$1" message="$2"
    local severity
    severity=$(rules_severity_for_file "${3:-$FILE_PATH}" "$rule")
    [[ "$severity" == "ignore" ]] && return 0
    record_finding "$rule" "$message" "$severity"
}

add_warning() {
    record_finding "$1" "$2" "warn"
}

validate_one_file() {
    # Deliberately NOT local: FILE_PATH and FILE_PATTERN are the globals the
    # sourced pack validators and file_has_ignore read - same contract as
    # post-write-check.sh.
    FILE_PATH="$1"
    FILE_PATTERN=$(metrics_file_pattern "$FILE_PATH")
    case "${FILE_PATH##*.}" in
        php)
            pack_run_validators "$FILE_PATH" "php"
            pack_run_validators "$FILE_PATH" "php_layers"
            pack_run_validators "$FILE_PATH" "php_persistence"
            pack_run_validators "$FILE_PATH" "php_security"
            ;;
        ts|tsx)
            pack_run_validators "$FILE_PATH" "typescript"
            pack_run_validators "$FILE_PATH" "typescript_layers"
            pack_run_validators "$FILE_PATH" "typescript_persistence"
            pack_run_validators "$FILE_PATH" "typescript_security"
            ;;
        py) pack_run_validators "$FILE_PATH" "python" ;;
        sh|bash) pack_run_validators "$FILE_PATH" "bash" ;;
    esac
}

while IFS= read -r touched; do
    [[ -z "$touched" || ! -f "$touched" ]] && continue
    # Same metacharacter refusal as post-write-check: a hostile path skips
    # validation loudly, it does not reach the validators.
    if [[ "$touched" == *[\$\`\;\|\&\<\>\\\"\']* || "$touched" == *$'\n'* ]]; then
        echo "craftsman: not validating ${touched}, the path contains a shell metacharacter" >&2
        continue
    fi
    validate_one_file "$touched"
done <<< "$TOUCHED_FILES"

[[ "$FINDING_COUNT" -eq 0 ]] && exit 0

CAP_NOTE=""
[[ "$TOTAL_TOUCHED" -gt "$FILE_CAP" ]] && \
    CAP_NOTE=" (first ${FILE_CAP} of ${TOTAL_TOUCHED} files checked)"

CONTEXT=$(printf "Craftsman subagent gate: agent '%s' left %d rule violation(s)%s. Fix these before building on its output:\n%b" \
    "$AGENT_TYPE" "$FINDING_COUNT" "$CAP_NOTE" "$FINDINGS")

jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "SubagentStop", additionalContext: $ctx}}'

exit 0
