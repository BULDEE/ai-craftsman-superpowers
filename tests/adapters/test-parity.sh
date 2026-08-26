#!/usr/bin/env bash
# =============================================================================
# Host adapter parity (ADR-0029).
#
# One rules engine, one verdict: for the same file under the same rule set,
# every front-end resolves the same rule ids to the same blocking decision.
# The fixtures run through the three front-ends that exist today: the Claude
# Code hooks, ci/craftsman-ci.sh, and the Hermes pre_verify adapter. A new
# directory under adapters/ that this suite does not cover fails the last
# assertion: an adapter without parity coverage is a fork, not an adapter.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-parity-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
mkdir -p "$CLAUDE_PLUGIN_DATA"

HERMES_HOOK="$ROOT_DIR/adapters/hermes/pre-verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-parity.XXXXXX")
PREV_PWD="$PWD"

echo ""
echo "=== host adapter parity (ADR-0029) ==="

mkdir -p "$WORK/src/Domain/User" "$WORK/relaxed"
cd "$WORK" && git init -q . 2>/dev/null
printf 'rules:\n  TS001: ignore\n' > relaxed/.craft-rules.yml
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1

_hermes() {
    python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "pre_verify", "session_id": "s1",
                  "cwd": sys.argv[1],
                  "extra": {"changed_paths": [], "coding": True, "attempt": 0}}))' "$WORK" \
        | bash "$HERMES_HOOK" 2>/dev/null
}

_ci_rules_for() {
    bash "$ROOT_DIR/ci/craftsman-ci.sh" --format json "$1" 2>/dev/null | python3 -c '
import json, sys
report = json.load(sys.stdin)
for v in report.get("violations") or []:
    print(v.get("rule"), v.get("severity"))'
}

_clean() { git checkout -q -- . 2>/dev/null; git clean -qfd 2>/dev/null; mkdir -p src relaxed; }

# --- LAYER001, critical, enforced pre-write -------------------------------
PHP_FILE="$WORK/src/Domain/User/User.php"
PHP_CONTENT='<?php
declare(strict_types=1);
namespace App\Domain\User;
use App\Infrastructure\Persistence\DoctrineUserRepository;
final class User {}'

RC=0
HOOK_OUT=$(python3 -c '
import json, sys
print(json.dumps({"tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' \
    "$PHP_FILE" "$PHP_CONTENT" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1) || RC=$?
printf '%s' "$PHP_CONTENT" > "$PHP_FILE"
CI_OUT=$(_ci_rules_for "src/Domain/User/User.php")
HERMES_OUT=$(_hermes)
if [[ "$RC" -eq 2 ]] && printf '%s' "$HOOK_OUT" | grep -q "LAYER001" \
    && printf '%s' "$CI_OUT" | grep -q "^LAYER001 critical" \
    && printf '%s' "$HERMES_OUT" | grep -q '"decision"' \
    && printf '%s' "$HERMES_OUT" | grep -q "LAYER001"; then
    log_pass "LAYER001 blocks identically in hooks, CI and Hermes"
else
    log_fail "LAYER001 parity" "hook rc=$RC ci=[$CI_OUT] hermes=[$HERMES_OUT]"
fi
_clean

# --- TS001, critical, enforced post-write ---------------------------------
printf 'const bad: any = 1;\n' > "$WORK/src/Bad.ts"
RC=0
HOOK_OUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$WORK/src/Bad.ts" \
    | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || RC=$?
CI_OUT=$(_ci_rules_for "src/Bad.ts")
HERMES_OUT=$(_hermes)
if [[ "$RC" -eq 2 ]] && printf '%s' "$HOOK_OUT" | grep -q "TS001" \
    && printf '%s' "$CI_OUT" | grep -q "^TS001 critical" \
    && printf '%s' "$HERMES_OUT" | grep -q '"decision"' \
    && printf '%s' "$HERMES_OUT" | grep -q "TS001"; then
    log_pass "TS001 blocks identically in hooks, CI and Hermes"
else
    log_fail "TS001 parity" "hook rc=$RC ci=[$CI_OUT] hermes=[$HERMES_OUT]"
fi
_clean

# --- TS002, advisory: reported everywhere, blocks nowhere -----------------
printf 'export default function f() { return 1 }\n' > "$WORK/src/Warn.ts"
RC=0
HOOK_OUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$WORK/src/Warn.ts" \
    | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || RC=$?
CI_OUT=$(_ci_rules_for "src/Warn.ts")
HERMES_OUT=$(_hermes)
if [[ "$RC" -eq 0 ]] \
    && printf '%s' "$CI_OUT" | grep -q "^TS002" \
    && ! printf '%s' "$CI_OUT" | grep -q "^TS002 critical" \
    && [[ -n "$HERMES_OUT" ]] \
    && ! printf '%s' "$HERMES_OUT" | grep -q '"decision"' \
    && printf '%s' "$HERMES_OUT" | grep -q "TS002"; then
    log_pass "TS002 stays advisory in hooks, CI and Hermes"
else
    log_fail "TS002 parity" "hook rc=$RC ci=[$CI_OUT] hermes=[$HERMES_OUT]"
fi
_clean

# --- directory relaxation applies in every front-end ----------------------
printf 'const relaxed: any = 1;\n' > "$WORK/relaxed/Bad.ts"
RC=0
HOOK_OUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$WORK/relaxed/Bad.ts" \
    | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || RC=$?
CI_OUT=$(_ci_rules_for "relaxed/Bad.ts")
HERMES_OUT=$(_hermes)
if [[ "$RC" -eq 0 ]] \
    && ! printf '%s' "$CI_OUT" | grep -q "^TS001" \
    && [[ -z "$HERMES_OUT" ]]; then
    log_pass "a directory .craft-rules.yml relaxation holds in hooks, CI and Hermes"
else
    log_fail "relaxation parity" "hook rc=$RC ci=[$CI_OUT] hermes=[$HERMES_OUT]"
fi
_clean

# --- every adapter directory is covered here ------------------------------
UNCOVERED=""
for dir in "$ROOT_DIR"/adapters/*/; do
    case "$(basename "$dir")" in
        hermes) ;;
        *) UNCOVERED="${UNCOVERED}$(basename "$dir") " ;;
    esac
done
if [[ -z "$UNCOVERED" ]]; then
    log_pass "every adapters/ directory has parity coverage in this suite"
else
    log_fail "uncovered adapter" "add parity cases for: $UNCOVERED"
fi

cd "$PREV_PWD"
rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"

test_summary
