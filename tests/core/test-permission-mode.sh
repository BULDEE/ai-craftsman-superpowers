#!/usr/bin/env bash
# =============================================================================
# What the hooks do in plan mode, and what they must keep doing everywhere else.
#
# Claude Code passes `permission_mode` in the common fields of every hook's
# JSON input. Nothing in this plugin read it, so in plan mode, where the
# harness does NOT execute the Write, post-write-check.sh still recorded every
# finding: violations on files that were never written, counted in the 7-day
# trends and fed to the instinct candidate query, with nothing in the row
# saying they never happened.
#
# The two halves of this file matter equally. Plan mode must stop RECORDING,
# and it must keep REPORTING, because telling the model what its plan would
# break is the whole value of a check during planning. And the gate must stay
# red in `default`, so this change cannot quietly turn the gate off.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-permission-mode.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export HOME="$WORK/home"
mkdir -p "$HOME/.claude" "$WORK/src" "$WORK/src/Domain/Service"

echo "=== Permission mode ==="

# --- The helper's own contract -------------------------------------------------
source "$ROOT_DIR/hooks/lib/permission-mode.sh"

for case_line in \
    'plan|plan|the mode the harness names' \
    'default|default|the ordinary mode' \
    'bypassPermissions|bypassPermissions|a mode that changes nothing here' \
    'acceptEdits|acceptEdits|another documented mode'
do
    IFS='|' read -r given expected why <<< "$case_line"
    got=$(hook_permission_mode "$(printf '{"permission_mode":"%s"}' "$given")")
    if [[ "$got" == "$expected" ]]; then
        log_pass "mode: $why ($expected)"
    else
        log_fail "mode: $why" "expected $expected, got $got"
    fi
done

# An absent field is every harness version before it existed, and every caller
# that builds its own input. An unknown mode is the strict reading: a mode this
# plugin has never heard of must not silently turn anything off, and new modes
# appear in the harness faster than they appear here.
absent=$(hook_permission_mode '{}')
unknown=$(hook_permission_mode '{"permission_mode":"somethingNew"}')
if [[ "$absent" == "default" && "$unknown" == "default" ]]; then
    log_pass "an absent or unknown mode reads as default, never as a licence"
else
    log_fail "an absent or unknown mode reads as default" \
        "absent=$absent unknown=$unknown"
fi

# --- The hook, end to end ------------------------------------------------------
cat > "$WORK/src/Bad.php" <<'PHPSRC'
<?php
class Bad { public function setX($v) { $this->x = $v; } }
PHPSRC
( cd "$WORK" && git init -q && git add -A ) >/dev/null 2>&1

_rows() {
    local db="$1"
    [[ -f "$db" ]] || { printf '0'; return 0; }
    python3 -c "
import sqlite3, sys
try:
    print(sqlite3.connect(sys.argv[1]).execute('SELECT COUNT(*) FROM violations').fetchone()[0])
except Exception:
    print(0)
" "$db" 2>/dev/null
}

_run_mode() {
    local mode="$1" data="$WORK/data-$1"
    mkdir -p "$data"
    ( cd "$WORK" && printf '{"tool_name":"Write","permission_mode":"%s","tool_input":{"file_path":"%s/src/Bad.php"},"cwd":"%s"}' \
        "$mode" "$WORK" "$WORK" \
        | CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_OPTION_strictness=strict \
          bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 )
}

plan_out=$(_run_mode plan)
plan_code=$?
plan_rows=$(_rows "$WORK/data-plan/metrics.db")

assert_contains "plan mode still reports the finding" "$plan_out" "PHP001"
if [[ "${plan_rows:-0}" -eq 0 ]]; then
    log_pass "plan mode records no violation, because no file was written"
else
    log_fail "plan mode records no violation" "$plan_rows row(s) for a file that does not exist"
fi

default_out=$(_run_mode default)
default_rows=$(_rows "$WORK/data-default/metrics.db")

assert_contains "default mode still reports the finding" "$default_out" "PHP001"
if [[ "${default_rows:-0}" -gt 0 ]]; then
    log_pass "default mode still records ($default_rows row(s))"
else
    log_fail "default mode still records" "nothing was recorded, so the metrics went silent everywhere"
fi

