#!/usr/bin/env bash
# =============================================================================
# Mjolnir Library Tests
# Tests mjolnir.sh: enabled check, event pools, formatted output
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Mjolnir Library Tests ==="

# Source the library
source "$ROOT_DIR/hooks/lib/mjolnir.sh"

# Test: mjolnir_enabled returns 1 when config says false
echo ""
echo "[mjolnir_enabled]"
CLAUDE_PLUGIN_OPTION_mjolnir="false"
mjolnir_enabled || _rc=$?
assert_exit_code "disabled when config=false" "1" "${_rc:-0}"
unset CLAUDE_PLUGIN_OPTION_mjolnir

# Test: mjolnir_enabled returns 0 by default (default=true)
_rc=0; mjolnir_enabled || _rc=$?
assert_exit_code "enabled by default" "0" "$_rc"

# Test: mjolnir_pick returns non-empty for each event
echo ""
echo "[mjolnir_pick]"
for event in session_start violation_blocked violation_corrected verify_pass verify_fail push_success; do
    result=$(mjolnir_pick "$event")
    if [[ -n "$result" ]]; then
        log_pass "pick $event returns non-empty"
    else
        log_fail "pick $event returns non-empty" "was empty"
    fi
done

# Test: mjolnir_pick returns empty for unknown event
result=$(mjolnir_pick "unknown_event" || true)
if [[ -z "$result" ]]; then
    log_pass "pick unknown event returns empty"
else
    log_fail "pick unknown event returns empty" "got '$result'"
fi

# Test: mjolnir_line formats correctly
echo ""
echo "[mjolnir_line]"
result=$(mjolnir_line "session_start")
if echo "$result" | grep -qE '^⚒ Mjolnir: ".+"$'; then
    log_pass "line format matches pattern"
else
    log_fail "line format matches pattern" "got '$result'"
fi

# Test: mjolnir_line returns empty when disabled
CLAUDE_PLUGIN_OPTION_mjolnir="false"
result=$(mjolnir_line "session_start")
if [[ -z "$result" ]]; then
    log_pass "line empty when disabled"
else
    log_fail "line empty when disabled" "got '$result'"
fi
unset CLAUDE_PLUGIN_OPTION_mjolnir

test_summary
