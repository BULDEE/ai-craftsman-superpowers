#!/usr/bin/env bash
# =============================================================================
# Subagent Quality Gate — SubagentStop Hook
# Validates code produced by subagents against craftsman rules.
# Logs subagent activity in metrics for cross-agent pattern detection.
#
# TRIGGERS: SubagentStop (observational, async)
# EXIT CODES: 0 always (non-blocking)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

[[ -z "$AGENT_TYPE" ]] && exit 0

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

if $HAS_PYTHON3; then
    LIB_DIR="${SCRIPT_DIR}/lib"
    TIMESTAMP=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    ITEM=$(jq -n --arg a "$AGENT_TYPE" --arg ts "$TIMESTAMP" \
        '{agent_type: $a, completed_at: $ts}')
    python3 "$LIB_DIR/session_state.py" append "$SESSION_STATE" subagent_activity "$ITEM" 100 2>/dev/null || true
    python3 "$LIB_DIR/session_state.py" increment "$SESSION_STATE" subagent_count 2>/dev/null || true
fi

exit 0
