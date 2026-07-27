#!/usr/bin/env bash
# =============================================================================
# Ratchet CI parity (ADR-0025): craftsman-ci blocks the same structural
# regression as the real-time hook, using the same library.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="/tmp/craftsman-ratchet-ci-$$"
mkdir -p "$WORK/src"
PREV_PWD="$PWD"
cd "$WORK"

cat > .craft-config.yml <<'YAML'
v: 4
strictness: strict
stack: symfony
rules:
  RATCHET001: block
YAML

cat > src/Ok.php <<'PHP'
<?php
declare(strict_types=1);
final class Ok {
    private function __construct() {}
    public static function create(): self { return new self(); }
}
PHP

python3 "$ROOT_DIR/hooks/lib/ratchet.py" init src --baseline .craftsman-baseline.json >/dev/null

EXIT_CODE=0
bash "$ROOT_DIR/ci/craftsman-ci.sh" src/ >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "clean file passes CI with a baseline present"
else
    log_fail "clean CI run" "expected exit 0, got $EXIT_CODE"
fi

cat > src/Ok.php <<'PHP'
<?php
declare(strict_types=1);
final class Ok {
    private function __construct() {}
    public static function create(): self { return new self(); }
    public function grow(int $value): int {
        if ($value) { if ($value > 1) { if ($value > 2) { return 2; } } }
        return 0;
    }
}
PHP

EXIT_CODE=0
OUT=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" src/ 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]] && echo "$OUT" | grep -q "RATCHET001"; then
    log_pass "CI blocks the same structural regression as the hook"
else
    log_fail "ci ratchet" "exit=$EXIT_CODE $(echo "$OUT" | grep -i ratchet | head -2)"
fi

# CI must never write the baseline (pipeline is read-only)
BEFORE=$(shasum .craftsman-baseline.json | cut -d' ' -f1)
bash "$ROOT_DIR/ci/craftsman-ci.sh" src/ >/dev/null 2>&1 || true
AFTER=$(shasum .craftsman-baseline.json | cut -d' ' -f1)
if [[ "$BEFORE" == "$AFTER" ]]; then
    log_pass "CI never mutates the committed baseline"
else
    log_fail "ci read-only" "baseline changed during a CI run"
fi

# =============================================================================
# The hook and CI must agree on all three severities, not just on "block".
#
# CI resolved a boolean and put everything that was not "block" into warnings,
# so a directory that had switched a rule off still had every finding printed
# in the pipeline while the hook stayed silent on the same file. And CI walked
# the directory tree from a relative path, where dirname of "." is "." and the
# walk never ended: the gate hung instead of reporting.
# =============================================================================
echo ""
echo "=== The pipeline agrees with the hook on ignore, warn and block ==="

hook_reports_ratchet() {
    local out
    out=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$WORK/src/Ok.php" \
        | CLAUDE_PLUGIN_ROOT="$ROOT_DIR" timeout 30 bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1)
    printf '%s' "$out" | grep -c "RATCHET001" || true
}

ci_run() {
    local out code=0
    out=$(timeout 60 bash "$ROOT_DIR/ci/craftsman-ci.sh" src/ 2>&1) || code=$?
    printf '%s|%s' "$code" "$(printf '%s' "$out" | grep -c 'RATCHET001' || true)"
}

