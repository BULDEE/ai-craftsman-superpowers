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

# Session state for correction learning
SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

metrics_init 2>/dev/null || true

# Read session info from stdin
INPUT=$(cat)

# SessionEnd input has NO duration field (only session_id/transcript_path/
# cwd/reason). Derive duration from the epoch marker written by
# session-start.sh. Historical bug: reading the nonexistent
# session_duration_seconds yielded 0, producing a "-0 seconds" SQL window
# that recorded 0 blocked/warned on every session.
START_TS_FILE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-start-ts"
SESSION_DURATION=0
if [[ -f "$START_TS_FILE" ]]; then
    START_TS=$(cat "$START_TS_FILE" 2>/dev/null)
    NOW_TS=$(date +%s)
    if [[ "$START_TS" =~ ^[0-9]+$ ]] && (( NOW_TS >= START_TS )); then
        SESSION_DURATION=$(( NOW_TS - START_TS ))
    fi
fi
# Fallback: 1h window when the marker is missing or invalid ("0" would
# collapse the violation-count window to nothing).
if [[ "$SESSION_DURATION" -le 0 ]]; then
    SESSION_DURATION=3600
fi

# Count violations from this session (window = session duration)
PROJECT_HASH=$(metrics_project_hash)
DURATION_PARAM="-${SESSION_DURATION} seconds"
BLOCKED=$(python3 "${SCRIPT_DIR}/lib/metrics-query.py" "$METRICS_DB" \
    "SELECT COUNT(*) FROM violations WHERE project_hash=? AND blocked=1 AND timestamp > datetime('now', ?)" \
    "$PROJECT_HASH" "$DURATION_PARAM" 2>/dev/null || echo 0)
WARNED=$(python3 "${SCRIPT_DIR}/lib/metrics-query.py" "$METRICS_DB" \
    "SELECT COUNT(*) FROM violations WHERE project_hash=? AND blocked=0 AND ignored=0 AND timestamp > datetime('now', ?)" \
    "$PROJECT_HASH" "$DURATION_PARAM" 2>/dev/null || echo 0)

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

# Build agents_spawned JSON array for metrics record
AGENTS_JSON="[]"
if [[ "${AGENT_COUNT:-0}" -gt 0 ]]; then
    AGENTS_JSON="[\"agent_hook\"]"
fi

# Build skills_used JSON array (include team type if used)
SKILLS_JSON="[]"
if [[ -n "$TEAM_TYPE" ]]; then
    SKILLS_JSON="[\"team:${TEAM_TYPE}\"]"
fi

# Record session with agent/team stats
metrics_record_session "${SESSION_DURATION:-0}" "$SKILLS_JSON" "$AGENTS_JSON" "$BLOCKED" "$WARNED" 2>/dev/null || true

# Output summary as systemMessage (non-blocking)
SUMMARY_PARTS=()
[[ "$BLOCKED" -gt 0 || "$WARNED" -gt 0 ]] && SUMMARY_PARTS+=("${BLOCKED} violations blocked, ${WARNED} warnings")
[[ "${AGENT_COUNT:-0}" -gt 0 ]] && SUMMARY_PARTS+=("${AGENT_COUNT} agent invocation(s)")
[[ -n "$TEAM_TYPE" ]] && SUMMARY_PARTS+=("team: ${TEAM_TYPE}")
[[ "${COMPLETED_TASKS_COUNT:-0}" -gt 0 ]] && SUMMARY_PARTS+=("${COMPLETED_TASKS_COUNT} task(s) completed")

if [[ ${#SUMMARY_PARTS[@]} -gt 0 ]]; then
    # Join parts with " | "
    SUMMARY_MSG=""
    for part in "${SUMMARY_PARTS[@]}"; do
        [[ -n "$SUMMARY_MSG" ]] && SUMMARY_MSG="${SUMMARY_MSG} | "
        SUMMARY_MSG="${SUMMARY_MSG}${part}"
    done
    jq -n --arg msg "Session summary: ${SUMMARY_MSG}. Run /craftsman:metrics for details." '{
        systemMessage: $msg
    }'
fi

# Clear session state for correction learning + start-time marker
rm -f "$SESSION_STATE" "$START_TS_FILE"

exit 0
