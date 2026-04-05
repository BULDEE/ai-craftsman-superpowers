#!/usr/bin/env bash
# =============================================================================
# Pre-Push Verify Hook for Claude Code
# Blocks git push if /craftsman:verify has not been run in the current session.
#
# TRIGGERS: PreToolUse for Bash (git push)
# EXIT CODES: 0 = allow, 2 = block with reason
# =============================================================================
set -uo pipefail

# Fail-open trap: if hook crashes, allow the push
trap 'echo "WARNING: pre-push-verify.sh failed at line $LINENO" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"

# Resolve the session-state path via the bridge file written by session-start.sh.
# This ensures the hook reads the same file that skills write, even though skills
# run via the Bash tool and never receive CLAUDE_PLUGIN_DATA from the framework.
# Falls back to CLAUDE_PLUGIN_DATA (hook context) when the bridge file is absent.
_BRIDGE_FILE="${HOME}/.claude/craftsman-session-state-path"
if [[ -f "$_BRIDGE_FILE" ]]; then
    SESSION_STATE=$(< "$_BRIDGE_FILE")
else
    SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"
fi

# Read tool input from stdin
INPUT=$(cat)

# Only intercept git push commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [[ -z "$COMMAND" ]] || ! echo "$COMMAND" | grep -qE "git\s+push"; then
    exit 0
fi

# Check if /craftsman:verify was run in this session
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
_check_verified() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    local result
    result=$(python3 "$LIB_DIR/session_state.py" check-flag "$file" verified 2>/dev/null) || return 1
    [[ "$result" == "true" ]]
}

VERIFIED=false
if _check_verified "$SESSION_STATE"; then
    VERIFIED=true
fi

if [[ "$VERIFIED" == "true" ]]; then
    exit 0
fi

jq -n '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "BLOCKED: Run /craftsman:verify before pushing. This ensures all standards are met and the session is verified."
    }
}'
exit 2
