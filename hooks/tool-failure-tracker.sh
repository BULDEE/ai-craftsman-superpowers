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
    python3 -c "
import json, os, sys, datetime, tempfile
sf = sys.argv[1]
tool = sys.argv[2]
error = sys.argv[3][:200]
os.makedirs(os.path.dirname(sf), exist_ok=True)
try:
    with open(sf) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {}
failures = state.setdefault('tool_failures', [])
failures.append({
    'tool': tool,
    'error': error,
    'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
})
if len(failures) > 50:
    failures[:] = failures[-50:]
state['tool_failure_count'] = state.get('tool_failure_count', 0) + 1
d = os.path.dirname(sf)
fd, tmp = tempfile.mkstemp(dir=d, suffix='.tmp')
with os.fdopen(fd, 'w') as f:
    json.dump(state, f)
os.rename(tmp, sf)
" "$SESSION_STATE" "$TOOL_NAME" "${ERROR:-unknown}" 2>/dev/null || true
fi

exit 0
