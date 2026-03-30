#!/usr/bin/env bash
# =============================================================================
# Sentry Error Context — command wrapper for agent hook
# Checks agent_hooks gate AND sentry config BEFORE emitting any context.
# When enabled, injects a Sentry lookup request as additionalContext.
# =============================================================================
set -uo pipefail

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

# Gate: skip if Sentry is not configured
if [[ -z "${CLAUDE_PLUGIN_OPTION_sentry_org:-}" ]]; then
    exit 0
fi

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Circuit breaker check
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/channels.sh" ]]; then
    source "${SCRIPT_DIR}/lib/channels.sh"
    cb_init sentry 3 300 2>/dev/null || true
    CB_STATE=$(cb_state sentry 2>/dev/null) || true
    if [[ "$CB_STATE" == "open" ]]; then
        exit 0
    fi
fi

FILENAME=$(basename "$FILE_PATH")
jq -n --arg file "$FILENAME" '{
    systemMessage: ("SENTRY CONTEXT REQUEST: Search Sentry for recent errors related to " + $file + ". Report top 3 issues (title, frequency, last seen). Max 200 chars each. If no issues found, skip.")
}'
exit 0
