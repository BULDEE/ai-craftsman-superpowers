#!/usr/bin/env bash
# =============================================================================
# Shared Test Helpers - Craftsman Test Framework
# Source this from any test file to get assertions, counters, and JSON utils.
#
# Usage:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/test-helpers.sh"
#
# Provides:
#   - log_pass / log_fail - colored assertion logging with counters
#   - assert_exit_code - check exit code of last piped result
#   - assert_json_valid - validate JSON output
#   - assert_json_field - check specific JSON field value
#   - assert_json_contains - check JSON output contains string
#   - assert_contains / assert_not_contains - string matching
#   - run_hook - generic hook runner (stdin JSON → exit_code|output)
#   - test_summary - print pass/fail summary, exit with correct code
#   - setup_test_env / cleanup_test_env - temp directory management
# =============================================================================

# Guard against double-sourcing
[[ -n "${_TEST_HELPERS_LOADED:-}" ]] && return 0
_TEST_HELPERS_LOADED=1

# --- Counters ---
TESTS_PASSED=0
TESTS_FAILED=0

# --- Colors (safe for pipes) ---
if [[ -t 1 ]]; then
    _GREEN='\033[0;32m'
    _RED='\033[0;31m'
    _NC='\033[0m'
else
    _GREEN=''
    _RED=''
    _NC=''
fi

# --- Core Assertions ---

log_pass() {
    echo -e "  ${_GREEN}✓${_NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "  ${_RED}✗${_NC} $1: ${2:-}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# assert_exit_code "description" "expected" "actual"
assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$desc"
    else
        log_fail "$desc" "expected exit $expected, got $actual"
    fi
}

# assert_json_valid "description" "json_string"
assert_json_valid() {
    local desc="$1" json="$2"
    if echo "$json" | jq . >/dev/null 2>&1; then
        log_pass "$desc"
    else
        log_fail "$desc" "invalid JSON: $(echo "$json" | head -1)"
    fi
}

# assert_json_field "description" "json_string" "field_path" "expected_value"
assert_json_field() {
    local desc="$1" json="$2" field="$3" expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$desc"
    else
        log_fail "$desc" "expected $field=$expected, got $actual"
    fi
}

# assert_json_contains "description" "json_string" "pattern"
assert_json_contains() {
    local desc="$1" json="$2" pattern="$3"
    if echo "$json" | grep -qi "$pattern"; then
        log_pass "$desc"
    else
        log_fail "$desc" "JSON output does not contain '$pattern'"
    fi
}

# assert_contains "description" "haystack" "needle"
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qi "$needle"; then
        log_pass "$desc"
    else
        log_fail "$desc" "output does not contain '$needle'"
    fi
}

# assert_not_contains "description" "haystack" "needle"
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if ! echo "$haystack" | grep -qi "$needle"; then
        log_pass "$desc"
    else
        log_fail "$desc" "output should not contain '$needle'"
    fi
}

# --- Hook Runners ---

# run_hook "hook_script_path" "stdin_json"
# Returns: "exit_code|stdout"
run_hook() {
    local hook="$1" stdin_data="${2:-}"
    local output exit_code
    output=$(echo "$stdin_data" | bash "$hook" 2>/dev/null) || true
    exit_code=${PIPESTATUS[1]:-$?}
    # Re-run to get accurate exit code (pipe masks it)
    if [[ -n "$stdin_data" ]]; then
        echo "$stdin_data" | bash "$hook" >/dev/null 2>&1
        exit_code=$?
    else
        bash "$hook" </dev/null >/dev/null 2>&1
        exit_code=$?
    fi
    echo "$exit_code|$output"
}

# --- Environment ---

# setup_test_env - create isolated temp dir, export CLAUDE_PLUGIN_DATA
setup_test_env() {
    export CLAUDE_PLUGIN_DATA="/tmp/craftsman-tests-$$"
    mkdir -p "$CLAUDE_PLUGIN_DATA"
}

# cleanup_test_env - remove temp dir
cleanup_test_env() {
    [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] && rm -rf "$CLAUDE_PLUGIN_DATA"
}

