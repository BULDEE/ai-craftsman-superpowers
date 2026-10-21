#!/usr/bin/env bash
# =============================================================================
# Test Dismissal Guard (CR-289)
# Stop hook, synchronous. A test run failed in this session and no run as wide
# has passed since (lib/test_scope.py). When the turn's last message waves
# that failure away (flaky, passes alone, pre-existing, unrelated) and names no
# ticket, the turn does not end on it: a test red in the suite and green alone
# depends on shared state, order, time or the filesystem, which is a defect.
#
# Reported from a real session: the suite failed twice on one test, the agent
# wrote "flaky, already known, green in isolation", ran it alone and went on.
# The words are data, one category of the bias patterns per language
# (lib/bias-patterns/<lang>.conf, TEST_DISMISSAL); this hook names none.
#
# Strictness-aligned: block in strict, warn in moderate, silent in relaxed.
# stop_hook_active means the turn was already sent back once: a second stop on
# the same excuse is shown to the user, never looped.
#
# EXIT CODES: 0 always; the decision is the JSON on stdout.
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Both modes: the red run outstanding is the precision, the words are recall.
# A mode no language fills returns 1; read through a pipeline under the ERR
# trap, that silenced the whole guard, English included.
_dismissal_pattern() {
    local mode pattern combined=""
    for mode in curated signal; do
        pattern=$(bias_combined_pattern TEST_DISMISSAL "$mode") || continue
        combined="${combined:+${combined}|}${pattern}"
    done
    [[ -n "$combined" ]] || return 1
    printf '%s' "$combined"
}

# One command per line in, 'one', 'two' out.
_quoted_runs() {
    local run quoted=""
    while IFS= read -r run; do
        quoted="${quoted:+${quoted}, }'${run}'"
    done <<< "$1"
    printf '%s' "$quoted"
}

# This runs at the end of every turn, so the common case, no red run
# outstanding, exits on the session state before the config is read: 78 ms
# with the config first, measured.
INPUT=$(cat)
source "${SCRIPT_DIR}/lib/session-files.sh"
session_files_bind "$INPUT"
SESSION_STATE=$(session_file session-state.json)
[[ -n "$SESSION_STATE" && -f "$SESSION_STATE" ]] || exit 0
RED_RUNS=$(jq -r '.failed_test_runs // [] | .[].command' "$SESSION_STATE" 2>/dev/null)
[[ -z "$RED_RUNS" ]] && exit 0
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
[[ -z "$MESSAGE" ]] && exit 0

source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "test-dismissal-guard" "standard,strict" || exit 0
STRICTNESS=$(config_strictness)
[[ "$STRICTNESS" == "relaxed" ]] && exit 0

source "${SCRIPT_DIR}/lib/bias-registry.sh"
bias_registry_init "${CRAFTSMAN_BIAS_PATTERNS_DIR:-${SCRIPT_DIR}/lib/bias-patterns}"
DISMISSAL=$(_dismissal_pattern) || exit 0
printf '%s' "$MESSAGE" | grep -qiE "$DISMISSAL" || exit 0

# A ticket named is the answer asked for when the cause is not fixed in the
# session: an issue key (ORD-42), a GitHub number, or an issue URL.
printf '%s' "$MESSAGE" | grep -qE '\b[A-Z][A-Z0-9]+-[0-9]+\b|#[0-9]+\b|/issues/[0-9]+' && exit 0

RED=$(_quoted_runs "$RED_RUNS")

if [[ "$STRICTNESS" == "strict" && "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" != "true" ]]; then
    jq -n --arg r "A test run failed in this session and no run as wide has passed since: ${RED}. Your report waves it away (flaky, passes alone, pre-existing, unrelated). A test red in the suite and green alone depends on shared state, order, time or the filesystem: that is a defect, not noise. Find the cause, fix it and run ${RED} green; or open a ticket for it and name its identifier in your report, with what you found." \
        '{decision: "block", reason: $r}'
    exit 0
fi
jq -n --arg m "craftsman: this turn ended waving away a red test run (${RED}) as flaky or pre-existing, with no ticket named. A test red in the suite and green alone is a defect (shared state, order, time, filesystem)." \
    '{systemMessage: $m}'
exit 0
