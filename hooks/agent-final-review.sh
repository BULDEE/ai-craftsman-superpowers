#!/usr/bin/env bash
# =============================================================================
# Final Review Agent — command wrapper for agent hook
# Checks agent_hooks + strictness gates BEFORE emitting any context.
# When enabled, injects a final review request on Stop.
# =============================================================================
set -uo pipefail

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

# Gate: skip if strictness is not 'strict'
if [[ "${CLAUDE_PLUGIN_OPTION_strictness:-strict}" != "strict" ]]; then
    exit 0
fi

# Get changed files
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null) || true
[[ -z "$CHANGED_FILES" ]] && exit 0

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')

MSG="FINAL REVIEW REQUEST: Review changes made during this session. Check ONLY: (1) Layer violations — Domain importing Infrastructure/Presentation, Application importing Presentation, (2) Missing tests — new classes in src/ without corresponding test in tests/. Block only for architecture violations, not style issues."

if [[ "$FILE_COUNT" -gt 15 ]]; then
    MSG="${MSG}\n\n[ATOMIC COMMITS] This session modified ${FILE_COUNT} files. Craftsman practice: prefer small, focused commits (1-5 files each). Consider splitting this work into atomic commits before pushing."
fi

MSG="${MSG}\n\nChanged files:\n${CHANGED_FILES}"

jq -n --arg msg "$MSG" '{ systemMessage: $msg }'
exit 0
