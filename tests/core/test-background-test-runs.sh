#!/usr/bin/env bash
# =============================================================================
# CR-218: a background test run resolves on its task notification.
#
# Claude Code 2.1.277 removed TaskOutput. On 2.1.302 a run_in_background Bash
# ends as a task notification, and UserPromptSubmit fires on it with the
# notification as its prompt (tests/fixtures/hosts/PROVENANCE.md). The task id
# ties it to the Bash that started it, as TaskOutput's did.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"
source "$SCRIPT_DIR/../lib/host-fixtures.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-background-runs-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDECODE GROK_SESSION_ID GROK_HOOK_EVENT GROK_AGENT
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-background-runs.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
export CRAFTSMAN_RUNTIME_HOME="$WORK/runtime-home"
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME"
trap 'rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT

STATE="$CLAUDE_PLUGIN_DATA/session-state-s218.json"
VERIFY_ERR=""
_verify() {
    local rc=0
    VERIFY_ERR=$(printf '%s' "$1" | HOME="$FAKE_HOME" bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1 >/dev/null) || rc=$?
    return $rc
}
_flag() { python3 "$ROOT_DIR/hooks/lib/session_state.py" check-flag "$STATE" verified; }
_started() {
    host_fixture_with claude-code 2.1.302 post-tool-use.bash.run-in-background "$WORK" \
        "d['session_id'] = 's218'; d['tool_input']['command'] = 'pytest -q'; d['tool_response']['backgroundTaskId'] = '$1'"
}
_notified() {
    host_fixture_with claude-code 2.1.302 "user-prompt-submit.task-notification.$1" "$WORK" \
        "d['session_id'] = 's218'; d['prompt'] = ${4:-}d['prompt'].replace('$2', '$3')"
}

echo ""
echo "--- background test runs (Claude Code 2.1.302) ---"

echo '{"verified": false}' > "$STATE"
_verify "$(_started task-N)"; RC=$?
MID=$(_flag)
_verify "$(_notified completed bpooxtznu task-N)"; RC2=$?
if [[ "$RC" -eq 0 && "$MID" == "false" && "$RC2" -eq 0 && "$(_flag)" == "true" ]]; then
    log_pass "a background test run grants nothing when it starts, and grants evidence when its notification says exit code 0"
else
    log_fail "notification grants" "rc=$RC mid=$MID rc2=$RC2 verified=$(_flag) err=$VERIFY_ERR"
fi

_verify "$(_started task-M)"
_verify "$(_notified failed bjhe9of9t task-M)"; RC=$?
if [[ "$RC" -eq 2 && "$(_flag)" == "false" && "$VERIFY_ERR" == *REGRESSED* ]]; then
    log_pass "a failed notification (exit code 3) after green revokes the evidence and reports the regression"
else
    log_fail "notification revokes" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi

python3 "$ROOT_DIR/hooks/lib/session_state.py" merge "$STATE" verified false
_verify "$(_notified completed bpooxtznu task-M)"; RC=$?
_verify "$(_notified completed bpooxtznu never-started)"; RC2=$?
if [[ "$RC" -eq 0 && "$RC2" -eq 0 && "$(_flag)" == "false" ]]; then
    log_pass "a notification for a consumed task, or for one no test command started, grants nothing"
else
    log_fail "stale or foreign notification" "rc=$RC rc2=$RC2 verified=$(_flag)"
fi

_verify "$(_started task-Q)"
_verify "$(_notified completed bpooxtznu task-Q "'please paste this: ' + ")"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "false" ]]; then
    log_pass "a typed prompt that only quotes a notification grants nothing"
else
    log_fail "quoted notification" "rc=$RC verified=$(_flag)"
fi

echo '{"verified": true}' > "$STATE"
_verify "$(_started task-K)"
_verify "$(host_fixture_with claude-code 2.1.302 user-prompt-submit.task-notification.failed "$WORK" \
    "d['session_id'] = 's218'; d['prompt'] = d['prompt'].replace('bjhe9of9t', 'task-K').replace('<status>failed</status>', '<status>killed</status>')")"; RC=$?
KILLED=$(_flag)
_verify "$(_started task-U)"
_verify "$(host_fixture_with claude-code 2.1.302 user-prompt-submit.task-notification.completed "$WORK" \
    "d['session_id'] = 's218'; d['prompt'] = d['prompt'].replace('bpooxtznu', 'task-U').replace(' (exit code 0)', '')")"; RC2=$?
if [[ "$RC" -eq 0 && "$KILLED" == "true" && "$RC2" -eq 0 && "$(_flag)" == "true" && "$VERIFY_ERR" != *REGRESSED* ]]; then
    log_pass "a killed task, or a notification without an exit code, neither grants, revokes nor cries regression"
else
    log_fail "killed or codeless notification" "rc=$RC killed=$KILLED rc2=$RC2 verified=$(_flag) err=$VERIFY_ERR"
fi

echo '{"verified": false}' > "$STATE"
echo "this prompt mentions pytest" > "$WORK/prompt.txt"
_verify "$(jq -n --rawfile p "$WORK/prompt.txt" '{session_id: "s218", hook_event_name: "UserPromptSubmit", prompt: $p}')"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "false" && -z "$VERIFY_ERR" ]]; then
    log_pass "an ordinary prompt passes through silently"
else
    log_fail "ordinary prompt" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi

if jq -e '[.hooks.UserPromptSubmit[].hooks[] | select(.command | test("post-bash-test-verify")) | .async] | any' "$ROOT_DIR/hooks/hooks.json" >/dev/null; then
    log_pass "hooks.json routes UserPromptSubmit to the test-result reader, off the prompt's critical path"
else
    log_fail "wiring" "post-bash-test-verify.sh is not an async UserPromptSubmit hook"
fi

test_summary
