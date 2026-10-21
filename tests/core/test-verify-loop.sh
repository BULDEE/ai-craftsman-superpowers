#!/usr/bin/env bash
# =============================================================================
# Deterministic verification loop tests (ADR-0023)
# TaskCompleted evidence gate + test-failure revocation
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

FAKE_HOME="/tmp/craftsman-verify-loop-$$"
mkdir -p "$FAKE_HOME/.claude"

# The write count is the session-writes file post-write-check.sh appends to,
# never a key of the state JSON: the hook used to read a `writes_count` key no
# hook ever wrote, so the gate saw zero writes and let every task through.
export CLAUDE_PLUGIN_DATA="$FAKE_HOME/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"
# A hook names its state file after its payload's session_id under
# CLAUDE_PLUGIN_DATA (lib/session-files.sh); the ~/.claude bridge is read by
# skills in the Bash tool only. The payloads here carry no session_id, so the
# shared file is the one.
FAKE_STATE="$CLAUDE_PLUGIN_DATA/session-state.json"
printf '%s' "$FAKE_STATE" > "$FAKE_HOME/.claude/craftsman-session-state-path"
WRITES_FILE="$CLAUDE_PLUGIN_DATA/session-writes"

set_writes() {
    if [[ "$1" -eq 0 ]]; then
        rm -f "$WRITES_FILE"
    else
        : > "$WRITES_FILE"
        for _ in $(seq 1 "$1"); do echo 1 >> "$WRITES_FILE"; done
    fi
}

gate() {
    local subject="$1" strictness="$2"
    echo "{\"task\":{\"subject\":\"$subject\"}}" | \
        HOME="$FAKE_HOME" CLAUDE_PLUGIN_OPTION_strictness="$strictness" \
        bash "$ROOT_DIR/hooks/task-completed-verify.sh" 2>/dev/null
}

echo "=== TaskCompleted Evidence Gate ==="

echo '{"verified": false}' > "$FAKE_STATE"
set_writes 5
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]]; then
    log_pass "strict + unverified + writes: blocks (exit 2)"
else
    log_fail "strict gate" "expected exit 2, got $EXIT_CODE"
fi

echo '{"verified": true}' > "$FAKE_STATE"
set_writes 5
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "strict + verified: allows (exit 0)"
else
    log_fail "verified pass-through" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false}' > "$FAKE_STATE"
set_writes 5
OUTPUT=$(gate "Implement user entity" moderate)
if echo "$OUTPUT" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "moderate + unverified: warns via systemMessage, no block"
else
    log_fail "moderate warn" "expected systemMessage: $OUTPUT"
fi

EXIT_CODE=0
gate "Implement user entity" relaxed >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "relaxed: silent pass"
else
    log_fail "relaxed gate" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false}' > "$FAKE_STATE"
set_writes 5
EXIT_CODE=0
gate "docs: update readme" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "docs-prefixed task exempt from evidence gate"
else
    log_fail "docs exemption" "expected exit 0, got $EXIT_CODE"
fi

echo '{"verified": false}' > "$FAKE_STATE"
set_writes 0
EXIT_CODE=0
gate "Implement user entity" strict >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "no writes this session: nothing to verify (exit 0)"
else
    log_fail "no-writes exemption" "expected exit 0, got $EXIT_CODE"
fi

echo ""
echo "=== Test-Failure Revocation (post-bash-test-verify) ==="

DATA_DIR="$FAKE_HOME/plugin-data"
mkdir -p "$DATA_DIR"

# The shapes Claude Code sends (tests/fixtures/hosts/claude-code): a passing
# run is a PostToolUse whose tool_response has stdout and no exit code; a
# failing run is a PostToolUseFailure whose `error` starts with "Exit code N".
# The suite used to send `tool_result.exit_code`, a field no host sends, and
# so validated the reader that turned every real passing run into a
# regression (audit CR-117, C2).
run_verify_hook() {
    local exit_code="$1" payload
    if [[ "$exit_code" == "0" ]]; then
        payload='{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"12 passing","stderr":"","interrupted":false,"isImage":false}}'
    else
        payload="{\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"error\":\"Exit code $exit_code\\n1 failing\",\"is_interrupt\":false}"
    fi
    echo "$payload" | \
        HOME="$FAKE_HOME" CLAUDE_PLUGIN_DATA="$DATA_DIR" \
        bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1
}

