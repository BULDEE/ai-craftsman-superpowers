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
    COMPACT_SUMMARY=$(python3 -c "
import json, sys, datetime, os
sf = sys.argv[1]
try:
    with open(sf) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)

state['last_compact'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
state['compact_count'] = state.get('compact_count', 0) + 1

violations = state.get('blocked_violations', {})
patterns = state.get('patterns', {})
failures = state.get('tool_failure_count', 0)
subagents = state.get('subagent_count', 0)

def plural(n, singular, plural_form=None):
    p = plural_form or singular + 's'
    return f'{n} {singular}' if n == 1 else f'{n} {p}'

summary_parts = []
if violations:
    v_count = sum(len(r) for r in violations.values())
    summary_parts.append(f'{plural(v_count, \"active violation\")} across {plural(len(violations), \"file\")}')
if patterns:
    summary_parts.append(f'{plural(len(patterns), \"cross-file pattern\")} tracked')
if failures:
    summary_parts.append(f'{plural(failures, \"tool failure\")} this session')
if subagents:
    summary_parts.append(f'{plural(subagents, \"subagent completion\")}')

state['pre_compact_summary'] = ' | '.join(summary_parts) if summary_parts else 'clean session'

import tempfile as _tf
_d = os.path.dirname(sf)
_fd, _tmp = _tf.mkstemp(dir=_d, suffix='.tmp')
with os.fdopen(_fd, 'w') as f:
    json.dump(state, f)
os.rename(_tmp, sf)

if summary_parts:
    print(' | '.join(summary_parts))
" "$SESSION_STATE" 2>/dev/null) || true

    if [[ -n "$COMPACT_SUMMARY" ]]; then
        jq -n --arg summary "$COMPACT_SUMMARY" '{
            systemMessage: ("Context compaction — Craftsman state preserved: " + $summary)
        }'
    fi
fi

exit 0
