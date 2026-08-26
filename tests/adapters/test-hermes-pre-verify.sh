#!/usr/bin/env bash
# =============================================================================
# The Hermes pre_verify adapter speaks Hermes, not Claude Code.
#
# Two contract differences make this worth pinning. Hermes ignores the exit
# code (agent/shell_hooks.py logs a non-zero exit and lets the agent continue),
# so a verdict that is not JSON on stdout is no verdict at all. And a hook that
# speaks when it should stay quiet costs the agent a whole extra turn, bounded
# only by agent.max_verify_nudges.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

HOOK="$ROOT_DIR/adapters/hermes/pre-verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-hermes.XXXXXX")
PREV_PWD="$PWD"

echo ""
echo "=== Hermes pre_verify adapter ==="

mkdir -p "$WORK/src"
cd "$WORK" && git init -q . 2>/dev/null
# Scope is derived from git, not from the payload, so a "clean turn" means a
# clean worktree. Fixtures are committed and each case dirties only what it
# needs, otherwise every assertion would see the previous case's leftovers.
printf '<?php\ndeclare(strict_types=1);\nfinal class Ok { private function __construct() {} }\n' > src/Ok.php
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm fixtures >/dev/null 2>&1
printf 'const bad: any = 1;\n' > src/Bad.ts

_payload() {
    python3 -c '
import json, sys
print(json.dumps({
    "hook_event_name": "pre_verify", "tool_name": None, "tool_input": None,
    "session_id": "s1", "cwd": sys.argv[1],
    "extra": {"changed_paths": sys.argv[2].split(","), "coding": sys.argv[3] == "1",
              "attempt": int(sys.argv[4]), "final_response": "done", "model": "m",
              "platform": "cli"},
}))' "$WORK" "$1" "$2" "${3:-0}"
}

OUT=$(_payload "src/Bad.ts" 1 | bash "$HOOK" 2>/dev/null)
if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("decision")=="block" and d.get("reason") else 1)' 2>/dev/null; then
    log_pass "a blocking violation returns a block directive as JSON"
else
    log_fail "no verdict" "expected {\"decision\":\"block\",\"reason\":...}, got: ${OUT:-<empty>}"
fi

if printf '%s' "$OUT" | grep -q "TS001"; then
    log_pass "the directive names the rule the agent must fix"
else
    log_fail "verdict lacks detail" "rule id absent from: $OUT"
fi

# Silence is the contract for every case that is not a rejection: anything on
# stdout costs the agent an extra turn.
for case in "src/Bad.ts 0 non-coding session"; do
    set -- $case
    OUT=$(_payload "$1" "$2" | bash "$HOOK" 2>/dev/null)
    if [[ -z "$OUT" ]]; then
        log_pass "stays silent on a $3 $4"
    else
        log_fail "spurious verdict" "$3 $4 produced: $OUT"
    fi
done

# Hermes builds changed_paths from the tool name, not from the filesystem:
# agent/tool_dispatch_helpers.py returns [] for anything outside
# FILE_MUTATING_TOOL_NAMES, and only write_file and patch are in it. Every write
# through `terminal` (sed -i, python -c, tee, a redirect, git apply) is absent
# from the payload, so an adapter that trusted it would gate nothing at all.
printf 'const sneaky: any = 1;\n' > src/Sneaky.ts
OUT=$(_payload "" 1 | bash "$HOOK" 2>/dev/null)
if printf '%s' "$OUT" | grep -q "Sneaky.ts"; then
    log_pass "a file written outside the edit tools is still gated"
else
    log_fail "gate bypass" "a terminal write absent from changed_paths went unchecked"
fi

# An absolute or traversing path in the payload must not drag host files into
# the directive, nor the host's directory layout into the model's context.
OUT=$(_payload "../../../etc/hosts" 1 | bash "$HOOK" 2>/dev/null)
if ! printf '%s' "$OUT" | grep -q "etc/hosts"; then
    log_pass "a path outside the workspace never reaches the report"
else
    log_fail "containment" "host path leaked into the directive: $OUT"
fi
if ! printf '%s' "$OUT" | grep -q "$WORK"; then
    log_pass "reported paths are workspace-relative, not absolute"
else
    log_fail "path leak" "absolute host path in the directive: $OUT"
fi
rm -f src/Sneaky.ts

# A gate that could not run is not a clean file. Silence must only ever mean
# "the gate ran and found nothing", so every other outcome speaks on stderr.
rm -f src/Bad.ts
OUT=$(_payload "src/Ok.php" 1 | bash "$HOOK" 2>/dev/null)
if [[ -z "$OUT" ]]; then
    log_pass "a clean turn still produces no directive"
else
    log_fail "spurious verdict" "$OUT"
fi

