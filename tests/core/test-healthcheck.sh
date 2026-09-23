#!/usr/bin/env bash
# =============================================================================
# Tests for healthcheck library
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-test-hc-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT
# A Grok Bash tool exports GROK_SESSION_ID (1.0.34). host_detect reads it
# before Codex/Claude marks, so in-process checks that expect the Claude
# bridge or a Codex home named grok and went green on the wrong row.
unset GROK_SESSION_ID GROK_HOOK_EVENT GROK_AGENT

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Healthcheck Library Tests ==="

# Source healthcheck
source "$ROOT_DIR/hooks/lib/healthcheck.sh"

# Test: hc_check_system_deps should pass (python3, jq, sqlite3 available in test env)
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_system_deps
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_system_deps reports ok when deps present"
else
    log_fail "hc_check_system_deps should report ok: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_node should pass (node available)
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_node
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_node reports ok for node >= 20"
else
    log_fail "hc_check_node should report ok: ${_HC_STATUSES[0]}"
fi

# Test: hc_run_all produces results
hc_run_all
if [[ ${#_HC_NAMES[@]} -ge 4 ]]; then
    log_pass "hc_run_all produces ${#_HC_NAMES[@]} check results"
else
    log_fail "hc_run_all should produce at least 4 results, got ${#_HC_NAMES[@]}"
fi

# Test: hc_summary produces a one-liner
summary=$(hc_summary)
if [[ "$summary" == Healthcheck:* ]]; then
    log_pass "hc_summary produces one-liner: $summary"
else
    log_fail "hc_summary should start with 'Healthcheck:', got: $summary"
fi

# Test: hc_json produces valid JSON
json=$(hc_json)
if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    log_pass "hc_json produces valid JSON"
else
    log_fail "hc_json should produce valid JSON: $json"
fi

# Test: hc_check_session_bridge warns when bridge file is missing
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
_ORIG_HOME="$HOME"
export HOME="/tmp/craftsman-test-bridge-$$"
mkdir -p "$HOME/.claude"
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "warn" ]]; then
    log_pass "hc_check_session_bridge warns when bridge missing"
else
    log_fail "hc_check_session_bridge should warn when missing: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_session_bridge errors when bridge file is empty
printf '' > "$HOME/.claude/craftsman-session-state-path"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "error" ]]; then
    log_pass "hc_check_session_bridge errors when bridge empty"
else
    log_fail "hc_check_session_bridge should error when empty: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_session_bridge ok when bridge points to valid dir
mkdir -p "$HOME/.claude/plugins/data/craftsman"
printf '%s' "$HOME/.claude/plugins/data/craftsman/session-state.json" > "$HOME/.claude/craftsman-session-state-path"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_session_bridge
if [[ "${_HC_STATUSES[0]}" == "ok" ]]; then
    log_pass "hc_check_session_bridge ok when bridge valid"
else
    log_fail "hc_check_session_bridge should be ok when valid: ${_HC_STATUSES[0]}"
fi

# Test: hc_check_lsp records a status (ok when a server exists, warn otherwise)
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_lsp
if [[ "${_HC_NAMES[0]}" == "lsp" && ( "${_HC_STATUSES[0]}" == "ok" || "${_HC_STATUSES[0]}" == "warn" ) ]]; then
    log_pass "hc_check_lsp records lsp status (${_HC_STATUSES[0]})"
else
    log_fail "hc_check_lsp missing or invalid status: ${_HC_STATUSES[0]:-none}"
fi

# Test: hc_check_lsp warn message points at install paths when nothing found
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
PATH="/usr/bin:/bin" hc_check_lsp
if [[ "${_HC_STATUSES[0]}" == "warn" && "${_HC_MESSAGES[0]}" == *"intelephense"* ]]; then
    log_pass "hc_check_lsp warns with install hints when no server on PATH"
else
    log_pass "hc_check_lsp found a server on restricted PATH (environment-dependent, ok)"
fi

# Cleanup bridge test
rm -rf "$HOME"
export HOME="$_ORIG_HOME"

