#!/usr/bin/env bash
# =============================================================================
# CR-289: a turn does not end on a red test waved away as flaky.
#
# Reported from a real session: the functional suite failed twice on one test,
# the agent wrote "flaky, already known, green in isolation", ran the test
# alone and went on, and once announced the CI green except that test. The
# state each case starts from is written by the real producer,
# post-bash-test-verify.sh, from a red suite then the failing test alone; the
# Stop payloads are the captured ones of Claude Code and Codex, with only the
# message and the session swapped in.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="${TMPDIR:-/tmp}/craftsman-dismissal-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
export HOME="$WORK/home"
export CRAFTSMAN_RUNTIME_HOME="$HOME"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDE_CODE_SESSION_ID CRAFTSMAN_SESSION_ID
mkdir -p "$CLAUDE_PLUGIN_DATA" "$HOME/.claude"
trap 'rm -rf "$WORK"' EXIT

GUARD="$ROOT_DIR/hooks/test-dismissal-guard.sh"
STATE="$CLAUDE_PLUGIN_DATA/session-state-s289.json"
CLAUDE_STOP="$ROOT_DIR/tests/fixtures/hosts/claude-code/2.1.272/stop.json"
CODEX_STOP="$ROOT_DIR/tests/fixtures/hosts/codex/0.154.0/stop.json"

test_run() {
    local outcome="$1" command="$2"
    if [[ "$outcome" == pass ]]; then
        jq -n --arg c "$command" \
            '{session_id: "s289", hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c},
              tool_response: {stdout: "OK (1 test, 2 assertions)", stderr: "", interrupted: false, isImage: false}}'
    else
        jq -n --arg c "$command" \
            '{session_id: "s289", hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {command: $c},
              error: "Exit code 1\nFAILURES!\nTests: 120, Assertions: 339, Failures: 1.", is_interrupt: false}'
    fi | bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" >/dev/null 2>&1
}

# stop <fixture> <message> [stop_hook_active] [strictness]: the guard's stdout.
stop() {
    local fixture="$1" message="$2" active="${3:-false}" strictness="${4:-strict}"
    jq --arg m "$message" --argjson a "$active" '.session_id = "s289" | .last_assistant_message = $m | .stop_hook_active = $a' "$fixture" \
        | CLAUDE_PLUGIN_OPTION_STRICTNESS="$strictness" bash "$GUARD" 2>/dev/null
}
blocked() { [[ "$(printf '%s' "$1" | jq -r '.decision // empty' 2>/dev/null)" == "block" ]]; }
warned() { [[ -n "$(printf '%s' "$1" | jq -r '.systemMessage // empty' 2>/dev/null)" ]] && ! blocked "$1"; }

EXCUSE="1 failure in the suite: testOrderIsRateLimited. It is flaky, already known, and passes alone, so the rest is green."
EXCUSE_FR="1 échec dans la suite : testOrderIsRateLimited. Il est flaky, déjà connu, et vert en isolation."
HONEST="The suite is red: testOrderIsRateLimited returns 405 instead of 429. I have not found the cause yet; next I compare the router state between the two runs."
TICKETED="testOrderIsRateLimited is flaky: it reads a cache pool written by the previous test. Opened ORD-42 with that cause."

echo "=== No red run outstanding: the guard has nothing to say ==="

echo '{"verified": false}' > "$STATE"
OUT=$(stop "$CLAUDE_STOP" "$EXCUSE")
if [[ -z "$OUT" ]]; then
    log_pass "the excuse with no red run in the session passes silently"
else
    log_fail "no red run" "output=$OUT"
fi

test_run fail "vendor/bin/phpunit"
test_run pass "vendor/bin/phpunit"
OUT=$(stop "$CLAUDE_STOP" "$EXCUSE")
if [[ -z "$OUT" ]]; then
    log_pass "a red suite answered by the suite green passes silently"
else
    log_fail "red then green suite" "output=$OUT state=$(jq -c . "$STATE")"