# The gated party configures the gate: a turn that edits .craft-rules.yml or
# .craft-config.yml could switch its own violations to `ignore` before the scan
# reads them, and consent in Hermes survives script edits (the allowlist keys
# on the command string, not a hash). Such a turn is refused outright.
printf 'TS001: ignore\n' > .craft-rules.yml
OUT=$(_payload "" 1 | bash "$HOOK" 2>/dev/null)
if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("decision")=="block" else 1)' 2>/dev/null; then
    log_pass "a turn that edits the gate's own configuration is refused"
else
    log_fail "gate self-edit accepted" "expected a block, got: ${OUT:-<empty>}"
fi
if printf '%s' "$OUT" | grep -q "craft-rules"; then
    log_pass "the refusal names the gate file the turn touched"
else
    log_fail "unnamed gate file" "$OUT"
fi
rm -f .craft-rules.yml

# Non-critical findings surface once, on the first attempt, and never block: a
# warning repeated on every nudge would burn max_verify_nudges on advice, and a
# warning dropped entirely would break verdict parity with the other front-ends.
printf 'export default function f() { return 1 }\n' > src/Warn.ts
OUT=$(_payload "src/Warn.ts" 1 0 | bash "$HOOK" 2>/dev/null)
if [[ -n "$OUT" ]] && ! printf '%s' "$OUT" | grep -q '"decision"' && printf '%s' "$OUT" | grep -q "TS002"; then
    log_pass "advisory findings are surfaced without a block directive"
else
    log_fail "warnings dropped or blocking" "attempt 0 on a warn-only turn gave: ${OUT:-<empty>}"
fi
OUT=$(_payload "src/Warn.ts" 1 1 | bash "$HOOK" 2>/dev/null)
if [[ -z "$OUT" ]]; then
    log_pass "advisory findings stay silent after the first attempt"
else
    log_fail "warning loop" "attempt 1 still nudges: $OUT"
fi
if ! _payload "src/Warn.ts" 1 0 | bash "$HOOK" 2>/dev/null | grep -q "refactor"; then
    log_pass "a non-structural finding carries no refactor-skill hint"
else
    log_fail "spurious hint" "TS002 alone routed to the refactor skill"
fi
rm -f src/Warn.ts

# A structural finding names the method, not just the fault: the directive
# routes the agent to the refactor skill instead of an inline patch.
# RATCHET001 is the structural rule the CI-backed gate actually emits, so the
# fixture is a committed baseline plus a file that regressed past it.
printf 'export const grow = 1;\n' > src/Grow.ts
python3 "$ROOT_DIR/hooks/lib/ratchet.py" init src/Grow.ts \
    --baseline .craftsman-baseline.json --reason "fixture" >/dev/null 2>&1
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm ratchet-base >/dev/null 2>&1
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'export const grow%s = %s;\n' "$i" "$i" >> src/Grow.ts; done
OUT=$(_payload "src/Grow.ts" 1 0 | bash "$HOOK" 2>/dev/null)
if printf '%s' "$OUT" | grep -q "RATCHET001" && printf '%s' "$OUT" | grep -q "refactor"; then
    log_pass "a structural finding routes the agent to the refactor skill"
else
    log_fail "no skill hint" "RATCHET001 directive lacks the refactor route: ${OUT:-<empty>}"
fi
git reset -q --hard HEAD~1 >/dev/null 2>&1
git checkout -q -- . 2>/dev/null; rm -f src/Grow.ts

# An autonomous agent commits. Scope taken from the worktree alone left a
# committed violation invisible: clean worktree, silent gate, everything the
# turn produced unscanned.
git add -A >/dev/null 2>&1
printf 'const committed: any = 1;\n' > src/Committed.ts
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm "agent work" >/dev/null 2>&1
BASE=$(git rev-parse HEAD~1)
OUT=$(CRAFTSMAN_DIFF_BASE="$BASE" bash "$HOOK" < <(_payload "" 1) 2>/dev/null)
if printf '%s' "$OUT" | grep -q "Committed.ts"; then
    log_pass "work the agent already committed is still gated"
else
    log_fail "gate bypass" "a committed violation left the worktree clean and the gate silent"
fi
git reset -q --hard HEAD~1 >/dev/null 2>&1

# stderr goes to a container log nobody reads in an autonomous loop, so a gate
# that could not run must block rather than let the turn conclude.
sed "s#\${PLUGIN_ROOT}/ci/craftsman-ci.sh#/nonexistent-gate.sh#" "$HOOK" > "$WORK/broken-hook.sh"
printf 'const x: any = 1;\n' > src/Dirty.ts
OUT=$(bash "$WORK/broken-hook.sh" < <(_payload "" 1) 2>/dev/null)
if printf '%s' "$OUT" | grep -q "could not run"; then
    log_pass "a gate that cannot run blocks instead of passing silently"
