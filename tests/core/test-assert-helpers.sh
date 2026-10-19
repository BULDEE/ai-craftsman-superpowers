#!/usr/bin/env bash
# =============================================================================
# The shared assertions give the same verdict whatever the size of the text.
#
# `echo "$haystack" | grep -q` under pipefail: grep exits on the first match,
# echo takes SIGPIPE on the rest, and the pipeline reports 141. assert_contains
# then failed on a text that held the needle (test-rule-baseline.sh, macOS CI,
# PR #116), and assert_not_contains passed on one that held the forbidden text.
# Measured: 100/100 wrong verdicts on a 1 MB text, 0/100 with a here-string.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

BIG="needle-at-the-start"$'\n'"$(for _ in $(seq 40); do cat "$ROOT_DIR/skills/setup/SKILL.md"; done)"

# Prints "<passed> <failed>" for one helper call, run apart from this suite's counters.
_verdict() {
    ( TESTS_PASSED=0; TESTS_FAILED=0; "$@" >/dev/null; echo "$TESTS_PASSED $TESTS_FAILED" )
}

echo ""
echo "--- assertions on a text larger than a pipe buffer (${#BIG} bytes) ---"

for helper in assert_contains assert_json_contains; do
    got=$(_verdict "$helper" "probe" "$BIG" "needle-at-the-start")
    if [[ "$got" == "1 0" ]]; then
        log_pass "$helper passes when the text holds the needle"
    else
        log_fail "$helper on a large text" "passed/failed=$got, expected 1 0"
    fi
done

got=$(_verdict assert_not_contains "probe" "$BIG" "needle-at-the-start")
if [[ "$got" == "0 1" ]]; then
    log_pass "assert_not_contains fails when the text holds the forbidden needle"
else
    log_fail "assert_not_contains on a large text" "passed/failed=$got, expected 0 1"
fi

got=$(_verdict assert_not_contains "probe" "$BIG" "absent-from-the-text")
if [[ "$got" == "1 0" ]]; then
    log_pass "control: assert_not_contains passes when the needle is absent"
else
    log_fail "assert_not_contains control" "passed/failed=$got, expected 1 0"
fi

test_summary
