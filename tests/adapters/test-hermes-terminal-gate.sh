#!/usr/bin/env bash
# =============================================================================
# Between two conclusions, a Hermes agent could push.
#
# The conclusion gate (pre-verify.sh) judges a turn when the agent is about to
# conclude. Between two conclusions the agent can `git commit` and `git push`
# through the `terminal` tool, which no craftsman hook saw: a violation the
# conclusion would have refused was already on the remote. A control cycle an
# order of magnitude slower than the object it controls is an audit after the
# fact (guardrail review, MUST-FIX 4).
#
# The `terminal` branch of pre-tool-call.sh refuses `git push` (and `git
# commit` under `strict`) unless the conclusion gate's last verdict is a pass
# ON THIS TREE: the verdict records the tree it judged, and a pass on one tree
# does not authorise pushing another. With no verdict at all the push is
# refused too: no verdict is not a clean verdict (ADR-0029).
#
# Wire (https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks):
# stdin {"hook_event_name":"pre_tool_call","tool_name":"terminal",
#        "tool_input":{"command":"..."},"session_id":"...","cwd":"..."};
# exit 2 or {"action":"block","message":"..."} refuses the call.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

GATE="$ROOT_DIR/adapters/hermes/pre-tool-call.sh"
VERIFY="$ROOT_DIR/adapters/hermes/pre-verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-hermes-terminal.XXXXXX")
PREV_PWD="$PWD"
cleanup() { cd "$PREV_PWD" || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== Hermes terminal gate ==="

REPO="$WORK/repo"
mkdir -p "$REPO/src"
cd "$REPO" && git init -q . 2>/dev/null
printf '<?php\ndeclare(strict_types=1);\nfinal class Ok { private function __construct() {} }\n' > src/Ok.php
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm fixtures >/dev/null 2>&1

# The shell wire, as Hermes serialises it.
terminal() {
    python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "pre_tool_call", "tool_name": "terminal",
                  "tool_input": {"command": sys.argv[1]}, "session_id": "s1",
                  "cwd": sys.argv[2], "profile": "default", "extra": {}}))' "$1" "$REPO"
}
gate() {
    local rc=0 out
    out=$(terminal "$1" | bash "$GATE" 2>/dev/null) || rc=$?
    printf '%s\n%s' "$rc" "$out"
}
verify_payload() {
    python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "pre_verify", "tool_name": None, "tool_input": None,
                  "session_id": "s1", "cwd": sys.argv[1],
                  "extra": {"changed_paths": [], "coding": True, "attempt": 0}}))' "$REPO"
}
refused() { [[ "${1%%$'\n'*}" == "2" ]] && printf '%s' "$1" | grep -q '"action": *"block"'; }

# --- No verdict yet: the push is refused, and the message names the gate ------
out=$(gate "git push origin main")
if refused "$out" && printf '%s' "$out" | grep -qi "conclusion"; then
    log_pass "git push with no conclusion verdict is refused, naming the conclusion gate"
else
    log_fail "git push with no conclusion verdict is refused, naming the conclusion gate" "got: $out"
fi

# --- A pipeline hides nothing --------------------------------------------------
out=$(gate "echo x && git push origin main")
if refused "$out" && ! printf '%s' "$out" | grep -q "could not judge"; then
    log_pass "git push inside a pipeline is refused too"
else
    log_fail "git push inside a pipeline is refused too" "got: $out"
fi

# --- Review of main eb54d13, B6: operators and wrappers hide nothing ---------
# `echo ok;git push` and `env git push` passed with exit 0 while `git push`
# was refused. A form the gate cannot qualify is refused, never let through.
B6_MISS=""
for hidden in "echo ok;git push" "env git push" "env -i PATH=/usr/bin git push" "command git push" \
              "GIT_TRACE=1 git push" "time git push" "nohup git push &" "xargs git push </dev/null" \
              "bash -c 'git push origin main'" "sh -c \"echo x; git push\"" "eval git push" \
              "echo \$(git push)" "sudo -u me git push"; do
    out=$(gate "$hidden")
    refused "$out" || B6_MISS+=" [$hidden]"
done
if [[ -z "$B6_MISS" ]]; then
    log_pass "B6: a push behind ;, env, command, a variable assignment, time, nohup, xargs, sh -c, eval, \$() or sudo is refused"
else
    log_fail "B6: a push behind an operator or a wrapper is refused" "allowed:$B6_MISS"
fi
B6_FALSE=""
for data in "echo 'git push later'" "git log --grep push" "grep -r 'git push' docs"; do
    out=$(gate "$data")
    [[ "${out%%$'\n'*}" == "0" ]] || B6_FALSE+=" [$data]"
done
if [[ -z "$B6_FALSE" ]]; then
    log_pass "B6 control: git push as quoted data, a grep pattern or a log filter passes untouched"
else
    log_fail "B6 control: data mentioning git push passes" "refused:$B6_FALSE"
fi

# --- Under strict, a commit waits for the conclusion as well ------------------
out=$(gate "git commit -m wip")
if refused "$out"; then
    log_pass "git commit under strict (the default) is refused without a pass"
else
    log_fail "git commit under strict (the default) is refused without a pass" "got: $out"
fi

# --- Anything else passes untouched -------------------------------------------
out=$(gate "ls -la")
if [[ "$out" == "0" ]]; then
    log_pass "a terminal command that is neither push nor commit passes untouched"
else
    log_fail "a terminal command that is neither push nor commit passes untouched" "got: $out"