# Green run sets verified
echo '{"verified": false}' > "$FAKE_STATE"
run_verify_hook 0 >/dev/null || true
# set-verified writes via bridge; verify flag flip is environment-dependent,
# so assert the regression path directly:
echo '{"verified": true}' > "$FAKE_STATE"
EXIT_CODE=0
OUTPUT=$(run_verify_hook 1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]] && echo "$OUTPUT" | grep -q "REGRESSED"; then
    log_pass "failing run after green: exit 2 with regression message (asyncRewake)"
else
    log_fail "regression rewake" "exit=$EXIT_CODE output=$OUTPUT"
fi

if grep -q "test failure: npm test" "$DATA_DIR/test-failures.log" 2>/dev/null; then
    log_pass "failure appended to test-failures.log (monitor feed)"
else
    log_fail "failure log" "missing test-failures.log entry"
fi

echo '{"verified": false}' > "$FAKE_STATE"
EXIT_CODE=0
run_verify_hook 1 >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "failing run without prior green: silent (no rewake spam)"
else
    log_fail "no-spam guard" "expected exit 0, got $EXIT_CODE"
fi

# monitors.json is valid and wires the failure log
if jq -e '.[0].name == "craftsman-test-failures"' "$ROOT_DIR/monitors/monitors.json" >/dev/null 2>&1; then
    log_pass "monitors.json valid, test-failures monitor declared"
else
    log_fail "monitors.json" "invalid or missing monitor entry"
fi

echo ""
echo "=== A green run that ran no test grants no evidence (CR-255) ==="

# Each capture is what a real runner printed (tests/fixtures/test-runs,
# PROVENANCE.md): a script that only echoes, a suite whose every test is
# skipped, PHPUnit counting zero assertions. All of them exit 0, and before
# CR-255 every one of them set `verified`, which then let a task close and a
# push go through on a suite that tested nothing.
RUNS="$ROOT_DIR/tests/fixtures/test-runs"
PROOF_HOME="$FAKE_HOME/proof"
PROOF_DATA="$PROOF_HOME/data"
mkdir -p "$PROOF_HOME/.claude" "$PROOF_DATA"
PROOF_STATE="$PROOF_DATA/session-state-proof.json"

# The command each capture came from.
run_command() {
    case "$1" in
        npm-*)     echo "npm test" ;;
        pnpm-*)    echo "pnpm test" ;;
        jest-*)    echo "jest" ;;
        vitest-*)  echo "vitest run" ;;
        mocha-*)   echo "mocha" ;;
        pytest-*)  echo "pytest" ;;
        phpunit-*) echo "vendor/bin/phpunit" ;;
    esac
}

# feed <capture>: the capture as Claude Code sends a passing Bash run
# (tests/fixtures/hosts/claude-code/2.1.272/post-tool-use.bash.python-tests-passed.json),
# stdout and stderr apart: jest writes its summary to stderr.
feed() {
    local name="$1" out="" err=""
    [[ -f "$RUNS/$name.stdout" ]] && out=$(cat "$RUNS/$name.stdout")
    [[ -f "$RUNS/$name.stderr" ]] && err=$(cat "$RUNS/$name.stderr")
    jq -n --arg c "$(run_command "$name")" --arg o "$out" --arg e "$err" \
        '{session_id: "proof", hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c},
          tool_response: {stdout: $o, stderr: $e, interrupted: false, isImage: false, noOutputExpected: false}}' \
        | env -u CLAUDE_CODE_SESSION_ID -u CRAFTSMAN_SESSION_ID HOME="$PROOF_HOME" CRAFTSMAN_RUNTIME_HOME="$PROOF_HOME" \
            CLAUDE_PLUGIN_DATA="$PROOF_DATA" bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1
}

replay() {
    echo '{"verified": false}' > "$PROOF_STATE"
    feed "$1"
}

granted() { [[ "$(jq -r '.verified // false' "$PROOF_STATE" 2>/dev/null)" == "true" ]]; }

