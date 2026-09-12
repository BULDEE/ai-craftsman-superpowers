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

# --- The one hook that DOES behave differently by mode, and why that is not a
# gate softened by a dial.
#
# agent-ddd-verifier.sh is a PostToolUse hook. Its exit 2 cannot block a write,
# because the tool has already run; it shows the finding to the model. So it is
# advisory by construction, and skipping its paid subprocess in plan mode, where
# the harness will not create the file, is a decision about cost on an advisory
# layer. It is NOT the premise of this file, which is a PreToolUse deny being
# evaluated before the permission system.
#
# The difference is pinned here rather than argued: with a stubbed verifier
# returning a violation, `default` must exit 2 and `plan` must exit 0 having
# made zero subprocess calls. If someone later makes the verifier a PreToolUse
# gate, the first assertion is the one that has to change, on purpose.
VERIFY_STUB_DIR="$CLAUDE_PLUGIN_DATA/stub-bin"
mkdir -p "$VERIFY_STUB_DIR" "$CLAUDE_PLUGIN_DATA/repo/src/Domain"
cat > "$VERIFY_STUB_DIR/claude" <<'STUB'
#!/bin/sh
echo "called" >> "$CLAUDE_STUB_LOG"
echo "DDD_VIOLATIONS
src/Domain/Order.php:3 Layer violation - Domain imports Infrastructure"
STUB
chmod +x "$VERIFY_STUB_DIR/claude"
printf '%s\n' "$VIOLATION_CONTENT" > "$CLAUDE_PLUGIN_DATA/repo/src/Domain/Order.php"
( cd "$CLAUDE_PLUGIN_DATA/repo" && git init -q && git add -A ) >/dev/null 2>&1

verifier_exit() {
    local mode="$1"
    export CLAUDE_STUB_LOG="$CLAUDE_PLUGIN_DATA/stub-calls-$mode"
    : > "$CLAUDE_STUB_LOG"
    ( cd "$CLAUDE_PLUGIN_DATA/repo" && jq -n --arg fp "src/Domain/Order.php" --arg pm "$mode" \
        '{"tool_name":"Write","tool_input":{"file_path":$fp},"permission_mode":$pm}' \
        | env -u CLAUDE_EFFORT -u CRAFTSMAN_HEADLESS_VERIFY PATH="$VERIFY_STUB_DIR:$PATH" \
              HOME="$CLAUDE_PLUGIN_DATA/home" \
          bash "$ROOT_DIR/hooks/agent-ddd-verifier.sh" >/dev/null 2>&1 )
    echo $?
}
mkdir -p "$CLAUDE_PLUGIN_DATA/home/.claude"

code=$(verifier_exit default)
calls=$(awk 'END { print NR }' "$CLAUDE_PLUGIN_DATA/stub-calls-default")
if [[ "$code" == "2" && "${calls:-0}" -ge 1 ]]; then
    log_pass "verifier in default: reports the violation (exit 2, $calls call)"
else
    log_fail "verifier in default reports the violation" "exit $code, $calls call(s)"
fi

code=$(verifier_exit plan)
calls=$(awk 'END { print NR }' "$CLAUDE_PLUGIN_DATA/stub-calls-plan")
if [[ "$code" == "0" && "${calls:-0}" -eq 0 ]]; then
    log_pass "verifier in plan: advisory layer steps aside (exit 0, zero calls), by decision"
else
    log_fail "verifier in plan steps aside by decision" "exit $code, $calls call(s)"
fi

# --- Static guard: only the enumerated readers touch permission_mode, and no
# reader branches an exit code near it.
#
# The original line forbade reading the field at all and said a legitimate
# reader must update this test in the same change. That happened: plan mode
# is a mode where the harness does not execute the Write, so recording a
# violation there files a finding against a file that was never written. The
# matrix above still proves the PreToolUse verdict is identical in every mode.
#
# The first version of this guard grepped for `exit 2` on the same line as the
# mode reference, and was blind to the shape actually present in the change
# it guarded: `|| exit 0` two lines under the read. It looks at a window now,
# and any exit code inside it is a finding, because the behavioural assertions
# above are what decide whether that exit is legitimate, never this grep.
PERMISSION_MODE_READERS="hooks/lib/permission-mode.sh hooks/post-write-check.sh hooks/agent-ddd-verifier.sh hooks/agent-final-review.sh"

unexpected=""
while IFS= read -r hook; do
    [[ -z "$hook" ]] && continue
    relative="${hook#"$ROOT_DIR"/}"
    case " $PERMISSION_MODE_READERS " in
        *" $relative "*) continue ;;
    esac
    unexpected="${unexpected}${relative} "
done <<< "$(grep -l 'permission_mode\|PERMISSION_MODE' "$ROOT_DIR"/hooks/*.sh "$ROOT_DIR"/hooks/lib/*.sh 2>/dev/null || true)"

if [[ -z "${unexpected// /}" ]]; then
    log_pass "only the enumerated hooks read permission_mode"
else
    log_fail "only the enumerated hooks read permission_mode" \
        "undeclared reader(s): $unexpected"
fi

# The window: the line that mentions the mode and its immediate neighbours. An
# exit inside it is reported by file and line, so a reviewer sees the shape
# and decides, rather than a grep deciding for them. Wider than one line and
# the guard fired on `$HAS_PYTHON3 || return 0` three lines away, which is the
# other way a static guard dies: crying wolf until somebody deletes it. The
# behavioural assertions above are the real guard; this one only makes a new
# shape visible.
EXPECTED_MODE_EXITS="hooks/agent-ddd-verifier.sh:hook_mode_runs_verification"
for reader in $PERMISSION_MODE_READERS; do
    hits=$(awk '
        /permission_mode|PERMISSION_MODE|hook_mode_/ { for (i = NR - 1; i <= NR + 1; i++) window[i] = 1 }
        { line[NR] = $0 }
        END {
            for (n = 1; n <= NR; n++)
                if (window[n] && line[n] ~ /(^|[^a-zA-Z_])(exit|return)[[:space:]]+[0-9]/)
                    print n ": " line[n]
        }' "$ROOT_DIR/$reader")
    if [[ -z "$hits" ]]; then
        log_pass "$reader: no exit code beside a mode reference"
        continue
    fi
    # An expected one carries the helper name on the same line, which is the
    # shape of a decision taken through the helper rather than around it.
    unexpected_hits=$(printf '%s\n' "$hits" | grep -v 'hook_mode_runs_verification\|hook_mode_records_metrics' || true)
    if [[ -z "$unexpected_hits" ]]; then
        log_pass "$reader: the only exit near the mode goes through the helper (pinned above)"
    else
        log_fail "$reader branches an exit code on the mode" "$unexpected_hits"
    fi
done

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
