#!/usr/bin/env bash
# =============================================================================
# Post-Bash Test Auto-Verify Hook
# Sets verified=true when a test suite is seen to pass, revokes it when one is
# seen to fail. "Seen" means decoded from what the host actually sent
# (hooks/lib/tool_result.py, fixtures under tests/fixtures/hosts):
#   Claude Code   a passing run is a PostToolUse (no exit code in the object:
#                 a non-zero exit is a PostToolUseFailure, whose `error` names
#                 it); a run_in_background run resolves later on TaskOutput,
#                 tied to its Bash by task id.
#   Codex         the shell output is a bare string with no exit code, so a
#                 run there is `unknown`: no evidence granted, none revoked.
# The reader this replaces took `tool_result.exit_code` (a field no host
# sends) and defaulted it to 1: a passing suite became "REGRESSED" (audit
# CR-117, C2).
#
# TRIGGERS: PostToolUse for Bash|TaskOutput, PostToolUseFailure for Bash
# EXIT CODES: 0 = pass; 2 = a suite green earlier this session now fails
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "post-bash-test-verify" "standard,strict" || exit 0

INPUT=$(cat)

DECODED=$(printf '%s' "$INPUT" | python3 "${SCRIPT_DIR}/lib/tool_result.py" 2>/dev/null) || exit 0
STATE=$(printf '%s' "$DECODED" | jq -r '.state // "unknown"')
EXIT_CODE=$(printf '%s' "$DECODED" | jq -r '.exit_code // empty')
COMMAND=$(printf '%s' "$DECODED" | jq -r '.command // empty')
TASK_ID=$(printf '%s' "$DECODED" | jq -r '.task_id // empty')
TOOL=$(printf '%s' "$DECODED" | jq -r '.tool // empty')

# Which commands run a test suite is the packs' knowledge. The literal list
# this replaces meant the deterministic verification loop (ADR-0023) was blind
# to every language whose runner it had not been taught, so `flutter test`
# failing left the session's "verified" flag standing.
#
# run-tests.sh stays here because it is this plugin's own runner, not any
# language's: it belongs to the engine, and no pack should have to claim it.
# The runner has to be INVOKED: it STARTS a command, optionally behind a
# launcher (npx, poetry run, python -m) or a path (./bin/pytest). `echo pytest`
# and `cat docs/pytest-notes.md` matched the bare word (review of e372e85, F3),
# and `echo 'python -m pytest -q'` matched the launcher inside a quoted string
# (challenge review of e2acf22, F4): the pattern is anchored at the start of
# the command it is tested against, which _last_command extracts.
_runner_names() {
    local pattern="run-tests\\.sh" command
    while IFS= read -r command; do
        [[ -z "$command" ]] && continue
        [[ ! "$command" =~ ^[A-Za-z0-9_./\ -]+$ ]] && continue
        pattern="${pattern}|$(printf '%s' "$command" | sed 's/[.]/\\./g')"
    done <<< "$(lang_all_capability test_commands 2>/dev/null)"
    printf '(%s)' "$pattern"
}

_test_command_pattern() {
    local pattern="run-tests\\.sh" command
    while IFS= read -r command; do
        [[ -z "$command" ]] && continue
        # Commands become part of a regex, and manifests are repository-supplied
        # data. Accept a conservative charset and escape the rest.
        [[ ! "$command" =~ ^[A-Za-z0-9_./\ -]+$ ]] && continue
        pattern="${pattern}|$(printf '%s' "$command" | sed 's/[.]/\\./g')"
    done <<< "$(lang_all_capability test_commands 2>/dev/null)"
    printf '^[[:space:]]*((npx|bunx|poetry run|pipenv run|uv run|python3? -m|php|time|env) )?([^[:space:]'"'"'"]*/)?(%s)([[:space:]]|$)' "$pattern"
}

# This session's file, named by the payload's session_id (lib/session-files.sh).
# The ~/.claude bridge is for skills in the Bash tool, which have no payload;
# a hook has one and does not read a machine-wide pointer another host's
# session may have written.
source "${SCRIPT_DIR}/lib/session-files.sh"
session_files_bind "$INPUT"
SESSION_STATE=$(session_file session-state.json)

LIB_DIR="${SCRIPT_DIR}/lib"

# A TaskOutput names the task, not the command: the Bash that started it
# recorded the pair below, and the result is read back against it.
if [[ "$TOOL" == "TaskOutput" ]]; then
    [[ -z "$TASK_ID" ]] && exit 0
    COMMAND=$(python3 "$LIB_DIR/session_state.py" read "$SESSION_STATE" pending_test_tasks '[]' 2>/dev/null \
        | jq -r --arg id "$TASK_ID" '[.[] | select(.task_id == $id)] | last | .command // empty' 2>/dev/null)
    [[ -z "$COMMAND" ]] && exit 0
fi
[[ -z "$COMMAND" ]] && exit 0

source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
pack_loader_init

# Cheap pre-filter: no runner name anywhere, nothing to decide.
if ! echo "$COMMAND" | grep -qE "$(_runner_names)"; then
    exit 0
