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
_BRIDGE="${HOME}/.claude/craftsman-session-state-path"
_BRIDGE_BAK="${_BRIDGE}.test-backup"
[[ -f "$_BRIDGE" ]] && cp "$_BRIDGE" "$_BRIDGE_BAK"

_DB_BRIDGE="${HOME}/.claude/craftsman-metrics-db-path"
_DB_BRIDGE_BAK="${_DB_BRIDGE}.test-backup"
[[ -f "$_DB_BRIDGE" ]] && cp "$_DB_BRIDGE" "$_DB_BRIDGE_BAK"

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
if [[ -f "$_DB_BRIDGE" ]]; then
    bridged_db=$(cat "$_DB_BRIDGE")
    if [[ "$bridged_db" == "${CLAUDE_PLUGIN_DATA}/metrics.db" ]]; then
        log_pass "Metrics DB bridge resolves CLAUDE_PLUGIN_DATA"
    else
        log_fail "Metrics DB bridge should point at \${CLAUDE_PLUGIN_DATA}/metrics.db" "got: $bridged_db"
    fi
else
    log_fail "Session start should write ~/.claude/craftsman-metrics-db-path" "file missing"
fi

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
[[ -f "$_BRIDGE_BAK" ]] && mv "$_BRIDGE_BAK" "$_BRIDGE"
[[ -f "$_DB_BRIDGE_BAK" ]] && mv "$_DB_BRIDGE_BAK" "$_DB_BRIDGE"

# Cleanup
rm -rf "$CLAUDE_PLUGIN_DATA" "/tmp/craftsman-fake-home-$$"

echo ""
echo "=== Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="

[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
