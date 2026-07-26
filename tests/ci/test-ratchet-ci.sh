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

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
