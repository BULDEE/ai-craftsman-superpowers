#!/usr/bin/env bash
# =============================================================================
# Post-Compact State Verification — PostCompact Hook
# Verifies that session state survived compaction and injects recovery summary.
# Pairs with pre-compact-save.sh to ensure correction learning continuity.
#
# TRIGGERS: PostCompact
# EXIT CODES: 0 always (non-blocking)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat 2>/dev/null) || true

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

if $HAS_PYTHON3 && [[ -f "$SESSION_STATE" ]]; then
    RECOVERY_MSG=$(python3 "$SCRIPT_DIR/lib/session_state.py" post-compact "$SESSION_STATE" 2>/dev/null) || true

    if [[ -n "$RECOVERY_MSG" ]]; then
        jq -n --arg msg "$RECOVERY_MSG" '{
            systemMessage: ("Post-compaction verification — " + $msg)
        }'
    fi
fi

exit 0
