#!/usr/bin/env bash
# =============================================================================
# One gate per write on Grok (CR-310), and no model call held in line (CR-315).
#
# Measured on Grok 1.0.62 (2026-11-17, `grok -p` with --debug-file): Grok
# discovers the plugin Claude Code installed under ~/.claude/plugins and runs
# its hooks (`plugin/craftsman/hooks:*`), and it runs the exported gate in
# ~/.grok/hooks too (`global/craftsman:*`). Every hook ran twice. The plugin
# path also skips the handlers that carry `if` (the git guards); the export
# keeps them. No setting holds the plugin off: a plain name in
# `[plugins] disabled` only names plugins Grok installed, and the full ID
# hashes the install path, which changes with every version.
#
# So a hook run from Grok's plugin path steps aside when a live exported gate
# is there. Grok sets GROK_PLUGIN_ROOT for a plugin hook only, and the export
# marks its own handlers, so a Claude Code session started from a Grok shell
# (which may inherit GROK_SESSION_ID) never steps aside.
#
# Grok has no `async`: the agent hooks ran in line, 8.3 to 9.3 s per write on
# each path. The export turns them off with the switch they already honour.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-grok-path.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$WORK/data" CRAFTSMAN_RUNTIME_HOME="$WORK/home"
export CLAUDE_PLUGIN_OPTION_STRICTNESS=strict
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDE_CODE_SESSION_ID CRAFTSMAN_SESSION_ID \
    GROK_SESSION_ID GROK_HOOK_EVENT GROK_PLUGIN_ROOT GROK_PLUGIN_DATA GROK_WORKSPACE_ROOT CRAFTSMAN_EXPORTED_GATE
PROJECT="$WORK/project"
mkdir -p "$HOME/.claude" "$HOME/.grok/hooks" "$CLAUDE_PLUGIN_DATA" "$PROJECT/src/Domain"
printf '{}\n' > "$PROJECT/composer.json"
GATE="$HOME/.grok/hooks/craftsman.json"
BAD="$PROJECT/src/Domain/Bad.php"
PAYLOAD=$(jq -n --arg f "$BAD" --arg c $'<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\Domain;\n\nclass Bad\n{\n}\n' \
    '{session_id: "g310", hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $f, content: $c}}')

_equal() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then log_pass "$1"; else log_fail "$1" "expected '$2', got '$3'"; fi
}
GATE_CODE=0
# pre-write-check.sh on a write PHP002 refuses, under the environment given.
_pre_write() { # <env assignments...>
    GATE_CODE=0
    (cd "$PROJECT" && printf '%s' "$PAYLOAD" | env "$@" CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
        bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1) || GATE_CODE=$?
}
PLUGIN_PATH=(GROK_HOOK_EVENT=pre_tool_use GROK_SESSION_ID=g310 GROK_PLUGIN_ROOT="$ROOT_DIR" GROK_WORKSPACE_ROOT="$PROJECT")

echo "=== The export the steps-aside decision trusts ==="
python3 "$ROOT_DIR/ci/host_hooks.py" grok "$ROOT_DIR" "$GATE" --data "$WORK/grok-data" >/dev/null
MARKED=$(jq '[.hooks[][].hooks[] | select(.command | test("CRAFTSMAN_EXPORTED_GATE=1 "))] | length' "$GATE")
TOTAL=$(jq '[.hooks[][].hooks[]] | length' "$GATE")
_equal "every exported handler says it is the exported gate" "$TOTAL" "$MARKED"
AGENTS_OFF=$(jq '[.hooks[][].hooks[] | select(.command | test("CLAUDE_PLUGIN_OPTION_AGENT_HOOKS=false "))] | length' "$GATE")
_equal "every exported handler carries agent hooks off (Grok runs async in line)" "$TOTAL" "$AGENTS_OFF"

# On a real machine the plugin path and the exported gate are two checkouts
# (the Claude Code cache, the developer's clone). The gate's root only has
# to hold the hooks for the gate to count as live.
mkdir -p "$WORK/gate-root/hooks" && touch "$WORK/gate-root/hooks/pre-write-check.sh"
_point_gate() { # <root>
    jq --arg r "$1" '.craftsman.root = $r' "$GATE" > "$GATE.tmp" && mv "$GATE.tmp" "$GATE"
}
_point_gate "$WORK/gate-root"

