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

# This session's file, named by the payload's session_id (lib/session-files.sh).
# The ~/.claude bridge is for skills in the Bash tool, which have no payload;
# a hook has one and does not read a machine-wide pointer another host's
# session may have written.
source "${SCRIPT_DIR}/lib/session-files.sh"
session_files_bind "$INPUT"
SESSION_STATE=$(session_file session-state.json)

VERIFIED=$(python3 "${SCRIPT_DIR}/lib/session_state.py" check-flag "$SESSION_STATE" verified 2>/dev/null || echo "false")
[[ "$VERIFIED" == "true" ]] && exit 0

# No files written this session? Nothing to verify.
#
# A failed read is not zero writes. Defaulting it to 0 meant a missing python3
# or a corrupt session state let a task be marked complete with no evidence at
# all, which is the one thing this hook exists to prevent. An unreadable count
# is treated as "there were writes" and the task still has to show evidence.
# One authority for the write count: the session-writes file post-write-check.sh
# appends to, which session-metrics.sh already counts at SessionEnd. This hook
# read a `writes_count` key of the session state that no hook ever wrote, saw
# nothing, and let every task through.
WRITES_FILE=$(session_file session-writes)
if [[ -f "$WRITES_FILE" ]]; then
    WRITES=$(wc -l < "$WRITES_FILE" 2>/dev/null | tr -d ' ') || WRITES="unknown"
else
    WRITES=0
fi
[[ "$WRITES" =~ ^[0-9]+$ ]] || WRITES="unknown"
[[ "$WRITES" == "0" ]] && exit 0

REASON="Task '${TASK_SUBJECT:-unknown}' marked complete without verification evidence. Run the test suite or /craftsman:verify first (evidence-before-completion, ADR-0023)."

if [[ "$STRICTNESS" == "strict" ]]; then
    echo "$REASON" >&2
    exit 2
fi

jq -n --arg msg "$REASON" '{ systemMessage: $msg }'
exit 0
