#!/usr/bin/env bash
# =============================================================================
# CR-258: the agent does not switch the project's git hooks off.
#
# anthropics/claude-code #40117 (closed "not planned" on 2026-05-07): a model
# committed six times in a row with `--no-verify` and `git stash`, 63
# integration tests failing, against CLAUDE.md and memory rules forbidding
# it. A rule the model reads is advice; a PreToolUse refusal is not. Each
# case below runs the real hook on a Bash payload; the wiring is read from
# hooks/hooks.json, and the cost is compared with pre-push-verify.sh, which
# runs on the same git commands.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-git-bypass-$$"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE
mkdir -p "$CLAUDE_PLUGIN_DATA"
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

GUARD="$ROOT_DIR/hooks/git-bypass-guard.sh"
_run() {
    python3 -c 'import json, sys; print(json.dumps({"session_id": "s258", "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1" \
        | bash "$GUARD" 2>/dev/null
}
# An allowed command prints nothing at all, and jq prints nothing for no input.
_decision() {
    local out
    out=$(_run "$1")
    [[ -z "$out" ]] && { echo "allow"; return; }
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null
}

expect_deny() {
    local command="$1" names="$2" out decision reason
    out=$(_run "$command")
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
    if [[ "$decision" == "deny" && "$reason" == *"$names"* ]]; then
        log_pass "refused: $command"
    else
        log_fail "not refused: $command" "decision=${decision:-none} reason=${reason:0:120}"
    fi
}

expect_allow() {
    local command="$1" decision
    decision=$(_decision "$command")
    if [[ "$decision" == "allow" && -f "$GUARD" ]]; then
        log_pass "allowed: $command"
    else
        log_fail "refused a legitimate command: $command" "decision=$decision"
    fi
}

echo ""
echo "--- the bypasses are refused ---"
expect_deny 'git commit -m "fix order total" --no-verify' "--no-verify"
expect_deny 'git commit -nm "fix order total"' "-n"
expect_deny 'git commit -am "fix" -n' "-n"
expect_deny 'git push --no-verify origin main' "--no-verify"
expect_deny 'git -c core.hooksPath=/dev/null commit -m "fix"' "core.hooksPath"
expect_deny 'git config core.hooksPath /dev/null' "core.hooksPath"
expect_deny 'git stash && git commit -m "fix" && git stash pop' "git stash"
expect_deny 'HUSKY=0 git commit -m "fix"' "HUSKY=0"
expect_deny 'SKIP=phpstan,phpunit git commit -m "fix"' "SKIP="
expect_deny 'cd app && git commit --no-verify -m "fix"' "--no-verify"
expect_deny 'git merge --no-verify feature/invoice' "--no-verify"

echo ""
echo "--- ordinary git work is not ---"
expect_allow 'git commit -m "fix order total"'
expect_allow 'git commit -m "-n is a flag the guard knows"'
expect_allow 'git commit -m "never use --no-verify here"'
expect_allow 'git commit -F msg.txt -a'
expect_allow 'git push -n origin main'
expect_allow 'git merge -n feature/invoice'
expect_allow 'git stash'
expect_allow 'git stash pop && git commit -m "fix"'
expect_allow 'git config --get core.hooksPath'
expect_allow 'git config --unset core.hooksPath'
expect_allow 'git config --unset core.hooksPath .husky'
expect_allow 'git log --oneline -5'
expect_allow 'echo "git commit --no-verify"'

echo ""
echo "--- wiring: PreToolUse on git commands, fail closed ---"
WIRING=$(jq -c '[.hooks.PreToolUse[] | select(.matcher | test("Bash")) | .hooks[] | select(.command | contains("git-bypass-guard.sh")) | {if, onFailure}]' "$ROOT_DIR/hooks/hooks.json" 2>/dev/null)
if [[ "$WIRING" == '[{"if":"Bash(git *)","onFailure":"block"}]' ]]; then
    log_pass "hooks.json runs the guard on every git subcommand, and a guard that cannot answer refuses"
else
    log_fail "guard wiring" "got ${WIRING:-nothing}"
fi

echo ""
echo "--- cost: no more than pre-push-verify.sh on the same git command ---"
_median_ms() {
    local hook="$1" payload="$2" runs=() start end
    for _ in 1 2 3 4 5 6 7; do
        start=$(python3 -c 'import time; print(int(time.perf_counter() * 1000))')
        printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1
        end=$(python3 -c 'import time; print(int(time.perf_counter() * 1000))')
        runs+=($((end - start)))
    done
    printf '%s\n' "${runs[@]}" | sort -n | sed -n 4p
}
PUSH='{"session_id":"s258","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
GUARD_MS=$(_median_ms "$GUARD" "$PUSH")
PUSH_MS=$(_median_ms "$ROOT_DIR/hooks/pre-push-verify.sh" "$PUSH")
if [[ -f "$GUARD" && "$GUARD_MS" -le $((PUSH_MS * 3 / 2)) ]]; then
    log_pass "guard median ${GUARD_MS}ms, pre-push-verify ${PUSH_MS}ms"
else
    log_fail "guard costs more than 1.5x pre-push-verify" "guard=${GUARD_MS}ms pre-push=${PUSH_MS}ms"
fi

test_summary