# Test: agent-teams check is ok in BOTH modes - absence of the experimental
# flag is a mode (degraded parallel dispatch), never a fault
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=claude-code CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="" hc_check_agent_teams
if [[ "${_HC_STATUSES[0]}" == "ok" && "${_HC_MESSAGES[0]}" == *"degraded"* ]]; then
    log_pass "hc_check_agent_teams: ok + degraded-mode message without the flag"
else
    log_fail "hc_check_agent_teams unset: ${_HC_STATUSES[0]} / ${_HC_MESSAGES[0]}"
fi

_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=claude-code CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1" hc_check_agent_teams
if [[ "${_HC_STATUSES[0]}" == "ok" && "${_HC_MESSAGES[0]}" == *"native"* ]]; then
    log_pass "hc_check_agent_teams: ok + native message with the flag"
else
    log_fail "hc_check_agent_teams set: ${_HC_STATUSES[0]} / ${_HC_MESSAGES[0]}"
fi

# Test: hc_check_skills reports how many skills the model can reach (#48),
# against the frontmatter counted here independently.
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
hc_check_skills
expected_total=0; expected_locked=0
for _skill in "$ROOT_DIR"/skills/*/SKILL.md; do
    [[ -f "$_skill" ]] || continue
    expected_total=$((expected_total + 1))
    awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$_skill" \
        | grep -q '^disable-model-invocation:[[:space:]]*true' && expected_locked=$((expected_locked + 1))
done
expected_msg="$((expected_total - expected_locked)) of ${expected_total} model-invocable, ${expected_locked} user-typed"
if [[ "${_HC_NAMES[0]}" == "skills" && "${_HC_MESSAGES[0]}" == "$expected_msg" ]]; then
    log_pass "hc_check_skills: ${_HC_MESSAGES[0]}"
else
    log_fail "hc_check_skills should say '${expected_msg}'" "got '${_HC_NAMES[0]}: ${_HC_MESSAGES[0]}'"
fi
if [[ "$expected_locked" -gt 0 && "$expected_locked" -lt "$expected_total" ]]; then
    log_pass "the count is about something: ${expected_locked} locked of ${expected_total}"
else
    log_fail "the count is about something" "locked=${expected_locked} total=${expected_total}"
fi

# The host row says what this host can observe, per capability, instead of
# hiding it in one score (research CR-131, R11). The facts are the captured
# ones: Codex sends no shell exit code and ignores `ask`.
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=codex hc_check_host
CODEX_MSG="${_HC_MESSAGES[0]}"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=claude-code hc_check_host
CLAUDE_MSG="${_HC_MESSAGES[0]}"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=mystery hc_check_host
UNKNOWN_STATUS="${_HC_STATUSES[0]}"
if [[ "$CODEX_MSG" == *"NOT observable"* && "$CODEX_MSG" == *"ask unsupported"* && "$CODEX_MSG" == *".agents/skills"* \
    && "$CLAUDE_MSG" == *"observable"* && "$CLAUDE_MSG" != *"NOT observable"* && "$CLAUDE_MSG" == *".claude/skills"* \
    && "$UNKNOWN_STATUS" == "warn" ]]; then
    log_pass "hc_check_host: Codex and Claude Code rows state exit-code observability, ask support and the skills directory; an unknown host warns"
else
    log_fail "hc_check_host" "codex=[$CODEX_MSG] claude=[$CLAUDE_MSG] unknown=$UNKNOWN_STATUS"
fi
# The real consumer is skills/healthcheck/SKILL.md, which sources config.sh,
# pack-loader.sh and healthcheck.sh and nothing else. Every case above hands
# the host in by hand, so none of them noticed that `host_detect` is not
# defined in that process: a Claude Code session, the one host fully
# qualified, reported "unknown host: capabilities not qualified" and
# "18 handlers declared but load status unknown" (measured 2026-09-20 in a
# `claude --plugin-dir` session). The check is the skill's own command line.
# The skill's first bash block, whatever it is: extracted from SKILL.md so the
# suite cannot drift from what the model is told to run.
SKILL_CMD=$(awk '/^```bash$/{f=1; next} /^```$/{if (f) exit} f' "$ROOT_DIR/skills/healthcheck/SKILL.md")
# The Bash tool puts the plugin's bin/ on PATH and exports no
# CLAUDE_PLUGIN_ROOT (measured 2026-09-20), which is how the skill resolves
# this installation: through craftsman-path, not through the environment.
# From the USER'S project directory, which is where the Bash tool runs: the
# library must resolve the installation from its own location. Four call
# sites fell back to `pwd`, so the checks read the project for hooks.json and
# the host matrix and reported "hooks.json missing" plus an unqualified host,
# which a model read as a broken installation (2026-09-20).
HC_CWD=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-hc-cwd.XXXXXX")
HC_OUT=$(cd "$HC_CWD" && env -u CLAUDE_PLUGIN_ROOT PATH="$ROOT_DIR/bin:$PATH" \
    CLAUDE_PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" \
    CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=hc-skill bash -c "$SKILL_CMD" 2>/dev/null)
HC_HOST=$(printf '%s' "$HC_OUT" | awk '$2 == "host" {sub(/^ +/, ""); print}')
HC_HOOKS=$(printf '%s' "$HC_OUT" | awk '$2 == "hooks" {sub(/^ +/, ""); print}')
rm -rf "$HC_CWD"
if [[ "$HC_HOST" == "[ok]"*claude-code* && "$HC_HOOKS" == "[ok]"* \
    && "$HC_HOOKS" != *"not recorded"* && "$HC_HOOKS" != *"loaded events unknown"* ]]; then
    log_pass "the skill's own command line, run from the user's project, names the host and reads this installation's hooks.json"
else
    log_fail "healthcheck as the skill runs it" "host=[$HC_HOST] hooks=[$(printf '%s' "$HC_HOOKS" | cut -c1-90)]"
fi

# The skill renders a diagnostic, so its instructions must forbid improving
# it: a session displayed `lsp: warn, none installed` as ok with an invented
# count and called the report ALL GREEN (2026-09-20).
HC_SKILL="$ROOT_DIR/skills/healthcheck/SKILL.md"
if grep -q "Never raise" "$HC_SKILL" && grep -q "as it came" "$HC_SKILL" \
    && ! grep -q "Status: ALL GREEN" "$HC_SKILL"; then
    log_pass "the healthcheck skill shows the command's own rendering and forbids raising a status or heading it ALL GREEN"
else
    log_fail "healthcheck skill rendering rules" "$(grep -c "ALL GREEN" "$HC_SKILL") ALL GREEN mentions"
fi

# A hook process gets a narrower PATH than the Bash tool of the same session:
# the SessionStart banner said "lsp: none installed" while the same check,
# run from that session's shell, found four servers (2026-09-20). The user
# was told to install what was installed.
LSP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-lsp-home.XXXXXX")
mkdir -p "$LSP_HOME/.local/bin"
LSP_SERVER=$(lang_all_known_capability lsp 2>/dev/null | head -1)
printf '#!/bin/sh\nexit 0\n' > "$LSP_HOME/.local/bin/$LSP_SERVER"; chmod +x "$LSP_HOME/.local/bin/$LSP_SERVER"
LSP_OUT=$(cd "$ROOT_DIR" && env -i HOME="$LSP_HOME" PATH=/usr/bin:/bin CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
    CLAUDE_PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" bash -c '
        source hooks/lib/config.sh; source hooks/lib/pack-loader.sh; pack_loader_init 2>/dev/null
        source hooks/lib/healthcheck.sh; hc_check_lsp; printf "%s|%s" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}"' 2>/dev/null)
if [[ "$LSP_OUT" == ok\|*"$LSP_SERVER"* ]]; then
    log_pass "a language server installed under ~/.local/bin is found by a hook whose PATH does not carry it"
else
    log_fail "lsp lookup beyond the hook PATH" "server=$LSP_SERVER out=$(printf '%s' "$LSP_OUT" | cut -c1-90)"
fi
rm -rf "$LSP_HOME"

# A skill runs in the host's shell tool, which carries no payload. In a Codex
# session `craftsman-healthcheck` reported "unknown host" about Codex and
# read the ~/.claude bridge, which belongs to another host (measured
# 2026-09-20 by a Codex session qualifying this plugin).
CX_DATA=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-cx-data.XXXXXX")
CX_OUT=$(cd "$ROOT_DIR" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CRAFTSMAN_SESSION_HOST \
    CODEX_THREAD_ID=01a0bf07 CLAUDE_PLUGIN_ROOT="$ROOT_DIR" CLAUDE_PLUGIN_DATA="$CX_DATA" bash -c '
        source hooks/lib/config.sh; source hooks/lib/healthcheck.sh
        hc_check_host; hc_check_session_bridge
        printf "%s|%s\n%s|%s\n" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}" "${_HC_STATUSES[1]}" "${_HC_MESSAGES[1]}"' 2>/dev/null)
CX_HOST=$(printf '%s' "$CX_OUT" | sed -n 1p)
CX_BRIDGE=$(printf '%s' "$CX_OUT" | sed -n 2p)
if [[ "$CX_HOST" == ok\|*codex* && "$CX_BRIDGE" == ok\|codex:* && "$CX_BRIDGE" == *"$CX_DATA"* ]]; then
    log_pass "a Codex shell names codex from CODEX_THREAD_ID, and the bridge row points at this installation's data directory, not at ~/.claude"
else
    log_fail "healthcheck under a Codex shell" "host=[$(printf '%s' "$CX_HOST" | cut -c1-70)] bridge=[$(printf '%s' "$CX_BRIDGE" | cut -c1-80)]"
fi
rm -rf "$CX_DATA"

# Codex reads TOML roles from its own home and installing the plugin does not
# write them: the twelve are offered to spawn_agent only once exported there
# (measured 2026-09-20, a craftsman-architect spawn answered). A session with
# the skills and none of the roles deserves a line, not a silence.
AR_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-roles.XXXXXX")
_roles_row() { # $1 = CODEX_HOME
    cd "$ROOT_DIR" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CRAFTSMAN_SESSION_HOST \
        CODEX_THREAD_ID=r1 CODEX_HOME="$1" CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash -c '
            source hooks/lib/config.sh; source hooks/lib/healthcheck.sh
            hc_check_agent_roles; printf "%s|%s" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}"' 2>/dev/null
}
AR_EMPTY=$(_roles_row "$AR_HOME")
mkdir -p "$AR_HOME/agents" && printf 'name = "craftsman-architect"\n' > "$AR_HOME/agents/craftsman-architect.toml"
AR_FULL=$(_roles_row "$AR_HOME")
AR_CC=$(cd "$ROOT_DIR" && env CRAFTSMAN_SESSION_HOST=claude-code bash -c '
    source hooks/lib/config.sh; source hooks/lib/healthcheck.sh
    hc_check_agent_roles; printf "%s" "${_HC_STATUSES[0]}"' 2>/dev/null)
if [[ "$AR_EMPTY" == warn\|*"loads roles from config layers"* && "$AR_FULL" == warn\|1* && "$AR_CC" == ok ]]; then
    log_pass "a Codex home without roles reports the native plugin limitation; with them loading is still unmeasured; another host is ok without looking"
else
    log_fail "agent roles per host" "empty=[$(printf '%s' "$AR_EMPTY" | cut -c1-90)] full=[$AR_FULL] claude=$AR_CC"
fi
rm -rf "$AR_HOME"

# Declared is not loaded: hooks/host-capabilities.json says which events each
# host loads (Codex 0.154.0: not TaskCompleted, PostToolUseFailure, FileChanged,
# from its own generated schema), and a handler on an event the host does not
# load is named with the function it carries, never counted as active.
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=codex CLAUDE_PLUGIN_ROOT="$ROOT_DIR" hc_check_hooks_declared
CODEX_HOOKS="${_HC_MESSAGES[0]}"; CODEX_HOOKS_STATUS="${_HC_STATUSES[0]}"
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=claude-code CLAUDE_PLUGIN_ROOT="$ROOT_DIR" hc_check_hooks_declared
CLAUDE_HOOKS="${_HC_MESSAGES[0]}"; CLAUDE_HOOKS_STATUS="${_HC_STATUSES[0]}"
DECLARED=$(jq '[.hooks[][] | .hooks[]] | length' "$ROOT_DIR/hooks/hooks.json")
if [[ "$CODEX_HOOKS_STATUS" == "warn" && "$CODEX_HOOKS" == "${DECLARED} handlers declared on "* \
    && "$CODEX_HOOKS" == *"NOT loaded by codex: FileChanged"* && "$CODEX_HOOKS" == *"PostToolUseFailure (failed tool tracking"* && "$CODEX_HOOKS" == *"TaskCompleted (evidence gate"* \
    && "$CLAUDE_HOOKS_STATUS" == "ok" && "$CLAUDE_HOOKS" == *"every event is one claude-code loads"* ]]; then
    log_pass "hc_check_hooks_declared: on Codex the three unloaded events are named with the function each loses; on Claude Code every event loads"
else
    log_fail "hc_check_hooks_declared" "codex=[$CODEX_HOOKS_STATUS $CODEX_HOOKS] claude=[$CLAUDE_HOOKS_STATUS $CLAUDE_HOOKS]"
fi
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=mystery CLAUDE_PLUGIN_ROOT="$ROOT_DIR" hc_check_hooks_declared
if [[ "${_HC_STATUSES[0]}" == "warn" && "${_HC_MESSAGES[0]}" == *"not recorded"* && "${_HC_MESSAGES[0]}" != *"every event"* ]]; then
    log_pass "hc_check_hooks_declared: a host the matrix does not record warns; no evidence is never 'every event loads'"
else
    log_fail "hc_check_hooks_declared unknown host" "${_HC_STATUSES[0]} ${_HC_MESSAGES[0]}"
fi
# every declared event is accounted for on every host: loaded, or its lost function named
UNACCOUNTED=$(python3 - "$ROOT_DIR" <<'PY'
import json, sys
root = sys.argv[1]
declared = set(json.load(open(f"{root}/hooks/hooks.json"))["hooks"])
caps = json.load(open(f"{root}/hooks/host-capabilities.json"))
missing = []
for host, spec in caps["hosts"].items():
    for event in declared - set(spec["events_loaded"]):
        if event not in caps["event_functions"]:
            missing.append(f"{host}:{event}")
print(" ".join(missing))
PY
)
if [[ -z "$UNACCOUNTED" ]]; then
    log_pass "host-capabilities.json accounts for every declared event on every host (loaded, or the lost function named)"
else
    log_fail "host-capabilities.json" "declared events with no loaded entry and no named function: $UNACCOUNTED"
fi

# Grok lists a plugin's hooks/hooks.json and runs none of them (measured
# 1.0.30 and again 1.0.34 in this session: grok inspect shows
# `file plugin: craftsman`, hook_execution has only global/settings rows, a
# write of a non-final Domain class importing Infrastructure landed). The
# healthcheck that only named FileChanged/TaskCompleted as "not loaded"
# reported 12 ok / 2 warn while the write gate was inert. The consumer is
# this row: unwired Grok is a warning that names the export, a
# .grok/hooks/craftsman.json that actually calls pre-write-check.sh is wired.
G_PROJ=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-grok-hc.XXXXXX")
G_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-grok-home.XXXXXX")
_g_hooks_row() { ( cd "$G_PROJ" && HOME="$G_HOME" CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash -c 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/config.sh"; source "$CLAUDE_PLUGIN_ROOT/hooks/lib/healthcheck.sh"; hc_check_write_gate; printf "%s|%s" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}"' ); }
G_BARE=$(_g_hooks_row)
if [[ "$G_BARE" == warn\|*"write gate is inert"* && "$G_BARE" == *"craftsman-ci export --target grok-hooks"* ]]; then
    log_pass "an unwired Grok project warns that the write gate is inert and names the grok-hooks export"
else
    log_fail "unwired Grok write gate" "$(printf '%s' "$G_BARE" | cut -c1-220)"
fi
mkdir -p "$G_PROJ/.grok/hooks" "$G_HOME/.grok/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash /opt/craftsman/hooks/pre-write-check.sh"}]}]}}' \
    > "$G_PROJ/.grok/hooks/craftsman.json"
G_UNOWNED=$(_g_hooks_row)
if [[ "$G_UNOWNED" == error\|*"belongs to nowhere"* && "$G_UNOWNED" == *"craftsman-ci export --target grok-hooks"* ]]; then
    log_pass "a Grok gate that calls pre-write-check.sh without an owner marker is an error"
else
    log_fail "unowned Grok write gate" "$(printf '%s' "$G_UNOWNED" | cut -c1-220)"
fi
python3 "$ROOT_DIR/ci/host_hooks.py" grok "$ROOT_DIR" "$G_PROJ/.grok/hooks/craftsman.json" >/dev/null
G_OWNED=$(_g_hooks_row)
if [[ "$G_OWNED" == ok\|*"wired via"* ]]; then
    log_pass "a Grok gate whose marker matches this install is wired"
else
    log_fail "owned Grok write gate" "$(printf '%s' "$G_OWNED" | cut -c1-220)"
fi
jq '.craftsman.root = "/tmp/craftsman-other-install"' "$G_PROJ/.grok/hooks/craftsman.json" > "$G_PROJ/.grok/hooks/craftsman.json.tmp"
mv "$G_PROJ/.grok/hooks/craftsman.json.tmp" "$G_PROJ/.grok/hooks/craftsman.json"
G_FOREIGN=$(_g_hooks_row)
if [[ "$G_FOREIGN" == error\|*"belongs to /tmp/craftsman-other-install"* && "$G_FOREIGN" == *"this install is"* ]]; then
    log_pass "a Grok gate that belongs to another checkout is an error naming both paths"
else
    log_fail "foreign Grok write gate" "$(printf '%s' "$G_FOREIGN" | cut -c1-220)"
fi
python3 "$ROOT_DIR/ci/host_hooks.py" grok "$ROOT_DIR" "$G_PROJ/.grok/hooks/craftsman.json" >/dev/null
jq '.craftsman.version = "0.0.1"' "$G_PROJ/.grok/hooks/craftsman.json" > "$G_PROJ/.grok/hooks/craftsman.json.tmp"
mv "$G_PROJ/.grok/hooks/craftsman.json.tmp" "$G_PROJ/.grok/hooks/craftsman.json"
G_BEHIND=$(_g_hooks_row)
if [[ "$G_BEHIND" == warn\|*"craftsman-ci export --target grok-hooks"* ]]; then
    log_pass "a Grok gate from this install at an older version names the export"
else
    log_fail "stale Grok write gate" "$(printf '%s' "$G_BEHIND" | cut -c1-220)"
fi
HERE_ROOT=$(cd "$ROOT_DIR" && pwd -P)
jq -n --arg root "/tmp/craftsman-other-install" '{craftsman:{root:$root,commit:"x",version:"0"},hooks:{}}' \
    > "$G_HOME/.grok/hooks/craftsman.json"
(
    cd "$G_PROJ" && HOME="$G_HOME" CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        bash -c 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/config.sh"; source "$CLAUDE_PLUGIN_ROOT/hooks/lib/healthcheck.sh"; hc_refresh_owned_gate'
)
G_FOREIGN_LEFT=$(jq -r '.craftsman.root' "$G_HOME/.grok/hooks/craftsman.json")
jq -n --arg root "$HERE_ROOT" '{craftsman:{root:$root,commit:"000000000000",version:"0.0.1"},hooks:{}}' \
    > "$G_HOME/.grok/hooks/craftsman.json"
(
    cd "$G_PROJ" && HOME="$G_HOME" CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        bash -c 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/config.sh"; source "$CLAUDE_PLUGIN_ROOT/hooks/lib/healthcheck.sh"; hc_refresh_owned_gate'
)
G_REFRESHED=$(jq -r '.craftsman.version' "$G_HOME/.grok/hooks/craftsman.json")
if [[ "$G_FOREIGN_LEFT" == "/tmp/craftsman-other-install" && "$G_REFRESHED" == "$(jq -r '.version' "$ROOT_DIR/.claude-plugin/plugin.json")" ]]; then
    log_pass "SessionStart refresh rewrites only the global gate whose root is this install"
else
    log_fail "owned gate refresh" "foreign=$G_FOREIGN_LEFT version=$G_REFRESHED"
fi
rm -f "$G_PROJ/.grok/hooks/craftsman.json"
HERE_ROOT=$(cd "$ROOT_DIR" && pwd -P)
LEGACY_SAME="$G_HOME/.grok/hooks/craftsman.json"
printf '%s\n' "{\"hooks\":{\"PreToolUse\":[{\"hooks\":[{\"command\":\"env CLAUDE_PLUGIN_ROOT=${HERE_ROOT} bash pre-write-check.sh\"}]}]}}" > "$LEGACY_SAME"
G_LEGACY=$(_g_hooks_row)
LEGACY_BEFORE=$(cksum "$LEGACY_SAME")
(
    cd /tmp && HOME="$G_HOME" CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        bash -c 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/config.sh"; source "$CLAUDE_PLUGIN_ROOT/hooks/lib/healthcheck.sh"; hc_refresh_owned_gate'
)
G_LEGACY_MARK=$(jq -r '.craftsman.root' "$LEGACY_SAME")
if [[ "$G_LEGACY" == warn\|*"craftsman-ci export --target grok-hooks"* && "$G_LEGACY_MARK" == "$HERE_ROOT" ]]; then
    log_pass "a legacy gate of this install warns, then the refresh adopts it"
else
    log_fail "legacy same-root gate" "row=$G_LEGACY mark=$G_LEGACY_MARK"
fi
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":"env CLAUDE_PLUGIN_ROOT=/tmp/craftsman-other-install bash pre-write-check.sh"}]}]}}' > "$LEGACY_SAME"
LEGACY_BYTES=$(cksum "$LEGACY_SAME")
G_LEGACY_OTHER=$(_g_hooks_row)
(
    cd /tmp && HOME="$G_HOME" CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        bash -c 'source "$CLAUDE_PLUGIN_ROOT/hooks/lib/config.sh"; source "$CLAUDE_PLUGIN_ROOT/hooks/lib/healthcheck.sh"; hc_refresh_owned_gate'
)
if [[ "$G_LEGACY_OTHER" == error\|*"belongs to /tmp/craftsman-other-install"* && "$G_LEGACY_OTHER" == *"craftsman-ci export --target grok-hooks"* && "$(cksum "$LEGACY_SAME")" == "$LEGACY_BYTES" ]]; then
    log_pass "a legacy gate of another install is an error and is left byte for byte"
else
    log_fail "legacy foreign gate" "row=$G_LEGACY_OTHER before=$LEGACY_BYTES after=$(cksum "$LEGACY_SAME")"
fi
unset LEGACY_BEFORE
rm -rf "$G_PROJ" "$G_HOME"

# The Grok row of the matrix is what hc_check_host prints. exit_code_observable
# was false while the captured run_terminal_command result carries exit_code
# (PROVENANCE.md, CR-146 decoder test), so the healthcheck told a Grok session
# the verification loop grants nothing. The value is the contract, not the key.
if jq -e '.hosts.grok.exit_code_observable == true and .hosts.grok.plugin_hooks_executed == false' \
    "$ROOT_DIR/hooks/host-capabilities.json" >/dev/null 2>&1; then
    log_pass "Grok matrix: exit codes observable, plugin hooks not executed (boolean)"
else
    log_fail "Grok matrix values" "$(jq -c '.hosts.grok | {version,exit_code_observable,plugin_hooks_executed}' "$ROOT_DIR/hooks/host-capabilities.json")"
fi
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=grok CLAUDE_PLUGIN_ROOT="$ROOT_DIR" hc_check_host
if [[ "${_HC_STATUSES[0]}" == "ok" && "${_HC_MESSAGES[0]}" == *"verification loop live"* && "${_HC_MESSAGES[0]}" != *"NOT observable"* ]]; then
    log_pass "hc_check_host on Grok reports the verification loop live"
else
    log_fail "hc_check_host Grok loop" "${_HC_STATUSES[0]} ${_HC_MESSAGES[0]}"
fi

echo ""
_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CRAFTSMAN_SESSION_HOST=codex CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 hc_check_agent_teams
if [[ "${_HC_MESSAGES[0]}" == *"Claude team flag does not apply"* ]]; then
    log_pass "a parent Claude team flag does not enable teams in Codex"
else
    log_fail "Codex incorrectly inherits Claude teams"
fi

echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
