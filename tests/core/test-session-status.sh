#!/usr/bin/env bash
# =============================================================================
# One session's quality state as JSON (ADR-0031): what the cockpit mod's band
# and turn receipt draw. Asserted on files the real hooks wrote, never on
# hand-made ones alone: a key the hooks stop writing must turn this red.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

STATUS_HOME="/tmp/craftsman-status-tests-$$"
export CLAUDE_PLUGIN_DATA="$STATUS_HOME/data"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
mkdir -p "$CLAUDE_PLUGIN_DATA"
ID=status-pulse

_hook() {
    HOME="$STATUS_HOME" CRAFTSMAN_RUNTIME_HOME="$STATUS_HOME" bash "$ROOT_DIR/hooks/$1" >/dev/null 2>&1
}

_status() {
    HOME="$STATUS_HOME" CRAFTSMAN_RUNTIME_HOME="$STATUS_HOME" CRAFTSMAN_SESSION_ID="$ID" \
        CRAFTSMAN_SESSION_HOST=claude-code CRAFTSMAN_PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" \
        bash "$ROOT_DIR/bin/craftsman-helper" session status 2>&1
}

echo ""
echo "=== Session status ==="

printf '{"session_id":"%s","source":"startup"}' "$ID" | _hook session-start.sh
fresh=$(_status)
assert_json_valid "a fresh session's status is JSON" "$fresh"
assert_contains "a fresh session has written nothing" \
    "$(jq -c '[.writes, .blocked, .warned, .tests.verdict, (.since | type)]' <<< "$fresh")" \
    '\[0,0,0,"not-run","number"\]'

FIXTURE="$ROOT_DIR/tests/core/fixtures/invalid-no-strict.php"
jq -n --arg id "$ID" --arg fp "$FIXTURE" \
    '{session_id: $id, hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $fp}}' \
    | _hook post-write-check.sh
written=$(_status)
assert_contains "the write the hook validated is counted" "$(jq -c '[.writes, .files]' <<< "$written")" '\[1,1\]'
assert_contains "the block the hook recorded is counted" "blocked=$(jq '.blocked' <<< "$written")" "blocked=[1-9]"
assert_contains "the open block names the file and its rule" \
    "$(jq -c '.open[0] | [.file, (.rules | index("PHP001") != null)]' <<< "$written")" \
    "invalid-no-strict.php\",true"

state=$(HOME="$STATUS_HOME" CRAFTSMAN_SESSION_ID="$ID" bash -c \
    'source "$0/hooks/lib/session-files.sh"; session_file session-state.json' "$ROOT_DIR")
python3 "$ROOT_DIR/hooks/lib/test_scope.py" fail "$state" "vendor/bin/phpunit" "vendor/bin/phpunit" >/dev/null 2>&1
red=$(_status)
assert_contains "a red run the hooks recorded is the verdict" \
    "$(jq -c '.tests' <<< "$red")" '"verdict":"red","red_runs":\["vendor/bin/phpunit"\]'
python3 "$ROOT_DIR/hooks/lib/test_scope.py" pass "$state" "vendor/bin/phpunit" >/dev/null 2>&1
assert_contains "the same run green is evidence" "$(jq -r '.tests.verdict' <<< "$(_status)")" '^verified$'

usage=$(bash "$ROOT_DIR/bin/craftsman-helper" session 2>&1); usage_code=$?
assert_contains "session without status names its usage" "$usage_code:$usage" "^2:Usage: craftsman-helper session status"

rm -rf "/tmp/craftsman-status-tests-$$"
test_summary
