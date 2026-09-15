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
R=$(host_fixture codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK" \
    | python3 "$ROOT_DIR/hooks/lib/write_mirror.py" --list 2>&1)
EXPECTED=$(printf 'add\t%s/src/Domain/Order.php\nmove\t%s/Existing.php\t%s/src/Domain/Existing.php' "$WORK" "$WORK" "$WORK")
if [[ "$R" == "$EXPECTED" ]]; then
    log_pass "the captured multi-file patch lists an add and a move with both paths"
else
    log_fail "captured patch listing" "$(printf '%s' "$R" | tr '\n\t' ' >' | cut -c1-200)"
fi

test_summary
