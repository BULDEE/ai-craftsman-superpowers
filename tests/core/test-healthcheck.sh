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
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="" hc_check_agent_teams
if [[ "${_HC_STATUSES[0]}" == "ok" && "${_HC_MESSAGES[0]}" == *"degraded"* ]]; then
    log_pass "hc_check_agent_teams: ok + degraded-mode message without the flag"
else
    log_fail "hc_check_agent_teams unset: ${_HC_STATUSES[0]} / ${_HC_MESSAGES[0]}"
fi

_HC_NAMES=(); _HC_STATUSES=(); _HC_MESSAGES=(); _HC_PASS=0; _HC_TOTAL=0
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1" hc_check_agent_teams
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
if [[ "$CX_HOST" == ok\|codex* && "$CX_BRIDGE" == ok\|codex:* && "$CX_BRIDGE" == *"$CX_DATA"* ]]; then
    log_pass "a Codex shell names codex from CODEX_THREAD_ID, and the bridge row points at this installation's data directory, not at ~/.claude"
else
    log_fail "healthcheck under a Codex shell" "host=[$(printf '%s' "$CX_HOST" | cut -c1-70)] bridge=[$(printf '%s' "$CX_BRIDGE" | cut -c1-80)]"
fi
rm -rf "$CX_DATA"

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

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