else
    log_fail "fails open" "missing gate produced no directive: ${OUT:-<empty>}"
fi
rm -f src/Dirty.ts

OUT=$(echo 'not json at all' | bash "$HOOK" 2>/dev/null)
RC=$?
if [[ -z "$OUT" && "$RC" -eq 0 ]]; then
    log_pass "malformed input yields no verdict and exit 0"
else
    log_fail "malformed input" "rc=$RC out=$OUT"
fi

# jq is absent from the nousresearch/hermes-agent image; a dependency on it
# would make the adapter a no-op there without ever saying so.
if ! sed 's/#.*//' "$HOOK" | grep -qE '(^|[^a-z_.-])jq[[:space:]]'; then
    log_pass "adapter does not depend on jq, which the Hermes image lacks"
else
    log_fail "jq dependency" "the Hermes image has no jq"
fi

echo ""
echo "=== claude-craftsman wrapper ==="

WRAPPER="$ROOT_DIR/adapters/hermes/claude-craftsman.sh"

# --bare skips auto-discovery of hooks, skills and plugins AND does not read
# CLAUDE_CODE_OAUTH_TOKEN (docs/en/headless, docs/en/authentication). It loses
# the gate and the supplied credential in one flag, and the docs say it becomes
# the default for -p in a future release, so refusing it explicitly is the
# point of the wrapper existing at all.
mkdir -p "$WORK/fakebin"
printf '#!/bin/sh\nfor a in "$@"; do echo "ARG:$a"; done\necho "KEY:${ANTHROPIC_API_KEY:-unset}"\n' > "$WORK/fakebin/claude"
chmod +x "$WORK/fakebin/claude"

RC=0
OUT=$(PATH="$WORK/fakebin:$PATH" CLAUDE_CODE_OAUTH_TOKEN=tok bash "$WRAPPER" --bare "x" 2>&1) || RC=$?
if [[ "$RC" -eq 64 ]]; then
    log_pass "the wrapper refuses --bare instead of running ungated"
else
    log_fail "bare accepted" "rc=$RC out=$OUT"
fi

# ANTHROPIC_API_KEY outranks CLAUDE_CODE_OAUTH_TOKEN in Claude Code's
# precedence order, and the Hermes image already carries one: leaving it set
# means the credential the caller supplied is silently not the one in use.
OUT=$(PATH="$WORK/fakebin:$PATH" CLAUDE_CODE_OAUTH_TOKEN=tok ANTHROPIC_API_KEY=sk-live \
      bash "$WRAPPER" "task" 2>/dev/null)
if printf '%s' "$OUT" | grep -q "KEY:unset"; then
    log_pass "an API key does not outrank the supplied OAuth token"
else
    log_fail "credential precedence" "ANTHROPIC_API_KEY survived: $OUT"
fi

if printf '%s' "$OUT" | grep -q -- "--plugin-dir"; then
    log_pass "the plugin is loaded explicitly rather than by discovery"
else
    log_fail "plugin not loaded" "$OUT"
fi

# Observed on the arguments claude actually receives, not grepped from the
# source: the wrapper's own refusal branch mentions the flag it forbids.
if ! printf '%s' "$OUT" | grep -q "^ARG:--bare$"; then
    log_pass "the wrapper never passes --bare itself"
else
    log_fail "bare passed" "the wrapper would disable the plugin it exists to load"
fi

RC=0
PATH="$WORK/fakebin:$PATH" env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
    bash "$WRAPPER" "task" >/dev/null 2>&1 || RC=$?
if [[ "$RC" -eq 78 ]]; then
    log_pass "no credential fails loudly instead of half-running"
else
    log_fail "silent credential failure" "rc=$RC"
fi

echo ""
echo "=== the adapter costs a Claude Code user nothing ==="

# Hermes support is opt-in for the people who run Hermes. Everyone else carries
# the files and loads none of them, and that has to be structural rather than
# remembered: the moment a hook or the manifest reaches into adapters/, every
# Claude Code session pays for a runtime it does not use.
LOADERS=$(grep -rl "adapters/" "$ROOT_DIR/hooks" "$ROOT_DIR/.claude-plugin" 2>/dev/null \
    | xargs grep -l "adapters/hermes" 2>/dev/null || true)
if [[ -z "$LOADERS" ]]; then
    log_pass "no hook and no plugin manifest reaches into adapters/"
else
    log_fail "adapter leaked into the load path" "$LOADERS"
fi

# The reverse direction is fine and intended: the adapter calls the shared gate
# rather than reimplementing severity resolution.
if grep -q "ci/craftsman-ci.sh" "$HOOK"; then
    log_pass "the adapter consumes the shared gate instead of duplicating it"
else
    log_fail "duplicated gate" "the adapter should call ci/craftsman-ci.sh"
fi

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
