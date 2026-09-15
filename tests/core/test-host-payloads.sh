#!/usr/bin/env bash
# =============================================================================
# Host payload contracts: the hooks read what each host actually sends.
#
# The fixtures are real captures (tests/fixtures/hosts/PROVENANCE.md). A hook
# that reads `tool_input.file_path` and exits 0 when it is missing waves every
# Codex apply_patch through (audit CR-117, C1): the same invalid class was
# refused via Write and admitted via apply_patch, before and after the write.
#
# Every negative case here is preceded by its known-good control on the same
# harness, so a red line means the hook and not the fixture.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"
source "$SCRIPT_DIR/../lib/host-fixtures.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-host-payloads-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDECODE
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-host-payloads.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)   # TMPDIR may end in a slash; the helper prints normalised paths
PREV_PWD="$PWD"
cleanup() { cd "$PREV_PWD"; rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"; }
trap cleanup EXIT

mkdir -p "$WORK/src/Domain" "$WORK/src/Infrastructure"
cd "$WORK" && git init -q .
printf '{"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json
printf '<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\Domain;\n\nfinal class Existing\n{\n}\n' > src/Domain/Existing.php
git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1

echo ""
echo "=== host payload contracts ==="

BAD_PHP='<?php
declare(strict_types=1);
namespace App\Domain;
use App\Infrastructure\Persistence\DoctrineOrderRepository;
class Order
{
}'
GOOD_PHP='<?php
declare(strict_types=1);
namespace App\Domain;
final class Order
{
}'

# A V4A patch, the grammar Codex 0.154.0 sends (see the fixture): one Add
# File per (path, content) pair, paths as the host wrote them (absolute).
_add_file_patch() {
    python3 - "$@" <<'PY'
import sys
args = sys.argv[1:]
out = ["*** Begin Patch"]
for path, content in zip(args[::2], args[1::2]):
    out.append("*** Add File: " + path)
    out.extend("+" + line for line in content.split("\n"))
out.append("*** End Patch")
print("\n".join(out))
PY
}

# The real capture, its patch swapped for the case under test.
_codex_pre() {
    host_fixture_with codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK" \
        "d['tool_input']['command'] = open('$1').read()"
}
_codex_post() {
    host_fixture_with codex 0.154.0 post-tool-use.apply_patch.multifile-move "$WORK" \
        "d['tool_input']['command'] = open('$1').read()"
}
_run() { # hook payload -> "rc|stdout+stderr"
    local out rc=0
    out=$(printf '%s' "$2" | bash "$ROOT_DIR/hooks/$1" 2>&1) || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# --- the host is read off the payload, not the environment ------------------
# A Codex hook launched from a Claude Code Bash tool inherits CLAUDECODE=1 and
# the parent's CLAUDE_CODE_SESSION_ID (fixture hook-env.project-hooks.json),
# so an environment-first detection would call every such Codex hook Claude.
source "$ROOT_DIR/hooks/lib/host.sh"
H1=$(CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent host_detect "$(host_fixture codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK")")
H2=$(CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent host_detect "$(host_fixture codex 0.154.0 pre-tool-use.bash "$WORK")")
H3=$(host_detect "$(host_fixture claude-code 2.1.272 pre-tool-use.write "$WORK")")
H4=$(env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u PLUGIN_ROOT bash -c "source '$ROOT_DIR/hooks/lib/host.sh'; host_detect '{\"tool_input\":{\"file_path\":\"/x\"}}'")
if [[ "$H1" == codex && "$H2" == codex && "$H3" == claude-code && "$H4" == unknown ]]; then
    log_pass "host_detect: Codex payloads are Codex under a Claude environment; Claude is Claude; anonymous is unknown"
else
    log_fail "host_detect" "apply_patch=$H1 bash=$H2 write=$H3 anonymous=$H4"
fi

# --- control: the Claude Code Write fixture is refused pre-write ------------
PAYLOAD=$(host_fixture_with claude-code 2.1.272 pre-tool-use.write "$WORK" \
    "d['tool_input']['file_path'] = '$WORK/src/Domain/Order.php'; d['tool_input']['content'] = open('/dev/stdin').read() if False else '''$BAD_PHP'''")
R=$(_run pre-write-check.sh "$PAYLOAD")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *LAYER001* && "${R#*|}" == *PHP002* ]]; then
    log_pass "control: Claude Code Write of an invalid Domain class is refused pre-write (LAYER001, PHP002)"
