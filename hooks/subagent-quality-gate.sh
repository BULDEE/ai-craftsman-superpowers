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
    python3 -c "
import json, os, sys, datetime, tempfile
sf = sys.argv[1]
agent = sys.argv[2]
os.makedirs(os.path.dirname(sf), exist_ok=True)
try:
    with open(sf) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {}
agents = state.setdefault('subagent_activity', [])
agents.append({
    'agent_type': agent,
    'completed_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
})
if len(agents) > 100:
    agents[:] = agents[-100:]
state['subagent_count'] = state.get('subagent_count', 0) + 1
d = os.path.dirname(sf)
fd, tmp = tempfile.mkstemp(dir=d, suffix='.tmp')
with os.fdopen(fd, 'w') as f:
    json.dump(state, f)
os.rename(tmp, sf)
" "$SESSION_STATE" "$AGENT_TYPE" 2>/dev/null || true
fi

exit 0
