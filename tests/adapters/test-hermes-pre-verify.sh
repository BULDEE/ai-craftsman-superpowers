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
              "attempt": 0, "final_response": "done", "model": "m", "platform": "cli"},
}))' "$WORK" "$1" "$2"
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

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