else
    log_fail "control: Claude Code Write refused" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# --- CR-118: the same class through Codex apply_patch ----------------------
_add_file_patch "$WORK/src/Domain/Order.php" "$BAD_PHP" > "$WORK/bad.patch"
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/bad.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *LAYER001* && "${R#*|}" == *PHP002* ]]; then
    log_pass "Codex apply_patch adding the same invalid class is refused pre-write (LAYER001, PHP002)"
else
    log_fail "Codex apply_patch refused pre-write" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# The refusal is the decision Codex honours: exit 2 (above) AND a deny on
# stdout. `ask` is parsed and not implemented there; a plain
# additionalContext lets the patch land.
if [[ "${R#*|}" == *'"permissionDecision": "deny"'* || "${R#*|}" == *'"permissionDecision":"deny"'* ]]; then
    log_pass "the refusal carries permissionDecision deny for a host without ask"
else
    log_fail "refusal carries deny" "out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi

# --- a valid patch passes: the gate refuses the invalid, not the format ----
_add_file_patch "$WORK/src/Domain/Order.php" "$GOOD_PHP" > "$WORK/good.patch"
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/good.patch")")
if [[ "${R%%|*}" == "0" ]]; then
    log_pass "a valid Codex apply_patch passes pre-write"
else
    log_fail "valid apply_patch passes" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# --- a mixed multi-file patch is refused as a whole -----------------------
_add_file_patch "$WORK/src/Domain/Good.php" "$GOOD_PHP" "$WORK/src/Domain/Order.php" "$BAD_PHP" > "$WORK/mixed.patch"
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/mixed.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *LAYER001* && "${R#*|}" == *Order.php* ]]; then
    log_pass "a mixed valid/invalid multi-file patch is refused and names the offending file"
else
    log_fail "mixed multi-file patch refused" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi

# --- a move is judged at its destination ----------------------------------
# Existing.php is valid where it is; moved under Infrastructure with a
# Domain-forbidden shape it must be judged by the rules of the new path. The
# real capture's Update+Move hunk is reused verbatim, only the paths bound.
mkdir -p "$WORK/src/Application"
printf '<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\Application;\n\nfinal class Service\n{\n}\n' > src/Application/Service.php
python3 - "$WORK" > "$WORK/move.patch" <<'PY'
import sys
w = sys.argv[1]
print("\n".join([
 "*** Begin Patch",
 f"*** Update File: {w}/src/Application/Service.php",
 f"*** Move to: {w}/src/Domain/Service.php",
 "@@",
 " namespace App\\Application;",
 "+",
 "+use App\\Infrastructure\\Mailer;",
 "*** End Patch"]))
PY
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/move.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *LAYER001* ]]; then
    log_pass "an Update+Move patch is judged at its destination path (LAYER001 under Domain/)"
else
    log_fail "move judged at destination" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi

# --- protected configuration through apply_patch --------------------------
R=$(_run config-protection.sh "$(host_fixture_with claude-code 2.1.272 pre-tool-use.write "$WORK" "d['tool_input']['file_path']='$WORK/phpstan.neon'")")
if [[ "${R%%|*}" == "2" ]]; then
    log_pass "control: Claude Code Write to phpstan.neon is refused"
else
    log_fail "control: phpstan.neon via Write" "rc=${R%%|*}"
fi
_add_file_patch "$WORK/phpstan.neon" "parameters:
    level: 0" > "$WORK/cfg.patch"
R=$(_run config-protection.sh "$(_codex_pre "$WORK/cfg.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *phpstan.neon* ]]; then
    log_pass "Codex apply_patch to phpstan.neon is refused"
else
    log_fail "phpstan.neon via apply_patch refused" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# A patch that relaxes the gate's own rules beside a violating file: on
# Claude Code the gate hands .craft-rules.yml to the human (ask). Codex
# documents ask as parsed and not implemented, so there the same write is
# denied: a decision the host cannot honour is no decision.
_add_file_patch "$WORK/src/Domain/.craft-rules.yml" "rules:
  LAYER001: ignore" "$WORK/src/Domain/Order.php" "$BAD_PHP" > "$WORK/relax.patch"
