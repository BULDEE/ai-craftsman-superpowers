#!/usr/bin/env bash
# =============================================================================
# DDD Architecture Verifier - command wrapper for agent hook
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
    systemMessage: ("DDD VERIFICATION REQUEST: Check the file " + $file + " for: (1) Layer violations - Domain must not import Infrastructure or Presentation, (2) Aggregate boundary violations - no cross-aggregate state mutation, (3) Missing Value Objects - primitive types where a VO should exist, (4) Naming - flag generic names like Manager/Helper/Utils in Domain layer, (5) God class - a class mixing unrelated responsibilities (persistence + formatting + business rules, or several independent feature toggles plus a state machine); judge by responsibility cohesion NOT raw line count, a rich aggregate of many small cohesive behaviours is fine, (6) Controller logic leak - orchestration or business rules inline in a Controller instead of an Application UseCase. The structural hooks (NEST001/LOC001/GOD001/PARAM001/CTRL001) already flag size and nesting heuristically; your job is the semantic call regex cannot make. Report only real issues and propose a concrete DDD refactor (extract value object/service, guard clauses, split responsibility). Be concise.")
}'
exit 0
