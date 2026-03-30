#!/usr/bin/env bash
# =============================================================================
# DDD Architecture Verifier — command wrapper for agent hook
# Checks agent_hooks gate BEFORE emitting any context.
# When enabled, injects a DDD verification request as additionalContext.
# =============================================================================
set -uo pipefail

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Only check domain-relevant files
EXT="${FILE_PATH##*.}"
case "$EXT" in
    php|ts|tsx) ;;
    *) exit 0 ;;
esac

jq -n --arg file "$FILE_PATH" '{
    systemMessage: ("DDD VERIFICATION REQUEST: Check the file " + $file + " for: (1) Layer violations — Domain must not import Infrastructure or Presentation, (2) Aggregate boundary violations — no cross-aggregate state mutation, (3) Missing Value Objects — primitive types where a VO should exist, (4) Naming — flag generic names like Manager/Helper/Utils in Domain layer. Report only semantic issues that regex cannot catch. Be concise.")
}'
exit 0