for severity in ignore warn block; do
    printf 'rules:\n  RATCHET001: %s\n' "$severity" > src/.craft-rules.yml

    CI_RESULT=$(ci_run)
    CI_CODE="${CI_RESULT%%|*}"
    CI_LINES="${CI_RESULT##*|}"
    HOOK_LINES=$(hook_reports_ratchet)

    if [[ "$CI_CODE" == "124" ]]; then
        log_fail "CI hangs on RATCHET001: $severity" \
            "the gate never returned: the directory walk does not terminate"
        continue
    fi

    case "$severity" in
        ignore)
            if [[ "$CI_LINES" -eq 0 && "$HOOK_LINES" -eq 0 && "$CI_CODE" -eq 0 ]]; then
                log_pass "ignore: both stay silent"
            else
                log_fail "ignore parity" "ci exit=$CI_CODE lines=$CI_LINES, hook lines=$HOOK_LINES"
            fi
            ;;
        warn)
            if [[ "$CI_LINES" -gt 0 && "$HOOK_LINES" -gt 0 && "$CI_CODE" -eq 1 ]]; then
                log_pass "warn: both report, the pipeline does not fail the build"
            else
                log_fail "warn parity" "ci exit=$CI_CODE lines=$CI_LINES, hook lines=$HOOK_LINES"
            fi
            ;;
        block)
            if [[ "$CI_LINES" -gt 0 && "$HOOK_LINES" -gt 0 && "$CI_CODE" -eq 2 ]]; then
                log_pass "block: both report and the pipeline fails"
            else
                log_fail "block parity" "ci exit=$CI_CODE lines=$CI_LINES, hook lines=$HOOK_LINES"
            fi
            ;;
    esac
done

rm -f src/.craft-rules.yml

# Invoked from a subdirectory, CI must resolve overrides the way the hook does.
#
# Both stop the walk at the project root: an override above it is out of scope
# for the hook and for CI alike, verified by running the hook in the same
# layout. What has to work is an override between the working directory and the
# file, which a relative walk gets right only by accident. The path is
# normalised to absolute before the walk so the walk and its cache keys are
# defined by the directory, not by how the caller spelled it.
echo ""
echo "=== Invoked from a subdirectory, CI honours an override under it ==="

SUB="$WORK/sub"
mkdir -p "$SUB/deep"
printf 'v: 4\nstrictness: strict\nstack: symfony\nrules:\n  RATCHET001: block\n' > "$SUB/.craft-config.yml"
cat > "$SUB/deep/Deep.php" <<'PHP'
<?php
declare(strict_types=1);
final class Deep {
    private function __construct() {}
}
PHP
( cd "$SUB" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" init deep --baseline .craftsman-baseline.json >/dev/null 2>&1 )
cat > "$SUB/deep/Deep.php" <<'PHP'
<?php
declare(strict_types=1);
final class Deep {
    private function __construct() {}
    public function grow(int $v): int {
        if ($v) { if ($v > 1) { if ($v > 2) { return 2; } } }
        return 0;
    }
}
PHP

# Positive control first. Without it, "the override silenced it" is satisfied
# by a run that never performed the ratchet check at all, which is what happens
# when the baseline is not where CI looks for it.
BASE_CODE=0
BASE_OUT=$(cd "$SUB" && timeout 60 bash "$ROOT_DIR/ci/craftsman-ci.sh" deep/Deep.php 2>&1) || BASE_CODE=$?
if [[ "$BASE_CODE" == "124" ]]; then
    log_fail "CI hangs when invoked from a subdirectory" "the gate never returned"
elif printf '%s' "$BASE_OUT" | grep -q "RATCHET001"; then
    log_pass "from a subdirectory, CI reports the regression with no override present"

    printf 'rules:\n  RATCHET001: ignore\n' > "$SUB/deep/.craft-rules.yml"
    OVER_CODE=0
    OVER_OUT=$(cd "$SUB" && timeout 60 bash "$ROOT_DIR/ci/craftsman-ci.sh" deep/Deep.php 2>&1) || OVER_CODE=$?
    if [[ "$OVER_CODE" == "124" ]]; then
        log_fail "CI hangs with a directory override" "the gate never returned"
    elif ! printf '%s' "$OVER_OUT" | grep -q "RATCHET001"; then
        log_pass "an override in the file's own directory is honoured from a subdirectory"
    else
        log_fail "override ignored" "CI still reported RATCHET001 (exit=$OVER_CODE)"
    fi
else
    log_fail "no regression reported from the subdirectory" \
        "the override assertion would pass without the ratchet ever running (exit=$BASE_CODE)"
fi

rm -rf "$SUB"

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
