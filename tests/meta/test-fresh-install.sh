#!/usr/bin/env bash
# =============================================================================
# A fresh install is what ships, not the checkout (CR-129).
#
# The archive is built from a tag on a throwaway clone (the same command the
# release workflow runs), extracted into an empty directory, and the real
# front-ends are run FROM THAT TREE with an empty data directory: the skills
# inventory a host would list, the hooks manifest, the write gate on a valid
# and an invalid file through the Claude Code payload and through the Codex
# apply_patch payload, two sessions kept apart, the doctrine export, the
# Codex roles, and `agent_hooks` reaching its consumer. A tracked file the
# archive lacks, or a runtime-only artefact the tree needs, fails here and
# nowhere else.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"
source "$SCRIPT_DIR/../lib/host-fixtures.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-fresh.XXXXXX"); WORK=$(cd "$WORK" && pwd -P)
PREV_PWD="$PWD"
trap 'cd "$PREV_PWD"; rm -rf "$WORK"' EXIT

echo ""
echo "=== fresh install from the built archive ==="

# A clone with the working tree's HEAD tagged, so the archive is what a
# release of this revision would ship.
git clone -q "$ROOT_DIR" "$WORK/clone" 2>/dev/null
( cd "$WORK/clone" && git tag v9.9.9 >/dev/null 2>&1 )
if bash "$WORK/clone/scripts/release-build.sh" v9.9.9 "$WORK/dist" >/dev/null 2>&1 && [[ -f "$WORK/dist/craftsman-9.9.9.tar.gz" ]]; then
    log_pass "the release build produces the archive from the tag"
else
    log_fail "release build" "no archive"; test_summary
fi
mkdir -p "$WORK/install" && tar -xzf "$WORK/dist/craftsman-9.9.9.tar.gz" -C "$WORK/install"
INSTALL="$WORK/install/craftsman-9.9.9"
[[ -d "$INSTALL/hooks" ]] || { log_fail "extract" "no hooks/ in the archive"; test_summary; }

