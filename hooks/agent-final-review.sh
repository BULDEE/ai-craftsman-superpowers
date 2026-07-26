#!/usr/bin/env bash
# =============================================================================
# Final Review (ADR-0018)
# Stop hook, async + asyncRewake. Reviews the session's changed files in a
# headless Haiku subprocess; wakes the main conversation (exit 2) only when
# architecture issues are found. Rewake budget of 2 per session prevents a
# review/fix/review loop.
# =============================================================================
set -uo pipefail

# Recursion guard: never review from inside a verification subprocess
[[ -n "${CRAFTSMAN_HEADLESS_VERIFY:-}" ]] && exit 0

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "agent-final-review" "standard,strict" || exit 0

# Gate: skip if strictness is not 'strict'
if [[ "${CLAUDE_PLUGIN_OPTION_strictness:-strict}" != "strict" ]]; then
    exit 0
fi

source "${SCRIPT_DIR}/lib/haiku-verify.sh"

CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(php|ts|tsx)$' || true)
[[ -z "$CHANGED_FILES" ]] && exit 0

# Rewake budget: at most 2 wake-ups per session
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
mkdir -p "$DATA_DIR" 2>/dev/null || true
BUDGET_FILE="${DATA_DIR}/final-review-rewakes-${SESSION_ID}"
REWAKES=$(cat "$BUDGET_FILE" 2>/dev/null || echo 0)
[[ "$REWAKES" -ge 2 ]] && exit 0

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
FILE_LIST=$(echo "$CHANGED_FILES" | head -30 | tr '\n' ' ')

PROMPT="You are a final architecture reviewer. Read these files changed during a coding session: ${FILE_LIST}. Check ONLY: (1) Layer violations - Domain importing Infrastructure/Presentation, Application importing Presentation, (2) Missing tests - new classes in src/ without a corresponding test in tests/, (3) Structural decay - a god class mixing unrelated responsibilities, or business logic leaking into a Controller. A rich aggregate of small cohesive behaviours is NOT a god class. If you find real issues, reply starting with the exact token REVIEW_ISSUES followed by one line per issue as 'file:line issue - fix suggestion'. Otherwise reply with the single word CLEAN."

VERDICT=$(haiku_verify "$PROMPT") || exit 0

if [[ "$VERDICT" == REVIEW_ISSUES* ]]; then
    echo $((REWAKES + 1)) > "$BUDGET_FILE" 2>/dev/null || true
    {
        echo "Final review (Haiku) found architecture issues in this session's changes:"
        haiku_findings "${VERDICT#REVIEW_ISSUES}"
        if [[ "$FILE_COUNT" -gt 15 ]]; then
            echo "Also: ${FILE_COUNT} files changed - prefer small atomic commits (1-5 files each) before pushing."
        fi
    } >&2
    exit 2
fi

exit 0