R=$(_run config-protection.sh "$(_codex_pre "$WORK/relax.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *'"deny"'* && "${R#*|}" != *'"ask"'* ]]; then
    log_pass "a Codex patch touching .craft-rules.yml is denied, never asked"
else
    log_fail "gate config via apply_patch denied" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
R=$(_run config-protection.sh "$(host_fixture_with claude-code 2.1.272 pre-tool-use.write "$WORK" "d['tool_input']['file_path']='$WORK/src/Domain/.craft-rules.yml'")")
if [[ "${R%%|*}" == "0" ]] && [[ "${R#*|}" == *'"ask"'* ]]; then
    log_pass "the same file through Claude Code Write still asks (the host supports it)"
else
    log_fail "Claude Code .craft-rules.yml still asks" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# --- post-write on apply_patch: every touched file is validated -----------
printf '%s\n' "$BAD_PHP" > "$WORK/src/Domain/Order.php"
printf '%s\n' "$GOOD_PHP" | sed 's/Order/Good/' > "$WORK/src/Domain/Good.php"
R=$(_run post-write-check.sh "$(_codex_post "$WORK/mixed.patch")")
if [[ "${R%%|*}" == "2" ]] && [[ "${R#*|}" == *LAYER001* ]]; then
    log_pass "post-write validates every file an apply_patch touched and refuses the invalid one"
else
    log_fail "post-write on apply_patch" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
rm -f "$WORK/src/Domain/Order.php" "$WORK/src/Domain/Good.php"

# --- the real capture itself, unmodified, is read as two files ------------
# The file the captured hunk edits, as it was when the capture was made.
printf '<?php\n\nnamespace App\\Domain;\n\nfinal class Existing\n{\n}\n' > "$WORK/Existing.php"
R=$(host_fixture codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK" \
    | python3 "$ROOT_DIR/hooks/lib/write_mirror.py" --list 2>&1)
EXPECTED=$(printf 'add\t%s/src/Domain/Order.php\nmove\t%s/Existing.php\t%s/src/Domain/Existing.php' "$WORK" "$WORK" "$WORK")
if [[ "$R" == "$EXPECTED" ]]; then
    log_pass "the captured multi-file patch lists an add and a move with both paths"
else
    log_fail "captured patch listing" "$(printf '%s' "$R" | tr '\n\t' ' >' | cut -c1-200)"
fi
M=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mirror.XXXXXX")
host_fixture codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK" \
    | python3 "$ROOT_DIR/hooks/lib/write_mirror.py" "$M" >/dev/null 2>&1
if grep -q "public function ping" "$M/src/Domain/Existing.php" 2>/dev/null \
    && grep -q "^final class Existing" "$M/src/Domain/Existing.php" \
    && [[ "$(tail -c1 "$M/src/Domain/Order.php" | od -An -c | tr -d ' ')" == '\n' ]]; then
    log_pass "the mirror holds the moved file with its hunk applied, and the added file ends with a newline"
else
    log_fail "mirror content" "$(ls -R "$M" | tr '\n' ' ' | cut -c1-120) :: $(cat "$M/src/Domain/Existing.php" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$M"
rm -f "$WORK/Existing.php"

# =============================================================================
# Independent review of the first cut (Codex, read-only): seven ways a patch
# could pass unjudged. Each one is a case here, so the fix has a witness.
# =============================================================================
echo ""
echo "--- review findings on the patch reader ---"

# F1: an added file's last line is a line. `while read` skips an unterminated
# one, so a one-line TS file holding `any` passed.
_add_file_patch "$WORK/src/one.ts" "export const x: any = 1;" > "$WORK/f1.patch"
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/f1.patch")")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *TS001* ]]; then
    log_pass "F1: a one-line added file is judged (its last line ends with a newline in the mirror)"
else
    log_fail "F1 trailing newline" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# F2: a hunk that cannot be placed is a refusal, not a judgment of its added
