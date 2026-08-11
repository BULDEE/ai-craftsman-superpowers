#!/usr/bin/env bash
# =============================================================================
# Session Metrics Hook for Claude Code
# Logs session summary on SessionEnd.
#
# TRIGGERS: SessionEnd
# =============================================================================
set -uo pipefail

# Non-blocking: session metrics are best-effort
trap 'echo "WARNING: session-metrics.sh failed at line $LINENO" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"

# Session state for correction learning
SESSION_STATE="${DATA_DIR}/session-state.json"
START_TS_FILE="${DATA_DIR}/session-start-ts"
WRITES_FILE="${DATA_DIR}/session-writes"
VIOLATIONS_FILE="${DATA_DIR}/session-violations"

metrics_init 2>/dev/null || true

# Read session info from stdin
INPUT=$(cat)

# SessionEnd input has NO duration field (only session_id/transcript_path/
# cwd/reason). Derive duration from the epoch marker written by
# session-start.sh. Historical bug: reading the nonexistent
# session_duration_seconds yielded 0, producing a "-0 seconds" SQL window
# that recorded 0 blocked/warned on every session.
derive_session_duration() {
    local duration=0 start_ts now_ts
    if [[ -f "$START_TS_FILE" ]]; then
        start_ts=$(cat "$START_TS_FILE" 2>/dev/null)
        now_ts=$(date +%s)
        if [[ "$start_ts" =~ ^[0-9]+$ ]] && (( now_ts >= start_ts )); then
            duration=$(( now_ts - start_ts ))
        fi
    fi
    # Fallback: 1h window when the marker is missing or invalid ("0" would
    # collapse the violation-count window to nothing).
    if [[ "$duration" -le 0 ]]; then
        duration=3600
    fi
    echo "$duration"
}

# Write/Edit exposure counter: one line appended per validated Write/Edit
# by post-write-check.sh. Denominator for violations-per-write benchmarks.
count_session_writes() {
    local count=0
    if [[ -f "$WRITES_FILE" ]]; then
        count=$(wc -l < "$WRITES_FILE" 2>/dev/null | tr -d ' ')
        [[ "$count" =~ ^[0-9]+$ ]] || count=0
    fi
    echo "$count"
}

# Violations OF this session, counted from the file post-write-check appends
# to, exactly like session-writes above.
#
# This used to re-query the violations table over a window of the session's
# own duration, which counts every other session's rows on the same project.
# On 2026-07-27 that produced 16236 warnings across 236 sessions against 1353
# violations actually recorded that day, and on a quiet day it under-counted
# instead. Every trend built on sessions.violations_* was reading noise.
count_violation_marker() {
    local marker="$1" count=0
    if [[ -f "$VIOLATIONS_FILE" ]]; then
        # grep -c exits 1 when it matches nothing, which the ERR trap above
        # turns into an aborted SessionEnd and a session never recorded at all.
        count=$(grep -c "^${marker}$" "$VIOLATIONS_FILE" 2>/dev/null | tr -d ' ') || count=0
    fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    echo "$count"
}

# Joins the non-empty summary parts with " | "; echoes the empty string when
# there is nothing worth reporting.
build_summary_message() {
    local parts=() part msg=""
    [[ "$BLOCKED" -gt 0 || "$WARNED" -gt 0 ]] && parts+=("${BLOCKED} violations blocked, ${WARNED} warnings")
    [[ "${AGENT_COUNT:-0}" -gt 0 ]] && parts+=("${AGENT_COUNT} agent invocation(s)")
    [[ -n "$TEAM_TYPE" ]] && parts+=("team: ${TEAM_TYPE}")
    [[ "${COMPLETED_TASKS_COUNT:-0}" -gt 0 ]] && parts+=("${COMPLETED_TASKS_COUNT} task(s) completed")
    [[ ${#parts[@]} -eq 0 ]] && return 0
    for part in "${parts[@]}"; do
        [[ -n "$msg" ]] && msg="${msg} | "
        msg="${msg}${part}"
    done
    echo "$msg"
}

SESSION_DURATION=$(derive_session_duration)
WRITES_COUNT=$(count_session_writes)
BLOCKED=$(count_violation_marker "blocked")
WARNED=$(count_violation_marker "warned")

# Extract agent usage count and team type from session state
AGENT_COUNT=0
TEAM_TYPE=""
COMPLETED_TASKS_COUNT=0
if [[ -f "$SESSION_STATE" ]]; then
    STATE_DATA=$(python3 "$SCRIPT_DIR/lib/session_state.py" read-session-metrics \
        "$SESSION_STATE" 2>/dev/null) || true

    if [[ -n "$STATE_DATA" ]]; then
        AGENT_COUNT=$(echo "$STATE_DATA" | sed -n '1p')
        TEAM_TYPE=$(echo "$STATE_DATA" | sed -n '2p')
        COMPLETED_TASKS_COUNT=$(echo "$STATE_DATA" | sed -n '3p')
    fi
fi

# Build agents_spawned JSON array for metrics record.
#
# The literal "agent_hook" was a placeholder that recorded nothing: 1053 of
# 1054 rows held [] and the rest held fragments of a broken quote. There is no
# source in this hook for an agent's name, so it records the count it does
# know rather than a name it does not.
AGENTS_JSON="[]"
if [[ "${AGENT_COUNT:-0}" -gt 0 ]]; then
    AGENTS_JSON="[{\"count\":${AGENT_COUNT}}]"
fi

# Build skills_used JSON array (include team type if used)
SKILLS_JSON="[]"
if [[ -n "$TEAM_TYPE" ]]; then
    SKILLS_JSON="[\"team:${TEAM_TYPE}\"]"
fi

# Record session with agent/team stats and write exposure
metrics_record_session "${SESSION_DURATION:-0}" "$SKILLS_JSON" "$AGENTS_JSON" "$BLOCKED" "$WARNED" "$WRITES_COUNT" 2>/dev/null || true

# Output summary as systemMessage (non-blocking)
SUMMARY_MSG=$(build_summary_message)
if [[ -n "$SUMMARY_MSG" ]]; then
    jq -n --arg msg "Session summary: ${SUMMARY_MSG}. Run /craftsman:metrics for details." '{
        systemMessage: $msg
    }'
fi

# Clear session state for correction learning + start-time marker + writes counter
rm -f "$SESSION_STATE" "$START_TS_FILE" "$WRITES_FILE" "$VIOLATIONS_FILE"

exit 0
