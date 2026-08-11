#!/usr/bin/env bash
# =============================================================================
# Gate independence tests
#
# The blocking gates (PreToolUse exit 2) must return the same verdict
# whatever the session dials say. Two dials arrive with hook input on
# current Claude Code: permission_mode (auto mode becomes the default on
# Pro/Max/Team on 2026-08-14) and the effort level ($CLAUDE_EFFORT). The
# hooks reference states a PreToolUse deny is evaluated before the
# permission system, so the only way auto mode could soften a gate is a
# hook reading permission_mode and deciding to. These tests pin that door
# shut, and prove the one legitimate effort consumer (the advisory Haiku
# layer) skips at low effort without touching Level 1.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-gate-independence-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
mkdir -p "$CLAUDE_PLUGIN_DATA"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDE_EFFORT

VIOLATION_CONTENT='<?php
namespace App\Domain;
use App\Infrastructure\Doctrine\OrderRepository;
class Order {}'

CLEAN_CONTENT='<?php
declare(strict_types=1);
namespace App\Domain;
final class Money {}'

# pre_hook_exit <content> [permission_mode]
pre_hook_exit() {
    local content="$1" mode="${2:-}"
    local input
    if [[ -n "$mode" ]]; then
        input=$(jq -n --arg fp "/tmp/craftsman-gate-$$/src/Domain/Order.php" \
            --arg c "$content" --arg pm "$mode" \
            '{"tool_input":{"file_path":$fp,"content":$c},"permission_mode":$pm}')
    else
        input=$(jq -n --arg fp "/tmp/craftsman-gate-$$/src/Domain/Order.php" \
            --arg c "$content" \
            '{"tool_input":{"file_path":$fp,"content":$c}}')
    fi
    echo "$input" | bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1
    echo $?
}

echo ""
echo "=== Gate Independence Tests (permission_mode) ==="

# Baseline: without the field, the layer violation blocks.
code=$(pre_hook_exit "$VIOLATION_CONTENT")
if [[ "$code" == "2" ]]; then
    log_pass "baseline: layer violation blocks with no permission_mode field"
else
    log_fail "baseline violation" "expected exit 2, got $code"
fi

# The same verdict must hold under every mode the harness can send.
for mode in default auto bypassPermissions; do
    code=$(pre_hook_exit "$VIOLATION_CONTENT" "$mode")
    if [[ "$code" == "2" ]]; then
        log_pass "layer violation still blocks with permission_mode=$mode"
    else
        log_fail "violation under $mode" "expected exit 2, got $code"
    fi
done

# Counter-test: clean content passes under auto too, or the matrix above
# would also pass with a gate that blocks everything.
code=$(pre_hook_exit "$CLEAN_CONTENT" "auto")
if [[ "$code" == "0" ]]; then
    log_pass "clean content passes with permission_mode=auto"
else
    log_fail "clean under auto" "expected exit 0, got $code"
fi

# config-protection answers the same under auto mode.
code=$(jq -n --arg fp "/tmp/project/phpstan.neon" \
    '{"tool_input":{"file_path":$fp},"permission_mode":"auto"}' \
    | bash "$ROOT_DIR/hooks/config-protection.sh" >/dev/null 2>&1; echo $?)
if [[ "$code" == "2" ]]; then
    log_pass "config-protection still blocks phpstan.neon with permission_mode=auto"
else
    log_fail "config-protection under auto" "expected exit 2, got $code"
fi

# Static guard: no hook script reads permission_mode. The behavioural matrix
# above proves today's verdicts; this line makes a future "soften when auto"
# patch fail loudly instead of shipping quietly. A legitimate reader must
# update this test in the same change.
hits=$(grep -l 'permission_mode' "$ROOT_DIR"/hooks/*.sh "$ROOT_DIR"/hooks/lib/*.sh 2>/dev/null || true)
if [[ -z "$hits" ]]; then
    log_pass "no hook script reads permission_mode"
else
    log_fail "hook reads permission_mode" "$hits"
fi

echo ""
echo "=== Gate Independence Tests (effort) ==="

# Level 1 ignores the effort dial entirely.
code=$(CLAUDE_EFFORT=low bash -c '
    jq -n --arg fp "/tmp/craftsman-gate-$$/src/Domain/Order.php" --arg c "$1" \
        "{\"tool_input\":{\"file_path\":\$fp,\"content\":\$c}}" \
    | bash "$0/hooks/pre-write-check.sh" >/dev/null 2>&1
    echo $?' "$ROOT_DIR" "$VIOLATION_CONTENT")
if [[ "$code" == "2" ]]; then
    log_pass "Level 1 still blocks the violation with CLAUDE_EFFORT=low"
else
    log_fail "Level 1 under low effort" "expected exit 2, got $code"
fi

# The advisory Haiku layer is the one legitimate effort consumer: at low it
# steps aside without spawning a subprocess.
FAKE_BIN="$CLAUDE_PLUGIN_DATA/bin"
MARKER="$CLAUDE_PLUGIN_DATA/haiku-called"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
touch "${FAKE_CLAUDE_MARKER:?}"
echo "CLEAN"
EOF
chmod +x "$FAKE_BIN/claude"

rm -f "$MARKER"
rc_low=$(
    export PATH="$FAKE_BIN:$PATH" FAKE_CLAUDE_MARKER="$MARKER" CLAUDE_EFFORT=low
    source "$ROOT_DIR/hooks/lib/haiku-verify.sh"
    haiku_verify "ping" >/dev/null 2>&1
    echo $?
)
if [[ "$rc_low" == "1" && ! -f "$MARKER" ]]; then
    log_pass "haiku_verify skips at CLAUDE_EFFORT=low (no subprocess spawned)"
else
    log_fail "haiku_verify at low effort" "rc=$rc_low marker=$([[ -f "$MARKER" ]] && echo present || echo absent)"
fi

rm -f "$MARKER"
out_default=$(
    export PATH="$FAKE_BIN:$PATH" FAKE_CLAUDE_MARKER="$MARKER"
    unset CLAUDE_EFFORT
    source "$ROOT_DIR/hooks/lib/haiku-verify.sh"
    haiku_verify "ping" 2>/dev/null
)
if [[ "$out_default" == "CLEAN" && -f "$MARKER" ]]; then
    log_pass "haiku_verify still runs when effort is unset"
else
    log_fail "haiku_verify default path" "out=$out_default marker=$([[ -f "$MARKER" ]] && echo present || echo absent)"
fi

rm -rf "$CLAUDE_PLUGIN_DATA"

test_summary