# lines (which, for a deletion, is nothing).
printf '// craftsman-ignore: TS001\nconst x: any = 1;\n' > "$WORK/src/sup.ts"
python3 - "$WORK" > "$WORK/f2.patch" <<'PY'
import sys; w = sys.argv[1]
print("\n".join(["*** Begin Patch", f"*** Update File: {w}/src/sup.ts", "@@", "-// this context line is not in the file", " const x: any = 1;", "*** End Patch"]))
PY
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/f2.patch")")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *"does not match the file"* && "${R#*|}" == *'"deny"'* ]]; then
    log_pass "F2: a hunk whose context is not in the file refuses the patch and says which file"
else
    log_fail "F2 unplaceable hunk" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
# ...and a deletion that does locate is judged on the whole result.
python3 - "$WORK" > "$WORK/f2b.patch" <<'PY'
import sys; w = sys.argv[1]
print("\n".join(["*** Begin Patch", f"*** Update File: {w}/src/sup.ts", "@@", "-// craftsman-ignore: TS001", " const x: any = 1;", "*** End Patch"]))
PY
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/f2b.patch")")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *TS001* ]]; then
    log_pass "F2: deleting the suppression comment exposes the violation it hid"
else
    log_fail "F2 deletion judged" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi
# Codex tolerates trailing whitespace drift in context; so does the reader.
printf 'const y = 1;   \nconst x: any = 2;\n' > "$WORK/src/drift.ts"
python3 - "$WORK" > "$WORK/f2c.patch" <<'PY'
import sys; w = sys.argv[1]
print("\n".join(["*** Begin Patch", f"*** Update File: {w}/src/drift.ts", "@@", " const y = 1;", "-const x: any = 2;", "+const x: number = 2;", "*** End Patch"]))
PY
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/f2c.patch")")
if [[ "${R%%|*}" == "0" ]]; then
    log_pass "F2: context differing only by trailing whitespace still places (as Codex's applier does)"
else
    log_fail "F2 whitespace tolerance" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi
rm -f "$WORK/src/sup.ts" "$WORK/src/drift.ts"

# F3: a helper that cannot run is a refusal on both gates. A python3 that
# exits 3 breaks the engine's own loaders first on the pre-write side (the ERR
# trap refuses) and the listing helper on the config side; either way the
# valid patch that passed above is refused now, and nothing says "allow".
mkdir -p "$WORK/nopath"; printf '#!/bin/sh\nexit 3\n' > "$WORK/nopath/python3"; chmod +x "$WORK/nopath/python3"
R=$(printf '%s' "$(_codex_pre "$WORK/good.patch")" | PATH="$WORK/nopath:$PATH" bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1); RC=$?
R2=$(printf '%s' "$(_codex_pre "$WORK/good.patch")" | PATH="$WORK/nopath:$PATH" bash "$ROOT_DIR/hooks/config-protection.sh" 2>&1); RC2=$?
if [[ "$RC" -eq 2 && "$RC2" -eq 2 && "$R" != *'"allow"'* && "$R2" != *'"allow"'* ]]; then
    log_pass "F3: a crashing helper refuses the write on pre-write and on config-protection (no verdict is not a clean verdict)"
else
    log_fail "F3 helper crash refuses" "pre rc=$RC [$(printf '%s' "$R" | tr '\n' ' ' | cut -c1-100)] cfg rc=$RC2 [$(printf '%s' "$R2" | tr '\n' ' ' | cut -c1-100)]"
fi
rm -rf "$WORK/nopath"

# F4: `@@ anchor` picks the occurrence; End of File pins the tail.
printf 'function first() {\n  return 1;\n}\nfunction second() {\n  return 1;\n}\n' > "$WORK/src/two.ts"
python3 - "$WORK" > "$WORK/f4.patch" <<'PY'
import sys; w = sys.argv[1]
print("\n".join(["*** Begin Patch", f"*** Update File: {w}/src/two.ts", "@@ function second() {", "-  return 1;", "+  const leak: any = 2; return leak;", "*** End Patch"]))
PY
M=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mirror.XXXXXX")
_codex_pre "$WORK/f4.patch" | python3 "$ROOT_DIR/hooks/lib/write_mirror.py" "$M" >/dev/null 2>&1
if [[ "$(sed -n '2p' "$M/src/two.ts")" == "  return 1;" && "$(sed -n '5p' "$M/src/two.ts")" == *"any"* ]]; then
    log_pass "F4: an @@ anchor edits the occurrence it names, not the first match"
