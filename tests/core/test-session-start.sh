#!/usr/bin/env bash
# =============================================================================
# Session Start Hook Tests
# Tests dependency checking and auto-setup gate.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-session-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"

mkdir -p "$CLAUDE_PLUGIN_DATA"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Backup bridge files - session-start.sh overwrites them with test paths
_DB_BRIDGE="${HOME}/.claude/craftsman-metrics-db-path"
backup_home_bridges

echo ""
echo "=== Session Start Hook Tests ==="

# Test: Hook outputs valid JSON
START_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-session-home.XXXXXX")
result=$(echo '{}' | HOME="$START_HOME" bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
exit_code=$?
if [[ "$exit_code" == "0" ]]; then
    log_pass "Session start exits 0"
else
    log_fail "Session start should exit 0" "got exit $exit_code"
fi

# Test: Output is valid JSON with systemMessage
if echo "$result" | jq -e '.systemMessage' >/dev/null 2>&1; then
    log_pass "Output contains systemMessage key"
else
    log_fail "Output should contain systemMessage" "got: $result"
fi

# Test: systemMessage contains Craftsman active
msg=$(echo "$result" | jq -r '.systemMessage' 2>/dev/null)
if [[ "$msg" == *"Craftsman active"* ]]; then
    log_pass "systemMessage contains 'Craftsman active'"
else
    log_fail "systemMessage should contain 'Craftsman active'" "got: $msg"
fi

# Test: Dependency check - all deps present means no warning
if command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v sqlite3 >/dev/null 2>&1; then
    if [[ "$msg" != *"MISSING"* ]]; then
        log_pass "No dependency warning when all deps present"
    else
        log_fail "Should not warn when all deps present" "got: $msg"
    fi
fi

# Test: metrics DB bridge points at the slug-aware path, not the bare fallback.
# Skills query through the Bash tool, where CLAUDE_PLUGIN_DATA does not exist:
# without this bridge they read a database no hook has written to since the
# plugin slug changed, and report a silent instrumentation outage.
#
# Run under a private HOME. ~/.claude/craftsman-metrics-db-path is one file for
# the whole machine, so reading the real one asserted a property of whatever
# session wrote it last: a live editor session overwriting it between this
# hook call and this read failed the suite for a reason that had nothing to do
# with the code, and it reproduced only under concurrency.
BRIDGE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-bridge.XXXXXX")
mkdir -p "$BRIDGE_HOME/.claude"
echo '{}' | HOME="$BRIDGE_HOME" bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null 2>&1
_OWN_BRIDGE="${BRIDGE_HOME}/.claude/craftsman-metrics-db-path"

if [[ -f "$_OWN_BRIDGE" ]]; then
    bridged_db=$(cat "$_OWN_BRIDGE")
    if [[ "$bridged_db" == "${CLAUDE_PLUGIN_DATA}/metrics.db" ]]; then
        log_pass "Metrics DB bridge resolves CLAUDE_PLUGIN_DATA"
    else
        log_fail "Metrics DB bridge should point at \${CLAUDE_PLUGIN_DATA}/metrics.db" "got: $bridged_db"
    fi
else
    log_fail "Session start should write ~/.claude/craftsman-metrics-db-path" "file missing"
fi
rm -rf "$BRIDGE_HOME"

# Test: the reporting skills read the bridge instead of hardcoding the fallback.
# The fallback path may still appear, but only as the `|| echo` arm of a bridge
# read: any line naming it without also naming the bridge is a hardcoded query.
# Matching on `sqlite3 <path>` alone is not enough, the original defect assigned
# the path to a variable first (`DB=~/...; sqlite3 "$DB"`).
hardcoded=$(grep -n 'plugins/data/craftsman/metrics\.db' \
    "$ROOT_DIR/skills/metrics/SKILL.md" "$ROOT_DIR/skills/debug/SKILL.md" 2>/dev/null \
    | grep -v 'craftsman-metrics-db-path')
if [[ -z "$hardcoded" ]]; then
    log_pass "Skills query the bridged DB path"
else
    log_fail "Skills must not query the bare fallback DB" "hardcoded at: $hardcoded"
fi

# Test: every SQL the reporting skills run is valid against the real schema.
# Step 7 selected agent_invocations and team_type, columns the sessions table
# never had: the query failed on every run and its `|| echo` arm announced an
# absence of activity, turning a schema error into a plausible-looking report.
SCHEMA_DB="${CLAUDE_PLUGIN_DATA}/schema-probe.db"
rm -f "$SCHEMA_DB"
(
    export METRICS_DB_DIR="$CLAUDE_PLUGIN_DATA"
    export METRICS_DB="$SCHEMA_DB"
    source "$ROOT_DIR/hooks/lib/metrics-db.sh"
    METRICS_DB="$SCHEMA_DB"
    metrics_init
) >/dev/null 2>&1

sql_errors=""
while IFS= read -r query; do
    err=$(sqlite3 "$SCHEMA_DB" "$query" 2>&1 >/dev/null)
    [[ -n "$err" ]] && sql_errors+="${err}; "
done < <(grep -ho '"SELECT [^"]*"' "$ROOT_DIR/skills/metrics/SKILL.md" "$ROOT_DIR/skills/debug/SKILL.md" 2>/dev/null | tr -d '"')

if [[ -z "$sql_errors" ]]; then
    log_pass "Skill queries are valid against the metrics schema"
else
    log_fail "Skill queries must match the schema" "$sql_errors"
fi

# Test: a correction outcome a skill names is one the table can hold. A value
# outside the CHECK constraint is not an SQL error, it is a count of zero: the
# score step counted action='fix' and its bonus never moved (review of main
# eb54d13, delivery D3). The persisted value is `fixed`.
allowed_actions=$(sqlite3 "$SCHEMA_DB" "SELECT sql FROM sqlite_master WHERE name='corrections';" 2>/dev/null | grep -oE "action IN \([^)]*\)" | grep -oE "'[a-z_]+'")
unknown_actions=$(grep -rhoE "action ?= ?'[A-Za-z_]+'" "$ROOT_DIR/skills" --include=SKILL.md 2>/dev/null | grep -oE "'[A-Za-z_]+'" \
    | grep -vxF -e "${allowed_actions:-none}" | tr '\n' ' ')
if [[ -n "$allowed_actions" && -z "$unknown_actions" ]]; then
    log_pass "Skills name only correction outcomes the schema accepts"
else
    log_fail "Skills name a correction outcome the table refuses" "unknown: ${unknown_actions:-none}; schema: ${allowed_actions:-unreadable}"
fi
rm -f "$SCHEMA_DB"

# Test: Auto-setup gate warns when no config
ORIGINAL_HOME="$HOME"
export HOME="/tmp/craftsman-fake-home-$$"
mkdir -p "$HOME/.claude"
result2=$(echo '{}' | bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
msg2=$(echo "$result2" | jq -r '.systemMessage' 2>/dev/null)
if [[ "$msg2" == *"/craftsman:setup"* ]]; then
    log_pass "Auto-setup gate warns when no .craft-config.yml"
else
    log_fail "Should warn about missing config" "got: $msg2"
fi
export HOME="$ORIGINAL_HOME"

# Restore bridge files
restore_home_bridges

# Cleanup
# --- A verification subprocess is not a session ------------------------------
#
# `claude -p` from haiku-verify.sh fires SessionStart too: this hook then
# rewrote session-start-ts and deleted session-writes and session-violations,
# so the real session's duration and write count restarted at every Haiku
# verification. The recursion guard the verifier sets is the signal.
HEADLESS_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-headless-start.XXXXXX")
mkdir -p "$HEADLESS_HOME/data" "$HEADLESS_HOME/.claude"
printf '1700000000' > "$HEADLESS_HOME/data/session-start-ts"
printf '3' > "$HEADLESS_HOME/data/session-writes"
headless_out=$(echo '{}' | CRAFTSMAN_HEADLESS_VERIFY=1 HOME="$HEADLESS_HOME" CLAUDE_PLUGIN_DATA="$HEADLESS_HOME/data" \
    bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
if [[ "$(cat "$HEADLESS_HOME/data/session-start-ts")" == "1700000000" && "$(cat "$HEADLESS_HOME/data/session-writes" 2>/dev/null)" == "3" ]]; then
    log_pass "a SessionStart fired by the verification subprocess leaves the real session's counters alone"
else
    log_fail "a SessionStart fired by the verification subprocess leaves the real session's counters alone" \
        "start-ts=$(cat "$HEADLESS_HOME/data/session-start-ts" 2>/dev/null) writes=$(cat "$HEADLESS_HOME/data/session-writes" 2>/dev/null)"
fi
if [[ -z "$headless_out" ]]; then
    log_pass "and injects nothing into the subprocess"
else
    log_fail "and injects nothing into the subprocess" "output: ${headless_out:0:80}"
fi
rm -rf "$HEADLESS_HOME"

# --- Skills approved at the old depth are named, not silently unloaded --------
LEGACY_SKILLS=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-legacy-skills.XXXXXX")
mkdir -p "$LEGACY_SKILLS/.claude/skills/craftsman-learned/learned-php001" "$LEGACY_SKILLS/data" "$LEGACY_SKILLS/.claude"
printf -- '---\nname: learned-php001\n---\n' > "$LEGACY_SKILLS/.claude/skills/craftsman-learned/learned-php001/SKILL.md"
legacy_out=$( cd "$LEGACY_SKILLS" && echo '{}' | HOME="$LEGACY_SKILLS" CLAUDE_PLUGIN_DATA="$LEGACY_SKILLS/data" \
    bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null )
if echo "$legacy_out" | grep -q "1 learned skill(s) at a depth Claude Code does not load"; then
    log_pass "a learned skill approved at the old depth is reported at SessionStart, with the move to make"
else
    log_fail "a learned skill approved at the old depth is reported at SessionStart" "output lacks the notice"
fi
rm -rf "$LEGACY_SKILLS"

# --- The wrapper hashes the project the hooks hash ----------------------------
#
# ~/.claude/craftsman-instincts.sh hashed $PWD; the hooks hash the git
# toplevel's physical path (metrics_project_hash). From a subdirectory, or
# through a symlinked path, /craftsman:metrics answered "no instincts" while
# SessionStart announced candidates, and `approve` could not find the id.
WRAP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-wrapper-hash.XXXXXX")
mkdir -p "$WRAP_HOME/.claude" "$WRAP_HOME/repo/src/Domain" "$WRAP_HOME/data"
( cd "$WRAP_HOME/repo" && git init -q ) >/dev/null 2>&1
( cd "$WRAP_HOME/repo" && echo '{}' | HOME="$WRAP_HOME" CLAUDE_PLUGIN_DATA="$WRAP_HOME/data" bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null 2>&1 )
HOOK_HASH=$( cd "$WRAP_HOME/repo/src/Domain" && bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_project_hash" )
WRAP_HASH=$( cd "$WRAP_HOME/repo/src/Domain" && HOME="$WRAP_HOME" CLAUDE_PLUGIN_DATA="$WRAP_HOME/data" bash -c '
    sed -n "s/^PROJECT_HASH=//p" "$HOME/.claude/craftsman-instincts.sh" >/dev/null
    # run the wrapper with a command that prints the hash it resolved
    CRAFTSMAN_PRINT_PROJECT_HASH=1 bash "$HOME/.claude/craftsman-instincts.sh" candidates 2>/dev/null' )
if [[ -n "$HOOK_HASH" && "$WRAP_HASH" == "$HOOK_HASH" ]]; then
    log_pass "the instincts wrapper resolves the same project hash as the hooks from a subdirectory"
else
    log_fail "the instincts wrapper resolves the same project hash as the hooks from a subdirectory" "hook=$HOOK_HASH wrapper=$WRAP_HASH"
fi
rm -rf "$WRAP_HOME"

# Test: an event Claude Code does not have, declared in hooks.json, is named in
# the banner, sorted and comma-joined; the shipped hooks.json names none. The
# hook reads hooks.json beside itself, so it runs here from a directory of
# links to the real hooks with one altered hooks.json.
check_unknown_hook_events() {
    local schema_root out
    schema_root=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-schema-root.XXXXXX")
    mkdir -p "$schema_root/hooks"
    ln -s "$ROOT_DIR"/hooks/* "$schema_root/hooks/"
    rm -f "$schema_root/hooks/hooks.json"
    jq '.hooks.ZetaEvent = [] | .hooks.AlphaEvent = []' "$ROOT_DIR/hooks/hooks.json" > "$schema_root/hooks/hooks.json"
    out=$(echo '{}' | HOME="$START_HOME" bash "$schema_root/hooks/session-start.sh" 2>/dev/null | jq -r '.systemMessage')
    rm -rf "$schema_root"
    assert_contains "unknown hook events are named, sorted" "$out" "unsupported events: AlphaEvent,ZetaEvent."
    assert_not_contains "the shipped hooks.json declares no unknown event" "$result" "SCHEMA WARNING"
}
check_unknown_hook_events

# Test: SessionStart also fires after a compaction, with the same session id.
# The session goes on, so its start time and its write and violation tallies
# survive; a session that starts restarts them (CR-296).
check_compaction_keeps_session_tallies() {
    local id=compact-keeps-tallies started writes violations
    _session_start_as() {
        printf '{"session_id":"%s","source":"%s"}' "$id" "$1" \
            | HOME="$START_HOME" bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null 2>&1
    }
    _session_start_as startup
    printf '1000' > "$CLAUDE_PLUGIN_DATA/session-start-ts-$id"
    printf 'a.php\nb.php\n' > "$CLAUDE_PLUGIN_DATA/session-writes-$id"
    printf 'blocked\n' > "$CLAUDE_PLUGIN_DATA/session-violations-$id"
    # Older than the sweep's age limit: a session that lives a week keeps it.
    touch -t 202001010000 "$CLAUDE_PLUGIN_DATA/session-start-ts-$id"
    _session_start_as compact
    started=$(cat "$CLAUDE_PLUGIN_DATA/session-start-ts-$id" 2>/dev/null)
    writes=$(wc -l < "$CLAUDE_PLUGIN_DATA/session-writes-$id" 2>/dev/null | tr -d ' ')
    violations=$(cat "$CLAUDE_PLUGIN_DATA/session-violations-$id" 2>/dev/null)
    assert_contains "a compaction keeps the session start time" "start=$started" "start=1000"
    assert_contains "a compaction keeps the session writes" "writes=$writes" "writes=2"
    assert_contains "a compaction keeps the session violations" "violations=$violations" "violations=blocked"
    _session_start_as startup
    started=$(cat "$CLAUDE_PLUGIN_DATA/session-start-ts-$id" 2>/dev/null)
    assert_not_contains "a new start restarts the session clock" "start=$started" "start=1000"
    if [[ -e "$CLAUDE_PLUGIN_DATA/session-writes-$id" ]]; then
        log_fail "a new start restarts the session tallies" "session-writes-$id still present"
    else
        log_pass "a new start restarts the session tallies"
    fi
}
check_compaction_keeps_session_tallies

# Test: SessionStart sweeps the files of sessions that ended without a
# SessionEnd, a week old, and nothing else; and it sweeps once a day, since a
# file a week old does not need a find and a Python start on every session.
check_sweep_takes_ended_sessions_only() {
    local sweep_data="$START_HOME/sweep-data" bindings="$START_HOME/.claude/craftsman/sessions"
    mkdir -p "$sweep_data" "$bindings"
    _sweep_fixture() {
        printf 'x\n' > "$sweep_data/session-writes-ended"
        printf 'x\n' > "$sweep_data/session-writes-live"
        printf 'x\n' > "$sweep_data/metrics.db"
        printf '{}' > "$bindings/ended.json"
        printf '{}' > "$bindings/live.json"
        touch -t 202001010000 "$sweep_data/session-writes-ended" "$sweep_data/metrics.db" "$bindings/ended.json"
    }
    _sweep_start() {
        echo '{"session_id":"sweeper","source":"startup"}' | HOME="$START_HOME" CRAFTSMAN_RUNTIME_HOME="$START_HOME" CLAUDE_PLUGIN_DATA="$sweep_data" \
            bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null 2>&1
    }
    _sweep_fixture
    _sweep_start
    local left
    left=$(cd "$sweep_data" && ls metrics.db session-writes-* 2>/dev/null | tr '\n' ' ')
    left="$left$(cd "$bindings" && ls ended.json live.json 2>/dev/null | tr '\n' ' ')"
    assert_contains "the sweep takes a week-old session file and binding" "left=$left." "left=metrics.db session-writes-live live.json ."
    _sweep_fixture
    _sweep_start
    if [[ -e "$sweep_data/session-writes-ended" ]]; then
        log_pass "a second start the same day does not sweep again"
    else
        log_fail "a second start the same day does not sweep again" "session-writes-ended was swept"
    fi
    touch -t 202001010000 "$sweep_data/.sweep-stamp"
    _sweep_start
    if [[ -e "$sweep_data/session-writes-ended" ]]; then
        log_fail "a start a day after the last sweep sweeps again" "session-writes-ended survived"
    else
        log_pass "a start a day after the last sweep sweeps again"
    fi
}
check_sweep_takes_ended_sessions_only

rm -rf "$CLAUDE_PLUGIN_DATA" "/tmp/craftsman-fake-home-$$" "${START_HOME:-}"

echo ""
echo "=== Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="

[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
