#!/usr/bin/env bash
# =============================================================================
# Pre-Compact Context Preservation — PreCompact Hook
# Saves current violation state and session context before compaction.
# Ensures correction learning and cross-file patterns survive compaction.
#
# TRIGGERS: PreCompact
# EXIT CODES: 0 always (non-blocking)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat 2>/dev/null) || true

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

if $HAS_PYTHON3 && [[ -f "$SESSION_STATE" ]]; then
    COMPACT_SUMMARY=$(python3 "$SCRIPT_DIR/lib/session_state.py" pre-compact "$SESSION_STATE" 2>/dev/null) || true

    if [[ -n "$COMPACT_SUMMARY" ]]; then
        jq -n --arg summary "$COMPACT_SUMMARY" '{
            systemMessage: ("Context compaction — Craftsman state preserved: " + $summary)
        }'
    fi
fi

exit 0