else
    log_fail "F4 anchor" "$(cat "$M/src/two.ts" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$M"
printf 'same\nmiddle\nsame\n' > "$WORK/src/eof.ts"
python3 - "$WORK" > "$WORK/f4b.patch" <<'PY'
import sys; w = sys.argv[1]
print("\n".join(["*** Begin Patch", f"*** Update File: {w}/src/eof.ts", "@@", "-same", "+last", "*** End of File", "*** End Patch"]))
PY
M=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mirror.XXXXXX")
_codex_pre "$WORK/f4b.patch" | python3 "$ROOT_DIR/hooks/lib/write_mirror.py" "$M" >/dev/null 2>&1
if [[ "$(cat "$M/src/eof.ts" | tr '\n' '|')" == "same|middle|last|" ]]; then
    log_pass "F4: an End of File hunk edits the tail, not the first match"
else
    log_fail "F4 end of file" "$(cat "$M/src/eof.ts" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$M" "$WORK/src/two.ts" "$WORK/src/eof.ts"

# F5: two workspaces in one patch do not share a mirror path.
mkdir -p "$WORK/packages/a/src" "$WORK/packages/b/src"
printf '{"name":"a"}\n' > "$WORK/packages/a/package.json"
printf '{"name":"b"}\n' > "$WORK/packages/b/package.json"
_add_file_patch "$WORK/packages/a/src/example.ts" "export const bad: any = 1;" "$WORK/packages/b/src/example.ts" "export const good: number = 1;" > "$WORK/f5.patch"
R=$(_run pre-write-check.sh "$(_codex_pre "$WORK/f5.patch")")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *TS001* ]]; then
    log_pass "F5: a monorepo patch adding an invalid file in one package and a valid one in another is refused"
else
    log_fail "F5 monorepo mirror" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi
rm -rf "$WORK/packages"

# F6: what landed and could not be read is reported unvalidated, not passed.
R=$(_run post-write-check.sh "$(host_fixture_with codex 0.154.0 post-tool-use.apply_patch.multifile-move "$WORK" "d['tool_input']['command'] = 'not a patch'")")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *"NOT validated"* ]]; then
    log_pass "F6: a landed patch the reader cannot parse is reported as unvalidated (exit 2), not passed"
else
    log_fail "F6 unreadable after landing" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
fi

# F7: a warning-only patch still surfaces its warnings in one JSON object.
printf 'export default function f() { return 1 }\n' > "$WORK/src/Warn.ts"
_add_file_patch "$WORK/src/Warn.ts" "export default function f() { return 1 }" > "$WORK/f7.patch"
R=$(_run post-write-check.sh "$(_codex_post "$WORK/f7.patch")")
if [[ "${R%%|*}" == "0" && "${R#*|}" == *TS002* ]] && printf '%s' "${R#*|}" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); assert "TS002" in d["hookSpecificOutput"]["additionalContext"]' 2>/dev/null; then
    log_pass "F7: an advisory finding on a landed patch reaches the host as one JSON object"
else
    log_fail "F7 warning merge" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
rm -f "$WORK/src/Warn.ts"

# =============================================================================
# CR-119: a test run is what the host said about it, not a field nobody sends
# =============================================================================
echo ""
echo "--- test results decoded per host ---"
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME"   # no bridge file: state lives under CLAUDE_PLUGIN_DATA
STATE="$CLAUDE_PLUGIN_DATA/session-state.json"
_verify() { # payload -> rc ; stderr kept in VERIFY_ERR
    local rc=0
    VERIFY_ERR=$(printf '%s' "$1" | HOME="$FAKE_HOME" bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" 2>&1 >/dev/null) || rc=$?
    return $rc
}
_flag() { python3 "$ROOT_DIR/hooks/lib/session_state.py" check-flag "$STATE" verified; }
_as_test() { host_fixture_with "$1" "$2" "$3" "$WORK" "d['tool_input']['command'] = 'pytest -q'${4:-}"; }

# control: a passing run on Claude Code grants the evidence
echo '{"verified": false}' > "$STATE"
_verify "$(_as_test claude-code 2.1.272 post-tool-use.bash.python-tests-passed)"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "true" ]]; then
    log_pass "control: a Claude Code PostToolUse for a passing test command sets verified"
