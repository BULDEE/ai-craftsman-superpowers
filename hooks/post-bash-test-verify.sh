#!/usr/bin/env bash
# =============================================================================
# Post-Bash Test Auto-Verify Hook
# Auto-sets verified=true when test suite passes (exit 0).
#
# TRIGGERS: PostToolUse for Bash
# EXIT CODES: 0 = always pass (informational only)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)

# Only care about successful Bash commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "1"' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0
[[ "$EXIT_CODE" != "0" ]] && exit 0

# Match test runner commands
if ! echo "$COMMAND" | grep -qE '(run-tests\.sh|phpunit|jest|vitest|pytest|cargo test|go test|npm test|pnpm test|yarn test)'; then
    exit 0
fi

# Already verified? Skip.
_BRIDGE_FILE="${HOME}/.claude/craftsman-session-state-path"
if [[ -f "$_BRIDGE_FILE" ]]; then
    SESSION_STATE=$(< "$_BRIDGE_FILE")
else
    SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"
fi

LIB_DIR="${SCRIPT_DIR}/lib"
CURRENT=$(python3 "$LIB_DIR/session_state.py" check-flag "$SESSION_STATE" verified 2>/dev/null || echo "false")
[[ "$CURRENT" == "true" ]] && exit 0

# Set verified
python3 "$LIB_DIR/session_state.py" set-verified 2>/dev/null

exit 0