# Control: a real suite run through `npm test` grants. If it does not, the
# instrument is broken and every "grants nothing" below would pass for nothing.
replay npm-script-runs-jest >/dev/null
if granted; then
    log_pass "control: npm test running a real jest suite grants the evidence"

    for capture in npm-echo-ok npm-true pnpm-exit-0 jest-no-tests jest-all-skipped \
                   vitest-no-tests vitest-all-skipped mocha-all-skipped pytest-all-skipped \
                   pytest-all-skipped-quiet phpunit-no-tests phpunit-all-skipped phpunit-no-assertions; do
        OUTPUT=$(replay "$capture")
        if ! granted && [[ "$OUTPUT" == *"no test ran"* ]]; then
            log_pass "$capture: exits 0, ran no test, grants nothing and says why"
        else
            log_fail "$capture grants no evidence" "verified=$(jq -c . "$PROOF_STATE") output=$OUTPUT"
        fi
    done

    # A run that executed tests still counts when some were skipped. A focused
    # run (`test.only`) prints the same shape as a partial skip: it is not
    # visible in the output, so it is a write-time rule's job, not this one's.
    for capture in jest-passed-and-skipped jest-focused vitest-passed-and-skipped \
                   mocha-ten-passing pytest-passed-and-skipped phpunit-passed-and-skipped; do
        replay "$capture" >/dev/null
        if granted; then
            log_pass "$capture: tests ran, the evidence is granted"
        else
            log_fail "$capture grants the evidence" "verified=$(jq -c . "$PROOF_STATE")"
        fi
    done

    # The skill's set-verified (no path argument) cannot grant what an empty
    # run just refused, the same way it cannot after a failure (CR-204 F7).
    skill_set_verified() {
        env -u CRAFTSMAN_SESSION_ID HOME="$PROOF_HOME" CRAFTSMAN_RUNTIME_HOME="$PROOF_HOME" \
            CLAUDE_PLUGIN_DATA="$PROOF_DATA" CLAUDE_CODE_SESSION_ID=proof \
            python3 "$ROOT_DIR/hooks/lib/session_state.py" set-verified 2>&1
    }
    replay npm-echo-ok >/dev/null
    EXIT_CODE=0
    OUTPUT=$(skill_set_verified) || EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]] && ! granted; then
        log_pass "after a run that ran no test, the skill's set-verified is refused"
    else
        log_fail "set-verified after an empty run" "exit=$EXIT_CODE verified=$(jq -c . "$PROOF_STATE") output=$OUTPUT"
    fi
    feed npm-script-runs-jest >/dev/null
    echo '{"verified": false}' > "$PROOF_STATE.tmp" && jq '.verified = false' "$PROOF_STATE" > "$PROOF_STATE.tmp" && mv "$PROOF_STATE.tmp" "$PROOF_STATE"
    EXIT_CODE=0
    OUTPUT=$(skill_set_verified) || EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 0 ]] && granted; then
        log_pass "a real run afterwards lifts the refusal"
    else
        log_fail "set-verified after a real run" "exit=$EXIT_CODE verified=$(jq -c . "$PROOF_STATE") output=$OUTPUT"
    fi
else
    log_fail "control: npm test running a real jest suite" \
        "granted nothing: verified=$(jq -c . "$PROOF_STATE" 2>/dev/null); the assertions on empty runs are undetermined"
fi

# Which wording means "no test ran" is each runner's, so each pack's: the hook
# names none of it (CLAUDE.md, the engine holds no list of languages).
if grep -qE 'No tests (found|executed)|Assertions: 0|[0-9]+ skipped|0 passing' "$ROOT_DIR/hooks/post-bash-test-verify.sh"; then
    log_fail "the hook holds no runner's wording" "a runner's output literal is in hooks/post-bash-test-verify.sh"
else
    log_pass "the hook holds no runner's wording: the packs declare it"
fi

echo ""
echo "=== A narrower green run does not restore a wider red one (CR-289) ==="

# Reported from a real session: the suite failed on one test, the agent ran
# that test alone, saw it pass, called it flaky and moved on. The hook granted
# the evidence on the filtered run and erased the failure. A run that passes
# with an argument the red run did not have may have run less (a filter, a
# path, a test name); which flags narrow is each runner's business, so any
# added argument counts as narrowing.
SCOPE_STATE="$PROOF_DATA/session-state-scope.json"
scope_run() {
    local outcome="$1" command="$2" stdout="${3:-OK (120 tests, 340 assertions)}"
    if [[ "$outcome" == pass ]]; then
        jq -n --arg c "$command" --arg o "$stdout" \
            '{session_id: "scope", hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c},
              tool_response: {stdout: $o, stderr: "", interrupted: false, isImage: false}}'
    else
        jq -n --arg c "$command" \
            '{session_id: "scope", hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {command: $c},
              error: "Exit code 1\nFAILURES!\nTests: 120, Assertions: 339, Failures: 1.", is_interrupt: false}'
    fi | env -u CLAUDE_CODE_SESSION_ID -u CRAFTSMAN_SESSION_ID HOME="$PROOF_HOME" CRAFTSMAN_RUNTIME_HOME="$PROOF_HOME" \
        CLAUDE_PLUGIN_DATA="$PROOF_DATA" bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1
}
scope_flag() { jq -r ".$1 // false" "$SCOPE_STATE" 2>/dev/null; }
fresh_scope() { echo '{"verified": false}' > "$SCOPE_STATE"; }

