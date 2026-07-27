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
result=$(echo '{}' | bash "$ROOT_DIR/hooks/session-start.sh" 2>/dev/null)
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
rm -rf "$CLAUDE_PLUGIN_DATA" "/tmp/craftsman-fake-home-$$"

echo ""
echo "=== Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="

[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