# --- Liveness preconditions for guard tests ---
#
# A security guard is usually asserted by the absence of something bad: no raw
# markup in the page, no oversized file in the baseline, no attacker string in
# the map. A dead program also produces absence, so those assertions cannot
# tell a working guard from deleted code. Stubbing dashboard.py, codemap.py and
# ratchet.py to `sys.exit(1)` left 19 of the 22 hostile-repo assertions green.
#
# Every absence assertion is therefore preceded by one of these, which fail
# loudly when the tool under test produced nothing at all.

# Gate the dependent assertion on these rather than merely reporting alongside
# it. A guard whose tool never ran is not verified, it is undetermined, and
# printing a green tick for it is the whole defect these helpers exist to close:
#
#   assert_produced_file "dashboard" "$OUT" && { ...absence assertion... }
#
# assert_produced_file <label> <path> - the tool wrote a non-empty artifact
assert_produced_file() {
    local label="$1" path="$2"
    if [[ -s "$path" ]]; then
        return 0
    fi
    log_fail "$label: tool produced no output" \
        "guard assertions skipped - they would have passed against deleted code"
    return 1
}

# assert_produced_output <label> <text> - the tool wrote something to stdout
assert_produced_output() {
    local label="$1" text="$2"
    if [[ -n "$text" ]]; then
        return 0
    fi
    log_fail "$label: tool produced no output" \
        "guard assertions skipped - they would have passed against deleted code"
    return 1
}

# tool_alive <label> <command...> - does this tool still work on benign input?
# For guards asserted by an empty result (a size cap, a refusal), emptiness is
# the pass condition, so liveness has to come from a separate benign run.
tool_alive() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        return 0
    fi
    log_fail "$label: tool does not run at all" \
        "guard assertions skipped - emptiness would have read as a pass"
    return 1
}

# Bridge files live in the real ~/.claude so skills can find them without
# CLAUDE_PLUGIN_ROOT, which means any suite invoking session-start.sh rewrites
# the developer's own bridges to throwaway test paths. Back them up as a set:
# guarding them one by one is how the metrics bridge got clobbered by
# test-hooks.sh the day it was introduced.
_CRAFTSMAN_BRIDGES=(
    "${HOME}/.claude/craftsman-session-state-path"
    "${HOME}/.claude/craftsman-metrics-db-path"
)

backup_home_bridges() {
    local bridge
    for bridge in "${_CRAFTSMAN_BRIDGES[@]}"; do
        [[ -f "$bridge" ]] && cp "$bridge" "${bridge}.test-backup"
    done
    return 0
}

restore_home_bridges() {
    local bridge
    for bridge in "${_CRAFTSMAN_BRIDGES[@]}"; do
        [[ -f "${bridge}.test-backup" ]] && mv "${bridge}.test-backup" "$bridge"
    done
    return 0
}

# --- Portable timeout ---
#
# `timeout` is GNU coreutils and is absent on a stock macOS. Tests that wrapped
# a command in it got exit 127 and empty output on those machines, which reads
# as "the tool produced nothing" rather than "the timeout binary is missing":
# four assertions failed that way on the macOS CI runner while passing on a Mac
# with coreutils installed. The fallback is a background job with a watchdog,
# so the budget still holds where the binary does not exist.
run_with_timeout() {
    local seconds="$1"; shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
        return $?
    fi

    # <&0 matters: bash redirects a background job's stdin from /dev/null unless
    # it is explicitly redirected, and every hook in this repository is fed its
    # payload on stdin. Without it the command reads nothing and returns as if
    # there were no input.
    "$@" <&0 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $waited -ge $seconds ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid"
}

# --- Summary ---

# test_summary - print results and exit with correct code
test_summary() {
    echo ""
    echo "==================================="
    echo -e " ${_GREEN}Passed:${_NC} $TESTS_PASSED"
    echo -e " ${_RED}Failed:${_NC} $TESTS_FAILED"
    echo "==================================="
    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}