# Control: a green suite on a fresh session grants. Without it, every "not
# granted" below could be an instrument that grants nothing.
fresh_scope
scope_run pass "vendor/bin/phpunit" >/dev/null
if [[ "$(scope_flag verified)" == "true" ]]; then
    log_pass "control: a green suite grants the evidence"

    fresh_scope
    scope_run fail "vendor/bin/phpunit" >/dev/null
    OUTPUT=$(scope_run pass "vendor/bin/phpunit --filter testOrderIsRateLimited" "OK (1 test, 2 assertions)")
    if [[ "$(scope_flag verified)" == "false" && "$(scope_flag last_test_failed)" == "true" \
          && "$OUTPUT" == *"'vendor/bin/phpunit'"* ]]; then
        log_pass "the failing test alone, green, does not restore the suite's evidence and names the red run"
    else
        log_fail "a filtered green run after a red suite" "state=$(jq -c . "$SCOPE_STATE") output=$OUTPUT"
    fi

    scope_run pass "vendor/bin/phpunit" >/dev/null
    if [[ "$(scope_flag verified)" == "true" && "$(scope_flag last_test_failed)" == "false" ]]; then
        log_pass "the whole suite green afterwards restores it"
    else
        log_fail "the suite green after the filtered run" "state=$(jq -c . "$SCOPE_STATE")"
    fi

    fresh_scope
    scope_run fail "vendor/bin/phpunit --filter testInvoiceTotal" >/dev/null
    scope_run pass "vendor/bin/phpunit" >/dev/null
    if [[ "$(scope_flag verified)" == "true" ]]; then
        log_pass "a narrow red run is cleared by the whole suite green"
    else
        log_fail "the suite green after a narrow red run" "state=$(jq -c . "$SCOPE_STATE")"
    fi

    fresh_scope
    scope_run fail "pytest" >/dev/null
    scope_run pass "npm test" "12 passing (40ms)" >/dev/null
    if [[ "$(scope_flag verified)" == "false" ]]; then
        log_pass "another suite's green run does not clear this suite's failure"
    else
        log_fail "another suite green after a red pytest" "state=$(jq -c . "$SCOPE_STATE")"
    fi
    scope_run pass "pytest" "120 passed in 3.10s" >/dev/null
    if [[ "$(scope_flag verified)" == "true" ]]; then
        log_pass "both suites green: the evidence is granted"
    else
        log_fail "both suites green" "state=$(jq -c . "$SCOPE_STATE")"
    fi

    # The red phase of TDD on one test must not hide the suite that was red
    # before it: every red run stays outstanding until a run as wide passes.
    fresh_scope
    scope_run fail "vendor/bin/phpunit" >/dev/null
    scope_run fail "vendor/bin/phpunit --filter testOrderShips" >/dev/null
    scope_run pass "vendor/bin/phpunit --filter testOrderShips" "OK (1 test, 3 assertions)" >/dev/null
    if [[ "$(scope_flag verified)" == "false" ]]; then
        log_pass "a test driven green on its own leaves the earlier red suite outstanding"
    else
        log_fail "TDD on one test after a red suite" "state=$(jq -c . "$SCOPE_STATE")"
    fi

    # The same suite started through a launcher or another path to the same
    # runner is the same run, not a narrower one.
    fresh_scope
    scope_run fail "vendor/bin/phpunit" >/dev/null
    scope_run pass "php vendor/bin/phpunit" >/dev/null
    if [[ "$(scope_flag verified)" == "true" ]]; then
        log_pass "the same suite behind a launcher clears the red run"
    else
        log_fail "the same suite behind a launcher" "state=$(jq -c . "$SCOPE_STATE")"
    fi
    fresh_scope
    scope_run fail "vendor/bin/phpunit" >/dev/null
    scope_run pass "./vendor/bin/phpunit" >/dev/null
    if [[ "$(scope_flag verified)" == "true" ]]; then
        log_pass "the same runner through another path clears the red run"
    else
        log_fail "the same runner through another path" "state=$(jq -c . "$SCOPE_STATE")"
    fi
else
    log_fail "control: a green suite grants the evidence" \
        "granted nothing: state=$(jq -c . "$SCOPE_STATE" 2>/dev/null); the scope assertions are undetermined"
fi

rm -rf "$FAKE_HOME"

test_summary