echo "=== Grok's plugin path steps aside for a live exported gate ==="
_pre_write "${PLUGIN_PATH[@]}"
assert_exit_code "the plugin path lets the exported gate judge" 0 "$GATE_CODE"
_pre_write "${PLUGIN_PATH[@]}" CRAFTSMAN_EXPORTED_GATE=1
assert_exit_code "the exported gate itself judges and refuses" 2 "$GATE_CODE"

echo "=== It never steps aside for nothing ==="
mv "$GATE" "$WORK/gate.json"
_pre_write "${PLUGIN_PATH[@]}"
assert_exit_code "no exported gate: the plugin path is the gate" 2 "$GATE_CODE"
jq --arg r "$WORK/gone" '.craftsman.root = $r' "$WORK/gate.json" > "$GATE"
_pre_write "${PLUGIN_PATH[@]}"
assert_exit_code "an exported gate whose checkout is gone is not a gate" 2 "$GATE_CODE"
mv "$WORK/gate.json" "$GATE"
_pre_write GROK_SESSION_ID=inherited
assert_exit_code "a Claude Code session started from a Grok shell keeps its gate" 2 "$GATE_CODE"
_pre_write
assert_exit_code "Claude Code keeps its gate when an export sits in ~/.grok" 2 "$GATE_CODE"

# An export written before the mark existed carries GROK_PLUGIN_ROOT (the
# export sets it) and no CRAFTSMAN_EXPORTED_GATE. Its hooks, run from the
# checkout it names, must not step aside for themselves: the gate would be
# off, and its session start, which rewrites the export, with it.
_point_gate "$ROOT_DIR"
_pre_write "${PLUGIN_PATH[@]}"
assert_exit_code "an exported gate never steps aside for itself, marked or not" 2 "$GATE_CODE"

echo "=== Every hook script carries the step-aside guard ==="
MISSING=""
for script in $(jq -r '[.hooks[][].hooks[].command | capture("/hooks/(?<s>[^\"/ ]+\\.sh)").s] | unique | .[]' "$ROOT_DIR/hooks/hooks.json"); do
    grep -q 'lib/exported-gate.sh' "$ROOT_DIR/hooks/$script" || MISSING="$MISSING $script"
done
_equal "no hook script in hooks.json runs twice on Grok" "" "$MISSING"

echo "=== The exported agent hook spends no model call ==="
mkdir -p "$WORK/bin"
printf '#!/bin/sh\ntouch "%s/claude-called"\necho CLEAN\n' "$WORK" > "$WORK/bin/claude"
chmod +x "$WORK/bin/claude"
printf '<?php\nnamespace App\\Domain;\nuse App\\Infrastructure\\Repo;\nfinal class Order {}\n' > "$PROJECT/src/Domain/Order.php"
(cd "$PROJECT" && git init -q && git add -A) >/dev/null 2>&1
VERIFIER=$(jq -r '[.hooks.PostToolUse[].hooks[].command | select(test("agent-ddd-verifier"))][0]' "$GATE")
_run_verifier() { # <command>
    rm -f "$WORK/claude-called"
    (cd "$PROJECT" && printf '{"tool_name":"Write","tool_input":{"file_path":"src/Domain/Order.php"},"cwd":"%s"}' "$PROJECT" \
        | env -u CLAUDE_EFFORT -u CRAFTSMAN_HEADLESS_VERIFY PATH="$WORK/bin:$PATH" bash -c "$1" >/dev/null 2>&1)
}
_run_verifier "${VERIFIER/CLAUDE_PLUGIN_OPTION_AGENT_HOOKS=false /}"
if [[ -f "$WORK/claude-called" ]]; then
    log_pass "control: without the switch the exported verifier calls claude"
else
    log_fail "control" "the verifier never called the stub: the case below would prove nothing"
fi
_run_verifier "$VERIFIER"
if [[ ! -f "$WORK/claude-called" ]]; then
    log_pass "the exported verifier does not call claude"
else
    log_fail "the exported verifier does not call claude" "it ran a model call in line on a host without async"
fi

test_summary
