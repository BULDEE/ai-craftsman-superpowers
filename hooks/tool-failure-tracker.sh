#!/usr/bin/env bash
# =============================================================================
# Tool Failure Tracker — PostToolUseFailure Hook
# Tracks tool execution failures in metrics for pattern detection.
#
# TRIGGERS: PostToolUseFailure (Write|Edit|Bash)
# EXIT CODES: 0 always (async, non-blocking, observational)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
ERROR=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null)

[[ -z "$TOOL_NAME" ]] && exit 0

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

if $HAS_PYTHON3; then
    LIB_DIR="${SCRIPT_DIR}/lib"
    TIMESTAMP=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    ITEM=$(jq -n --arg t "$TOOL_NAME" --arg e "${ERROR:0:200}" --arg ts "$TIMESTAMP" \
        '{tool: $t, error: $e, timestamp: $ts}')
    python3 "$LIB_DIR/session_state.py" append "$SESSION_STATE" tool_failures "$ITEM" 50 2>/dev/null || true
    python3 "$LIB_DIR/session_state.py" increment "$SESSION_STATE" tool_failure_count 2>/dev/null || true
fi

exit 0
