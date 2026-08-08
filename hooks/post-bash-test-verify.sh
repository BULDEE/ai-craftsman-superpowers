#!/usr/bin/env bash
# =============================================================================
# Post-Bash Test Auto-Verify Hook
# Auto-sets verified=true when test suite passes (exit 0).
#
# TRIGGERS: PostToolUse for Bash
# EXIT CODES: 0 = always pass (informational only)
# =============================================================================
set -uo pipefail

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "post-bash-test-verify" "standard,strict" || exit 0

INPUT=$(cat)

# Only care about successful Bash commands
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "1"' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Which commands run a test suite is the packs' knowledge. The literal list
# this replaces meant the deterministic verification loop (ADR-0023) was blind
# to every language whose runner it had not been taught, so `flutter test`
# failing left the session's "verified" flag standing.
#
# run-tests.sh stays here because it is this plugin's own runner, not any
# language's: it belongs to the engine, and no pack should have to claim it.
_test_command_pattern() {
    local pattern="run-tests\\.sh" command
    while IFS= read -r command; do
        [[ -z "$command" ]] && continue
        # Commands become part of a regex, and manifests are repository-supplied
        # data. Accept a conservative charset and escape the rest.
        [[ ! "$command" =~ ^[A-Za-z0-9_./\ -]+$ ]] && continue
        pattern="${pattern}|$(printf '%s' "$command" | sed 's/[.]/\\./g')"
    done <<< "$(lang_all_capability test_commands 2>/dev/null)"
    printf '(%s)' "$pattern"
}

source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
pack_loader_init

if ! echo "$COMMAND" | grep -qE "$(_test_command_pattern)"; then
    exit 0
fi

_BRIDGE_FILE="${HOME}/.claude/craftsman-session-state-path"
if [[ -f "$_BRIDGE_FILE" ]]; then
    SESSION_STATE=$(< "$_BRIDGE_FILE")
else
    SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"
fi

LIB_DIR="${SCRIPT_DIR}/lib"
CURRENT=$(python3 "$LIB_DIR/session_state.py" check-flag "$SESSION_STATE" verified 2>/dev/null || echo "false")

# Failing test run (ADR-0023): revoke verification evidence, feed the failure
# log to the background monitor, and wake the session (exit 2 + asyncRewake)
# only on a regression - the suite was green earlier in this session.
if [[ "$EXIT_CODE" != "0" ]]; then
    DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
    mkdir -p "$DATA_DIR" 2>/dev/null || true
    printf '%s test failure: %s (exit %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMMAND" "$EXIT_CODE" \
        >> "${DATA_DIR}/test-failures.log" 2>/dev/null || true
    if [[ "$CURRENT" == "true" ]]; then
        python3 "$LIB_DIR/session_state.py" merge "$SESSION_STATE" verified false 2>/dev/null || true
        echo "Test suite REGRESSED: '${COMMAND}' now exits ${EXIT_CODE} but was green earlier this session. Verification evidence revoked - fix the suite before claiming completion or pushing." >&2
        exit 2
    fi
    exit 0
fi

# Passing test run: set verified (skip if already set)
[[ "$CURRENT" == "true" ]] && exit 0
python3 "$LIB_DIR/session_state.py" set-verified 2>/dev/null

exit 0