# The gate itself. This is the assertion that stops the change above from
# becoming a way to turn the gate off: exit 2 in BOTH modes, including
# bypassPermissions, where the hooks reference says a hook's exit 2 outranks a
# permissionDecision. That is a decision taken on purpose here rather than by
# omission.
for mode in plan default bypassPermissions; do
    code=0
    # Built with json.dumps, never with a literal backslash-n: passed through
    # verbatim the whole fixture reaches the hook as ONE line, no anchored
    # regex can match, and the assertion passes or fails for a reason that has
    # nothing to do with the rule it names. That mistake cost a day on #47.
    # A LAYER violation, not a missing declare: PHP001 is auto-fixed by this
    # hook, which answers `allow` with an updatedInput, so a fixture built on
    # it would have asserted that the gate blocks while measuring a repair.
    payload=$(python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Write',
    'permission_mode': sys.argv[1],
    'tool_input': {
        'file_path': sys.argv[2] + '/src/Domain/Service/UserService.php',
        'content': '<?php\ndeclare(strict_types=1);\nuse App\\\\Infrastructure\\\\Persistence\\\\Repo;\nfinal class UserService {}\n',
    },
    'cwd': sys.argv[2],
}))" "$mode" "$WORK")
    ( cd "$WORK" && printf '%s' "$payload" \
        | CLAUDE_PLUGIN_DATA="$WORK/data-gate-$mode" CLAUDE_PLUGIN_OPTION_strictness=strict \
          bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1 ) || code=$?
    if [[ "$code" -eq 2 ]]; then
        log_pass "the gate still blocks in $mode (exit 2)"
    else
        log_fail "the gate still blocks in $mode" "exit $code"
    fi
done

# --- The semantic layer pays nothing for a file that will not exist ------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'STUB'
#!/bin/sh
echo "called" >> "$CLAUDE_STUB_LOG"
echo "CLEAN"
STUB
chmod +x "$WORK/bin/claude"

export CLAUDE_STUB_LOG="$WORK/stub-calls"
: > "$CLAUDE_STUB_LOG"
( cd "$WORK" && printf '{"tool_name":"Write","permission_mode":"plan","tool_input":{"file_path":"%s/src/Bad.php"},"cwd":"%s"}' "$WORK" "$WORK" \
    | env -u CLAUDE_EFFORT -u CRAFTSMAN_HEADLESS_VERIFY PATH="$WORK/bin:$PATH" \
          CLAUDE_PLUGIN_DATA="$WORK/data-verify" \
      bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 ) || true
plan_calls=$(awk 'END { print NR }' "$CLAUDE_STUB_LOG" 2>/dev/null)

: > "$CLAUDE_STUB_LOG"
( cd "$WORK" && printf '{"tool_name":"Write","permission_mode":"default","tool_input":{"file_path":"%s/src/Bad.php"},"cwd":"%s"}' "$WORK" "$WORK" \
    | env -u CLAUDE_EFFORT -u CRAFTSMAN_HEADLESS_VERIFY PATH="$WORK/bin:$PATH" \
          CLAUDE_PLUGIN_DATA="$WORK/data-verify2" \
      bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 ) || true
default_calls=$(awk 'END { print NR }' "$CLAUDE_STUB_LOG" 2>/dev/null)

if [[ "${plan_calls:-0}" -eq 0 ]]; then
    log_pass "plan mode spends no verification subprocess"
else
    log_fail "plan mode spends no verification subprocess" "$plan_calls call(s) for a file that will not exist"
fi
if [[ "${default_calls:-0}" -ge 1 ]]; then
    log_pass "default mode still verifies ($default_calls call)"
else
    log_fail "default mode still verifies" "the layer went silent everywhere"
fi

# --- A number in a security document that nobody checks ------------------------
#
# SECURITY.md said "19 scripts, 13 events" against 18 and 12 on disk. A reader
# auditing what runs on their machine counts the entries and finds a
# discrepancy they cannot explain, in the one document where that is least
# acceptable.
declared_events=$(python3 -c "
import json
data = json.load(open('$ROOT_DIR/hooks/hooks.json'))
print(len(data.get('hooks', data)))
" 2>/dev/null)
declared_scripts=$(ls "$ROOT_DIR"/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')

if grep -q "Hooks (${declared_scripts} scripts, ${declared_events} events)" "$ROOT_DIR/SECURITY.md"; then
    log_pass "SECURITY.md counts match hooks.json (${declared_scripts} scripts, ${declared_events} events)"
else
    log_fail "SECURITY.md counts match hooks.json" \
        "on disk: ${declared_scripts} scripts and ${declared_events} events; SECURITY.md says $(grep -o 'Hooks ([0-9]* scripts, [0-9]* events)' "$ROOT_DIR/SECURITY.md" | head -1)"
fi

# Every other document that states the count, because a figure repeated in
# three places drifts in three places.
stale_counts=$(grep -rln "Hooks ([0-9]* events)\|Hooks ([0-9]* scripts" \
    "$ROOT_DIR/docs" "$ROOT_DIR/CLAUDE.md" "$ROOT_DIR/README.md" 2>/dev/null \
    | while IFS= read -r doc; do
        grep -q "Hooks (${declared_events} events)\|Hooks (${declared_scripts} scripts, ${declared_events} events)" "$doc" || printf '%s ' "$doc"
      done)
if [[ -z "$stale_counts" ]]; then
    log_pass "no document states a hook count that hooks.json contradicts"
else
    log_fail "no document states a hook count that hooks.json contradicts" \
        "stale in: $stale_counts"
fi

test_summary