fi
out=$(gate "git status && git log --oneline -3")
if [[ "$out" == "0" ]]; then
    log_pass "a read-only git command passes untouched"
else
    log_fail "a read-only git command passes untouched" "got: $out"
fi

# --- A failed conclusion: still refused ---------------------------------------
printf 'const bad: any = 1;\n' > src/Bad.ts
verify_out=$(verify_payload | bash "$VERIFY" 2>/dev/null)
if printf '%s' "$verify_out" | grep -q '"decision": *"block"'; then
    log_pass "control: the conclusion gate refuses the turn with a TS001 file in it"
else
    log_fail "control: the conclusion gate refuses the turn with a TS001 file in it" "got: $verify_out"
fi
out=$(gate "git push")
if refused "$out" && printf '%s' "$out" | grep -q "refused the last turn"; then
    log_pass "git push after a failed conclusion is refused, and says the gate refused the turn"
else
    log_fail "git push after a failed conclusion is refused, and says the gate refused the turn" "got: $out"
fi

# --- A passed conclusion on this tree: allowed --------------------------------
rm -f src/Bad.ts
verify_out=$(verify_payload | bash "$VERIFY" 2>/dev/null)
if [[ -z "$verify_out" ]]; then
    log_pass "control: the conclusion gate passes the clean turn silently"
else
    log_fail "control: the conclusion gate passes the clean turn silently" "got: $verify_out"
fi
out=$(gate "git commit -m ok")
if [[ "${out%%$'\n'*}" == "0" ]]; then
    log_pass "git commit after a pass on this tree is allowed"
else
    log_fail "git commit after a pass on this tree is allowed" "got: $out"
fi
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm "judged" >/dev/null 2>&1
out=$(gate "git push origin main")
if [[ "${out%%$'\n'*}" == "0" ]]; then
    log_pass "git push of the judged tree is allowed"
else
    log_fail "git push of the judged tree is allowed" "got: $out"
fi

# --- Review of main eb54d13, B7: the refspec decides what is published --------
# After a pass on HEAD, `git push origin unsafe` published another branch's
# tree with exit 0. Every source a push names must carry the judged tree.
CURRENT=$(git rev-parse --abbrev-ref HEAD)
git checkout -q -b unsafe >/dev/null 2>&1
printf 'const unsafe: any = 1;\n' > src/Unsafe.ts
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm "unsafe" >/dev/null 2>&1
git checkout -q "$CURRENT" >/dev/null 2>&1
B7_MISS=""
for other in "git push origin unsafe" "git push origin unsafe:main" "git push origin HEAD unsafe" \
             "git push --all origin" "git push --mirror origin" "git push origin +unsafe:refs/heads/main"; do
    out=$(gate "$other")
    refused "$out" || B7_MISS+=" [$other]"
done
if [[ -z "$B7_MISS" ]]; then
    log_pass "B7: a push naming another branch, --all or --mirror is refused after a pass on HEAD"
else
    log_fail "B7: a push publishing a tree the gate did not judge is refused" "allowed:$B7_MISS"
fi
B7_OK=""
for same in "git push origin HEAD" "git push origin $CURRENT" "git push -u origin HEAD:refs/heads/review" "git push origin :stale-branch"; do
    out=$(gate "$same")
    [[ "${out%%$'\n'*}" == "0" ]] || B7_OK+=" [$same]"
done
if [[ -z "$B7_OK" ]]; then
    log_pass "B7 control: pushing the judged HEAD under any name, or deleting a remote branch, is allowed"
else
    log_fail "B7 control: the judged tree is still pushable" "refused:$B7_OK"
fi
git branch -q -D unsafe >/dev/null 2>&1

# --- A pass on one tree does not authorise another ----------------------------
printf 'const later: any = 1;\n' > src/Later.ts
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm "after the pass" >/dev/null 2>&1
out=$(gate "git push origin main")
if refused "$out" && printf '%s' "$out" | grep -q "different tree"; then
    log_pass "git push of a tree the conclusion never judged is refused, pass or no pass, and says so"
else
    log_fail "git push of a tree the conclusion never judged is refused, pass or no pass, and says so" "got: $out"
fi
git reset -q --hard HEAD~1 >/dev/null 2>&1

# --- Under moderate, only the push waits --------------------------------------
printf 'const again: any = 1;\n' > src/Again.ts
verify_payload | bash "$VERIFY" >/dev/null 2>&1
printf 'strictness: moderate\n' > .craft-config.yml
out=$(gate "git commit -m wip")
if [[ "${out%%$'\n'*}" == "0" ]]; then
    log_pass "git commit under moderate passes without a conclusion verdict"
else
    log_fail "git commit under moderate passes without a conclusion verdict" "got: $out"
fi
out=$(gate "git push")
if refused "$out"; then
    log_pass "git push under moderate still waits for a pass"
else
    log_fail "git push under moderate still waits for a pass" "got: $out"
fi
rm -f .craft-config.yml src/Again.ts

# --- git -C names the workspace; the payload cwd is a hint -------------------
out=$(terminal "git -C $REPO push" | sed "s#\"cwd\": \"[^\"]*\"#\"cwd\": \"/\"#" | bash "$GATE" 2>/dev/null; echo "rc=$?")
if printf '%s' "$out" | grep -q 'rc=2'; then
    log_pass "git -C <repo> push with a gateway cwd of / is judged in that repo"
else
    log_fail "git -C <repo> push with a gateway cwd of / is judged in that repo" "got: $out"
fi

test_summary