else
    log_fail "control: passing run sets verified" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi

# a failing run is a PostToolUseFailure: revoked, and a regression wakes the session
_verify "$(_as_test claude-code 2.1.272 post-tool-use-failure.bash.exit1-tests-failed)"; RC=$?
if [[ "$RC" -eq 2 && "$(_flag)" == "false" && "$VERIFY_ERR" == *REGRESSED* ]]; then
    log_pass "a Claude Code PostToolUseFailure (Exit code 1) after green revokes verified and reports the regression"
else
    log_fail "failure revokes" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi

# C2 as reproduced by the audit: a passing run on Codex carries no exit code.
# It must grant nothing AND revoke nothing.
echo '{"verified": true}' > "$STATE"
_verify "$(_as_test codex 0.154.0 post-tool-use.bash.python-tests-passed)"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "true" && "$VERIFY_ERR" != *REGRESSED* ]]; then
    log_pass "a Codex PostToolUse (string output, no exit code) leaves verified=true standing: no invented regression"
else
    log_fail "Codex unknown result is not a regression" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi
echo '{"verified": false}' > "$STATE"
_verify "$(_as_test codex 0.154.0 post-tool-use.bash.python-tests-passed)"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "false" && "$VERIFY_ERR" == *"no exit code"* ]]; then
    log_pass "the same Codex event grants no evidence either, and says why"
else
    log_fail "Codex unknown result grants nothing" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi
_verify "$(_as_test codex 0.154.0 post-tool-use.bash.exit3-with-output)"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "false" ]]; then
    log_pass "a Codex run that exited 3 (output only on the wire) is unknown, not a verdict"
else
    log_fail "Codex exit 3 unobservable" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi

# a background run resolves on TaskOutput, tied by task id
echo '{"verified": false}' > "$STATE"
_verify "$(_as_test claude-code 2.1.272 post-tool-use.bash.run-in-background "; d['tool_response']['backgroundTaskId'] = 'task-A'")"; RC=$?
MID=$(_flag)
_verify "$(host_fixture_with claude-code 2.1.272 post-tool-use.task-output.completed "$WORK" "d['tool_response']['task']['task_id'] = 'task-A'; d['tool_input']['task_id'] = 'task-A'")"; RC2=$?
if [[ "$RC" -eq 0 && "$MID" == "false" && "$RC2" -eq 0 && "$(_flag)" == "true" ]]; then
    log_pass "a run_in_background test run grants nothing until its TaskOutput completes with exitCode 0"
else
    log_fail "background run resolves on TaskOutput" "rc=$RC mid=$MID rc2=$RC2 verified=$(_flag) err=$VERIFY_ERR"
fi
_verify "$(host_fixture_with claude-code 2.1.272 post-tool-use.task-output.completed "$WORK" "d['tool_response']['task']['task_id'] = 'task-A'; d['tool_response']['task']['exitCode'] = 1")"; RC=$?
if [[ "$RC" -eq 2 && "$(_flag)" == "false" ]]; then
    log_pass "a TaskOutput ending the same task with exitCode 1 revokes the evidence"
else
    log_fail "TaskOutput failure revokes" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi
_verify "$(host_fixture_with claude-code 2.1.272 post-tool-use.task-output.completed "$WORK" "d['tool_response']['task']['task_id'] = 'never-seen'")"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "false" ]]; then
    log_pass "a TaskOutput for a task no test command started is ignored"
else
    log_fail "unknown TaskOutput ignored" "rc=$RC verified=$(_flag)"
fi

# an interruption is neither a pass nor a failure
echo '{"verified": true}' > "$STATE"
_verify "$(_as_test claude-code 2.1.272 post-tool-use-failure.bash.exit1-tests-failed "; d['is_interrupt'] = True")"; RC=$?
if [[ "$RC" -eq 0 && "$(_flag)" == "true" ]]; then
    log_pass "an interrupted test run (is_interrupt) changes nothing"
else
    log_fail "interrupted run" "rc=$RC verified=$(_flag) err=$VERIFY_ERR"
fi


test_summary
