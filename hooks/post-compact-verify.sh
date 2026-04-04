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

HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

INPUT=$(cat 2>/dev/null) || true

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

if $HAS_PYTHON3 && [[ -f "$SESSION_STATE" ]]; then
    RECOVERY_MSG=$(python3 -c "
import json, sys

sf = sys.argv[1]
try:
    with open(sf) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)

compact_count = state.get('compact_count', 0)
pre_summary = state.get('pre_compact_summary', '')
violations = state.get('blocked_violations', {})
failures = state.get('tool_failure_count', 0)

if compact_count == 0 and not pre_summary:
    sys.exit(0)

parts = []
parts.append(f'Compaction #{compact_count} completed')

if pre_summary:
    parts.append(f'Pre-compact state: {pre_summary}')

v_count = sum(len(r) for r in violations.values()) if violations else 0
if v_count > 0:
    parts.append(f'Violations preserved: {v_count}')
    parts.append('STATE OK')
elif pre_summary and 'violation' in pre_summary.lower():
    parts.append('WARNING: violations may have been lost during compaction')
else:
    parts.append('STATE OK')

if failures:
    parts.append(f'Tool failures tracked: {failures}')

print(' | '.join(parts))
" "$SESSION_STATE" 2>/dev/null) || true

    if [[ -n "$RECOVERY_MSG" ]]; then
        jq -n --arg msg "$RECOVERY_MSG" '{
            systemMessage: ("Post-compaction verification — " + $msg)
        }'
    fi
fi

exit 0
