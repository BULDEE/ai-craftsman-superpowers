#!/usr/bin/env bash
# =============================================================================
# Task Completion Evidence Gate (ADR-0023)
# TaskCompleted hook: marking a task complete requires verification evidence
# (recorded by /craftsman:verify or a passing test run this session).
# Strictness-aligned: block in strict, warn in moderate, silent in relaxed.
#
# EXIT CODES: 0 = allow, 2 = block with reason on stderr
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "task-completed-verify" "standard,strict" || exit 0

STRICTNESS=$(config_strictness)
[[ "$STRICTNESS" == "relaxed" ]] && exit 0

# Consume stdin (task payload)
INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task.subject // .subject // empty' 2>/dev/null)

# Docs-only style tasks are exempt: no code claim, no evidence needed
if echo "$TASK_SUBJECT" | grep -qiE '^(docs?|documentation|readme|changelog|adr)\b'; then
    exit 0
fi

_BRIDGE_FILE="${HOME}/.claude/craftsman-session-state-path"
if [[ -f "$_BRIDGE_FILE" ]]; then
    SESSION_STATE=$(< "$_BRIDGE_FILE")
else
    SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"
fi

VERIFIED=$(python3 "${SCRIPT_DIR}/lib/session_state.py" check-flag "$SESSION_STATE" verified 2>/dev/null || echo "false")
[[ "$VERIFIED" == "true" ]] && exit 0

# No files written this session? Nothing to verify.
WRITES=$(python3 "${SCRIPT_DIR}/lib/session_state.py" read "$SESSION_STATE" writes_count 0 2>/dev/null || echo 0)
[[ "$WRITES" == "0" || -z "$WRITES" ]] && exit 0

REASON="Task '${TASK_SUBJECT:-unknown}' marked complete without verification evidence. Run the test suite or /craftsman:verify first (evidence-before-completion, ADR-0023)."

if [[ "$STRICTNESS" == "strict" ]]; then
    echo "$REASON" >&2
    exit 2
fi

jq -n --arg msg "$REASON" '{ systemMessage: $msg }'
exit 0
