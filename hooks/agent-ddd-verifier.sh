#!/usr/bin/env bash
# =============================================================================
# DDD Architecture Verifier (ADR-0018)
# PostToolUse Write|Edit, async + asyncRewake. Runs semantic DDD checks in
# a headless Haiku subprocess; the main conversation is only interrupted
# (exit 2) when a real violation is found.
# =============================================================================
set -uo pipefail

# Recursion guard: never verify from inside a verification subprocess
[[ -n "${CRAFTSMAN_HEADLESS_VERIFY:-}" ]] && exit 0

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "agent-ddd-verifier" "standard,strict" || exit 0
source "${SCRIPT_DIR}/lib/haiku-verify.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"
case "$EXT" in
    php|ts|tsx) ;;
    *) exit 0 ;;
esac

PROMPT="You are a DDD architecture verifier. Read the file ${FILE_PATH} and check ONLY: (1) Layer violations - Domain must not import Infrastructure or Presentation, Application must not import Presentation, (2) Aggregate boundary violations - cross-aggregate state mutation, (3) Missing Value Objects - primitive obsession where a VO clearly exists in the codebase, (4) God class - unrelated responsibilities mixed (persistence + formatting + business rules); judge by cohesion, NOT line count, (5) Business logic inline in a Controller instead of an Application UseCase. Structural heuristics (size, nesting, params) are already covered by regex hooks: report only semantic issues they cannot catch. If you find real violations, reply starting with the exact token DDD_VIOLATIONS followed by one line per issue as 'file:line rule - fix suggestion'. If the file is clean, reply with the single word CLEAN."

VERDICT=$(haiku_verify "$PROMPT") || exit 0

if [[ "$VERDICT" == DDD_VIOLATIONS* ]]; then
    {
        echo "DDD verification (Haiku) found issues in ${FILE_PATH}:"
        echo "${VERDICT#DDD_VIOLATIONS}"
        echo "Fix them or justify why they are acceptable."
    } >&2
    exit 2
fi

exit 0
