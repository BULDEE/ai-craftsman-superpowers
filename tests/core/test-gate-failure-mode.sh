#!/usr/bin/env bash
# =============================================================================
# CR-220: a write gate that cannot answer refuses the write.
#
# pre-write-check.sh and config-protection.sh already turn an ERR into exit 2.
# What their trap cannot see is the host side: a hook that times out, is
# killed, or does not start. Claude Code 2.1.295 added `onFailure: "block"`
# for that case; without it, "on most events, when a hook fails or times out,
# Claude Code still carries out the action" (hooks documentation).
# pre-push-verify.sh is advisory by design and stays fail-open.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

HOOKS="$ROOT_DIR/hooks/hooks.json"
_on_failure() {
    jq -r --arg f "$1" '[.hooks.PreToolUse[].hooks[] | select(.command | contains($f)) | .onFailure // "continue"] | unique | join(",")' "$HOOKS"
}

echo ""
echo "--- write gates fail closed on the host side ---"

for gate in pre-write-check.sh config-protection.sh; do
    MODE=$(_on_failure "$gate")
    if [[ "$MODE" == "block" ]]; then
        log_pass "$gate: a timeout or a hook that cannot start refuses the write (onFailure: block)"
    else
        log_fail "$gate fails open on the host side" "onFailure=${MODE:-absent}"
    fi
done

MODE=$(_on_failure pre-push-verify.sh)
if [[ "$MODE" == "continue" ]]; then
    log_pass "pre-push-verify.sh stays advisory: a crash there never blocks a push"
else
    log_fail "pre-push-verify.sh became blocking" "onFailure=$MODE"
fi

test_summary