# inventory
SKILLS=$(find "$INSTALL/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')
LINKS=$(find "$INSTALL/skills" -name SKILL.md -type l | wc -l | tr -d ' ')
EXPECTED=$(find "$ROOT_DIR/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
if [[ "$SKILLS" == "$EXPECTED" && "$SKILLS" -ge 22 && "$LINKS" == "0" ]]; then
    log_pass "the archive ships $SKILLS skills as regular SKILL.md files, none a symlink (the Codex loader skips those)"
else
    log_fail "skills inventory" "regular=$SKILLS expected=$EXPECTED symlinks=$LINKS"
fi
HANDLERS=$(jq '[.hooks[][] | .hooks[]] | length' "$INSTALL/hooks/hooks.json" 2>/dev/null)
[[ "$HANDLERS" == "$(jq '[.hooks[][] | .hooks[]] | length' "$ROOT_DIR/hooks/hooks.json")" ]] && log_pass "hooks.json ships with its $HANDLERS handlers" || log_fail "hooks manifest" "$HANDLERS"
[[ -f "$INSTALL/hooks/host-capabilities.json" && -f "$INSTALL/adapters/copilot/hooks.json" && -x "$INSTALL/bin/craftsman-context" ]] && log_pass "the host matrix, the Copilot adapter and craftsman-context ship" || log_fail "shipped files" "missing"

# the gates, from the installed tree, on an empty data directory
export CLAUDE_PLUGIN_ROOT="$INSTALL"
export CLAUDE_PLUGIN_DATA="$WORK/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"
export CLAUDE_PLUGIN_OPTION_stack=fullstack CLAUDE_PLUGIN_OPTION_strictness=strict
unset CLAUDE_CODE_SESSION_ID CLAUDECODE CRAFTSMAN_HEADLESS_VERIFY PYTHONPATH
# The helpers must come from the installed tree, not from the checkout that
# ran this suite (review of 84b2350, F5): the python import path is checked.
V4A_FROM=$(cd "$INSTALL/hooks/lib" && python3 -c 'import v4a_patch, write_mirror; print(v4a_patch.__file__ + " " + write_mirror.__file__)')
if [[ "$V4A_FROM" == "$INSTALL/"*" $INSTALL/"* ]]; then
    log_pass "the patch reader and the mirror import from the installed tree"
else
    log_fail "installed imports" "$V4A_FROM"
fi
PROJ="$WORK/proj"; mkdir -p "$PROJ/src/Domain"; cd "$PROJ" && git init -q .
printf '{"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json; git add -A >/dev/null; git commit -qm base >/dev/null
BAD='<?php
declare(strict_types=1);
namespace App\Domain;
use App\Infrastructure\Persistence\DoctrineOrderRepository;
class Order
{
}'
GOOD='<?php
declare(strict_types=1);
namespace App\Domain;
final class Order
{
}'
_pre() { local rc=0; printf '%s' "$1" | HOME="$WORK/home" bash "$INSTALL/hooks/pre-write-check.sh" >/dev/null 2>&1 || rc=$?; echo $rc; }
mkdir -p "$WORK/home/.claude"
printf '%s\n' "$BAD" > "$WORK/bad.php"; printf '%s\n' "$GOOD" > "$WORK/good.php"
CLAUDE_BAD=$(host_fixture_with claude-code 2.1.272 pre-tool-use.write "$PROJ" "d['tool_input']['file_path'] = '$PROJ/src/Domain/Order.php'; d['tool_input']['content'] = open('$WORK/bad.php').read()")
CLAUDE_GOOD=$(host_fixture_with claude-code 2.1.272 pre-tool-use.write "$PROJ" "d['tool_input']['file_path'] = '$PROJ/src/Domain/Order.php'; d['tool_input']['content'] = open('$WORK/good.php').read()")
python3 - "$PROJ/src/Domain/Order.php" "$BAD" > "$WORK/bad.patch" <<'PY'
import sys
print("*** Begin Patch\n*** Add File: " + sys.argv[1] + "\n" + "\n".join("+" + l for l in sys.argv[2].split("\n")) + "\n*** End Patch")
PY
python3 - "$PROJ/src/Domain/Order.php" "$GOOD" > "$WORK/good.patch" <<'PY'
import sys
print("*** Begin Patch\n*** Add File: " + sys.argv[1] + "\n" + "\n".join("+" + l for l in sys.argv[2].split("\n")) + "\n*** End Patch")
PY
CODEX_BAD=$(host_fixture_with codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$PROJ" "d['tool_input']['command'] = open('$WORK/bad.patch').read()")
CODEX_GOOD=$(host_fixture_with codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$PROJ" "d['tool_input']['command'] = open('$WORK/good.patch').read()")
if [[ "$(_pre "$CLAUDE_BAD")" == "2" && "$(_pre "$CLAUDE_GOOD")" == "0" && "$(_pre "$CODEX_BAD")" == "2" && "$(_pre "$CODEX_GOOD")" == "0" ]]; then
    log_pass "from the installed tree: the invalid class is refused and the valid one passes, through the Claude Code Write and the Codex apply_patch alike"
else
    log_fail "installed gates" "claude bad=$(_pre "$CLAUDE_BAD") good=$(_pre "$CLAUDE_GOOD") codex bad=$(_pre "$CODEX_BAD") good=$(_pre "$CODEX_GOOD")"
fi

# two sessions on the installed tree stay apart
printf '%s' "$(host_fixture_with codex 0.154.0 session-start "$PROJ" "d['session_id']='fresh-a'")" | HOME="$WORK/home" bash "$INSTALL/hooks/session-start.sh" >/dev/null 2>&1
printf '%s' "$(host_fixture_with claude-code 2.1.272 session-start "$PROJ" "d['session_id']='fresh-b'")" | HOME="$WORK/home" bash "$INSTALL/hooks/session-start.sh" >/dev/null 2>&1
printf '%s' "$(host_fixture_with codex 0.154.0 session-end "$PROJ" "d['session_id']='fresh-a'")" | HOME="$WORK/home" bash "$INSTALL/hooks/session-metrics.sh" >/dev/null 2>&1
if [[ ! -f "$CLAUDE_PLUGIN_DATA/session-start-ts-fresh-a" && -f "$CLAUDE_PLUGIN_DATA/session-start-ts-fresh-b" ]]; then
    log_pass "two sessions of two hosts on the installed tree: ending one leaves the other's files"
else
    log_fail "installed isolation" "$(ls "$CLAUDE_PLUGIN_DATA" | grep session- | tr '\n' ' ')"
fi

# the exports run from the installed tree
( cd "$PROJ" && printf '# Team\n\nWITNESS keep\n' > AGENTS.md && bash "$INSTALL/ci/craftsman-ci.sh" export --target agents-md >/dev/null 2>&1 && bash "$INSTALL/ci/craftsman-ci.sh" export --target codex-agents >/dev/null 2>&1 )
ROLES=$(ls "$PROJ/.codex/agents/"craftsman-*.toml 2>/dev/null | wc -l | tr -d ' ')
PACK_AGENTS=$(ls "$INSTALL"/packs/*/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
CORE_AGENTS=$(find "$INSTALL/agents" -maxdepth 1 -name "*.md" -type f | wc -l | tr -d ' ')
# F8 (challenge review): a fresh tree has no pack symlinks under agents/, and
# the export produced the core six only; the packs' agents come from the packs.
if grep -q "WITNESS keep" "$PROJ/AGENTS.md" && grep -q "craftsman:doctrine:begin" "$PROJ/AGENTS.md" && [[ "$ROLES" == "$((CORE_AGENTS + PACK_AGENTS))" && "$ROLES" -ge 12 ]]; then
    log_pass "the doctrine block and $ROLES Codex roles (core $CORE_AGENTS + packs $PACK_AGENTS) export from the installed tree with no prior sync, the team's AGENTS.md text kept"
else
    log_fail "installed exports" "roles=$ROLES core=$CORE_AGENTS packs=$PACK_AGENTS $(head -3 "$PROJ/AGENTS.md" | tr '\n' '|')"
fi
# F7 (challenge review): the role's bootstrap named ${CLAUDE_PLUGIN_ROOT}, a
# variable a Codex role's shell does not have; exit 127 on the first command.
BOOT=$(grep -m1 -oE 'bash "[^"]*dispatch-context.sh"' "$PROJ/.codex/agents/craftsman-architect.toml")
RC=0; ( cd "$PROJ" && env -u CLAUDE_PLUGIN_ROOT bash -c "$BOOT" >/dev/null 2>&1 ) || RC=$?
if [[ "$BOOT" == *"$INSTALL/hooks/lib/dispatch-context.sh"* && "$RC" -ne 127 ]]; then
    log_pass "the exported role's bootstrap names the installed tree and runs from another project (rc=$RC, not 127)"
else
    log_fail "role bootstrap" "boot=[$BOOT] rc=$RC"
fi

# agent_hooks reaches its consumer from the installed tree (fake claude records the call)
mkdir -p "$WORK/bin"; printf '#!/bin/sh\necho invoked >> "%s/calls"\necho CLEAN\n' "$WORK" > "$WORK/bin/claude"; chmod +x "$WORK/bin/claude"
printf '%s\n' "$GOOD" > "$PROJ/src/Domain/Order.php"
_ddd() { rm -f "$WORK/calls"; ( cd "$PROJ" && printf '{"session_id":"fresh-b","prompt_id":"p","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$PROJ/src/Domain/Order.php" | env -u CLAUDE_EFFORT PATH="$WORK/bin:$PATH" CRAFTSMAN_GLOBAL_CONFIG_DIR="$WORK/global" "$@" bash "$INSTALL/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 ); [[ -f "$WORK/calls" ]] && echo called || echo not-called; }
mkdir -p "$WORK/global"
ON=$(_ddd CLAUDE_PLUGIN_OPTION_AGENT_HOOKS=true); OFF=$(_ddd CLAUDE_PLUGIN_OPTION_AGENT_HOOKS=false)
printf 'hooks:\n  agent_hooks: false\n' > "$WORK/global/.craft-config.yml"; GLOBAL_OFF=$(_ddd)
if [[ "$ON" == "called" && "$OFF" == "not-called" && "$GLOBAL_OFF" == "not-called" ]]; then
    log_pass "agent_hooks reaches its consumer from the installed tree: option on calls, option off and global off do not"
else
    log_fail "installed agent_hooks" "on=$ON off=$OFF global-off=$GLOBAL_OFF"
fi

test_summary
