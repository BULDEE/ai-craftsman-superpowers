#!/usr/bin/env bash
# =============================================================================
# CR-219: the Task tools are not on every model.
#
# Claude Code offers TaskCreate/Get/Update/List and TodoWrite only on older
# models; Opus 4.8, Sonnet 5, Fable 5 and newer get them back only with
# CLAUDE_CODE_ENABLE_TODO_TOOLS=1, which a plugin cannot set (changelog).
# The agent teams documentation names the way out: "Agents without the Task
# tools coordinate through messages instead of the shared task list."
# Every skill or agent that drives the Task tools must say what to do
# without them, or the model it runs on decides for it.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo ""
echo "--- Task tools: a fallback wherever they are driven ---"

DRIVERS=$(cd "$ROOT_DIR" && grep -rlE 'TaskCreate|TaskUpdate|TaskList|TodoWrite' skills agents packs 2>/dev/null | sort)
if [[ -n "$DRIVERS" ]]; then
    log_pass "control: the scan finds the files that drive the Task tools ($(printf '%s\n' "$DRIVERS" | wc -l | tr -d ' '))"
else
    log_fail "control" "no file mentions the Task tools: the scan is blind"
fi

MISSING=""
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    grep -q 'without the Task tools' "$ROOT_DIR/$file" || MISSING="${MISSING} ${file}"
done <<< "$DRIVERS"
if [[ -z "$MISSING" ]]; then
    log_pass "every skill or agent that drives the Task tools says what to do without them"
else
    log_fail "no fallback without the Task tools" "${MISSING# }"
fi

ALWAYS=$(cd "$ROOT_DIR" && grep -nE 'ALWAYS use (TaskCreate|TaskUpdate|TaskList)' skills agents packs -r 2>/dev/null)
if [[ -z "$ALWAYS" ]]; then
    log_pass "no rule demands a Task tool unconditionally"
else
    log_fail "unconditional Task tool rule" "$ALWAYS"
fi

test_summary