fi

# The command's result is the RUNNER's result only when the runner is what
# decided it. Measured (independent verification, 2026-09-15): `true || pytest`
# granted evidence for a runner that never ran, `false && pytest` revoked it
# for a `false`, `pytest fail; true` granted it for a green `true`. So:
#   grant   only when the runner is the LAST command (`cd api && pytest`,
#           `pytest -q`), with no `||` anywhere and no pipe in that last command
#   revoke  when the runner is the LAST command, because after a failure that
#           may be the suite, "the suite passed in this session" is no longer
#           a claim this layer can make. `verified` gates a push, so doubt
#           revokes: the cost is one re-run, the cost of the other direction
#           is a red tree pushed. Measured 2026-09-20: `echo 1 > pytest.rc &&
#           ./bin/pytest -q` exited 1 with the suite red and left the
#           evidence green.
#   WAKE    (exit 2, "REGRESSED") only when the runner is the WHOLE command:
#           a failed `cd x && pytest` may be the cd, and crying regression on
#           a guess is an invented regression. A compound failure revokes
#           quietly and says how to restore the evidence.
# Anything else is unknown: nothing granted, nothing revoked, and said so.
_last_command() { printf '%s' "$1" | tr '\n' ';' | sed 's/&&/;/g' | awk -F';' '{for (i=NF; i>0; i--) if ($i ~ /[^[:space:]]/) {print $i; exit}}'; }
LAST=$(_last_command "$COMMAND")
RUNNER_LAST=false; RUNNER_ALONE=false
if [[ "$COMMAND" != *"||"* && "$LAST" != *"|"* ]] && printf '%s' "$LAST" | grep -qE "$(_test_command_pattern)"; then
    RUNNER_LAST=true
    [[ "$COMMAND" != *"&&"* && "$COMMAND" != *";"* && "$COMMAND" != *$'\n'* ]] && RUNNER_ALONE=true
fi
if [[ "$RUNNER_LAST" != true ]]; then
    echo "craftsman: '${COMMAND}' is a compound command; its result is not the test runner's, so verification evidence is unchanged (run the runner as the last or only command)." >&2
    exit 0
fi

case "$STATE" in
    running)
        # Started in the background: remembered so the TaskOutput that ends
        # it can be read as this command's result. One entry per task: a poll
        # that reports "still running" is the same task, and appending it
        # again evicted the other pending tasks (review of e372e85, F4).
        [[ -z "$TASK_ID" ]] && exit 0
        python3 "$LIB_DIR/session_state.py" list-upsert "$SESSION_STATE" pending_test_tasks task_id \
            "$(jq -n --arg id "$TASK_ID" --arg c "$COMMAND" '{task_id: $id, command: $c}')" 20 2>/dev/null || true
        exit 0
        ;;
    interrupted)
        exit 0
        ;;
    unknown)
        echo "craftsman: '${COMMAND}' ran, but this host's tool event carries no exit code; verification evidence is unchanged (neither granted nor revoked)." >&2
        exit 0
        ;;
esac

# A task that ended is consumed: polling its result again must not grant the
# evidence a later failure revoked (review of e372e85, F5).
[[ "$TOOL" == "TaskOutput" ]] && python3 "$LIB_DIR/session_state.py" list-remove "$SESSION_STATE" pending_test_tasks task_id "$TASK_ID" 2>/dev/null || true

CURRENT=$(python3 "$LIB_DIR/session_state.py" check-flag "$SESSION_STATE" verified 2>/dev/null || echo "false")

# Failing test run (ADR-0023): revoke verification evidence, feed the failure
# log to the background monitor, and wake the session (exit 2 + asyncRewake)
# only on a regression - the suite was green earlier in this session.
if [[ "$STATE" == "failed" ]]; then
    DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
    mkdir -p "$DATA_DIR" 2>/dev/null || true
    printf '%s test failure: %s (exit %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMMAND" "${EXIT_CODE:-?}" \
        >> "${DATA_DIR}/test-failures.log" 2>/dev/null || true
    if [[ "$CURRENT" == "true" ]]; then
        python3 "$LIB_DIR/session_state.py" merge "$SESSION_STATE" verified false 2>/dev/null || true
        # The wake is for a failure this layer can attribute to the runner.
        if [[ "$RUNNER_ALONE" != true ]]; then
            echo "craftsman: '${COMMAND}' exited ${EXIT_CODE:-non-zero} and ends on a test runner; which command failed is not knowable from here, so the verification evidence is revoked. Run the runner alone to grant it again." >&2
            exit 0
        fi
        echo "Test suite REGRESSED: '${COMMAND}' now exits ${EXIT_CODE:-non-zero} but was green earlier this session. Verification evidence revoked - fix the suite before claiming completion or pushing." >&2
        exit 2
    fi
    exit 0
fi

# Passing test run: set verified (skip if already set)
[[ "$CURRENT" == "true" ]] && exit 0
python3 "$LIB_DIR/session_state.py" set-verified "$SESSION_STATE" 2>/dev/null

exit 0