fi

echo ""
echo "=== A red suite, the failing test green alone ==="

echo '{"verified": false}' > "$STATE"
test_run fail "vendor/bin/phpunit"
test_run pass "vendor/bin/phpunit --filter testOrderIsRateLimited"
if [[ "$(jq -r '.failed_test_runs | length' "$STATE" 2>/dev/null)" == "1" ]]; then
    log_pass "control: the producer left the red suite outstanding"
else
    log_fail "control: the producer left the red suite outstanding" \
        "state=$(jq -c . "$STATE" 2>/dev/null); every case below is undetermined"
fi

OUT=$(stop "$CLAUDE_STOP" "$EXCUSE")
if blocked "$OUT" && [[ "$(printf '%s' "$OUT" | jq -r '.reason')" == *"'vendor/bin/phpunit'"* ]]; then
    log_pass "Claude Code: 'flaky, passes alone' does not end the turn, and the reason names the red run"
else
    log_fail "Claude Code excuse blocked" "output=$OUT"
fi

OUT=$(stop "$CODEX_STOP" "$EXCUSE")
if blocked "$OUT"; then
    log_pass "Codex: the same excuse does not end the turn"
else
    log_fail "Codex excuse blocked" "output=$OUT"
fi

OUT=$(stop "$CLAUDE_STOP" "$EXCUSE_FR")
if blocked "$OUT"; then
    log_pass "the excuse in French does not end the turn"
else
    log_fail "French excuse blocked" "output=$OUT"
fi

# Only one mode declaring the category must not silence the other: an empty
# mode once took the whole guard down with it, English included.
mkdir -p "$WORK/en-only"
cp "$ROOT_DIR/hooks/lib/bias-patterns/en.conf" "$WORK/en-only/"
OUT=$(CRAFTSMAN_BIAS_PATTERNS_DIR="$WORK/en-only" stop "$CLAUDE_STOP" "$EXCUSE")
if blocked "$OUT"; then
    log_pass "with English alone declaring the words, the excuse still does not end the turn"
else
    log_fail "English alone" "output=$OUT"
fi

OUT=$(stop "$CLAUDE_STOP" "$HONEST")
if [[ -z "$OUT" ]]; then
    log_pass "a red suite reported as red, with no excuse, ends the turn"
else
    log_fail "honest report" "output=$OUT"
fi

OUT=$(stop "$CLAUDE_STOP" "$TICKETED")
if [[ -z "$OUT" ]]; then
    log_pass "the excuse with a ticket named ends the turn"
else
    log_fail "ticketed report" "output=$OUT"
fi

# Sent back once already: a second stop on the same excuse is not looped, it
# is shown to the user.
OUT=$(stop "$CLAUDE_STOP" "$EXCUSE" true)
if warned "$OUT"; then
    log_pass "stop_hook_active: no second block, a warning the user sees"
else
    log_fail "stop_hook_active" "output=$OUT"
fi

OUT=$(stop "$CLAUDE_STOP" "$EXCUSE" false moderate)
if warned "$OUT"; then
    log_pass "moderate: warns, does not block"
else
    log_fail "moderate" "output=$OUT"
fi

OUT=$(stop "$CLAUDE_STOP" "$EXCUSE" false relaxed)
if [[ -z "$OUT" ]]; then
    log_pass "relaxed: silent"
else
    log_fail "relaxed" "output=$OUT"
fi

echo ""
echo "=== Wiring ==="

if jq -e '[.hooks.Stop[].hooks[] | select(.command | test("test-dismissal-guard.sh")) | select((.async // false) | not)] | length == 1' \
        "$ROOT_DIR/hooks/hooks.json" >/dev/null 2>&1; then
    log_pass "hooks.json runs the guard on Stop, synchronously (an async Stop hook cannot keep the turn open)"
else
    log_fail "Stop wiring" "test-dismissal-guard.sh is not a synchronous Stop hook in hooks/hooks.json"
fi

test_summary
