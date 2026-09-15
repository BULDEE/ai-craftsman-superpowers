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
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "pre-push-verify" "standard,strict" || exit 0
source "${SCRIPT_DIR}/lib/config.sh"

# Resolve the session-state path via the bridge file written by session-start.sh.
# This ensures the hook reads the same file that skills write, even though skills
# run via the Bash tool and never receive CLAUDE_PLUGIN_DATA from the framework.
# Falls back to CLAUDE_PLUGIN_DATA (hook context) when the bridge file is absent.
# Read tool input from stdin
INPUT=$(cat)

# This session's file, named by the payload's session_id (lib/session-files.sh).
# The ~/.claude bridge is for skills in the Bash tool, which have no payload;
# a hook has one and does not read a machine-wide pointer another host's
# session may have written.
source "${SCRIPT_DIR}/lib/session-files.sh"
session_files_bind "$INPUT"
SESSION_STATE=$(session_file session-state.json)

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

# Warning only - do not block the push
echo "WARNING: Session not verified. Consider running /craftsman:verify before pushing code changes." >&2
jq -n '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "WARNING: Session not verified. Consider running /craftsman:verify for code changes. Push allowed."
    }
}'
exit 0
