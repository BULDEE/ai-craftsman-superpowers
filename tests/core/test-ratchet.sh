#!/usr/bin/env bash
# =============================================================================
# Structural ratchet tests (ADR-0025): metric core, baseline lifecycle.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

RATCHET="$ROOT_DIR/hooks/lib/ratchet.py"
WORK="/tmp/craftsman-ratchet-test-$$"
mkdir -p "$WORK"

echo "=== Metric core (measure) ==="

cat > "$WORK/simple.php" <<'PHP'
<?php
declare(strict_types=1);
final class Simple {
    public function greet(string $name): string {
        return "hello " . $name;
    }
}
PHP

OUT=$(python3 "$RATCHET" measure "$WORK/simple.php")
if echo "$OUT" | jq -e '.complexity == 0 and .fan_out == 0 and .ignores == 0' >/dev/null 2>&1; then
    log_pass "simple file: zero complexity, zero fan-out, zero ignores"
else
    log_fail "simple measure" "$OUT"
fi

cat > "$WORK/complex.php" <<'PHP'
<?php
use App\Infrastructure\Db;
use App\Domain\User;

final class Complex {
    public function decide(int $value): string {
        if ($value > 10) {
            foreach ([1, 2] as $item) {
                if ($item && $value) {
                    while ($value > 0) { $value--; }
                }
            }
        } elseif ($value < 0) {
            return "neg"; // craftsman-ignore: PHP004
        }
        return "ok";
    }
}
PHP

OUT=$(python3 "$RATCHET" measure "$WORK/complex.php")
if echo "$OUT" | jq -e '.complexity >= 5 and .fan_out == 2 and .ignores == 1' >/dev/null 2>&1; then
    log_pass "complex file: branches+nesting counted, 2 imports, 1 ignore"
else
    log_fail "complex measure" "$OUT"
fi

if echo "$OUT" | jq -e '.file_lines > 10 and .max_fn_lines >= 10' >/dev/null 2>&1; then
    log_pass "line metrics populated"
else
    log_fail "line metrics" "$OUT"
fi

OUT=$(python3 "$RATCHET" measure "$WORK/nope.bin" 2>/dev/null || true)
if [[ -z "$OUT" ]]; then
    log_pass "unsupported extension: silent empty (caller skips)"
else
    log_fail "unsupported ext" "$OUT"
fi

rm -rf "$WORK"

echo ""
echo "=== Baseline lifecycle ==="

WORK2="/tmp/craftsman-ratchet-base-$$"
mkdir -p "$WORK2/src"
BASE="$WORK2/.craftsman-baseline.json"
cd "$WORK2"

cat > src/app.php <<'PHP'
<?php
final class App {
    public function run(int $count): int {
        if ($count > 0) { return $count; }
        return 0;
    }
}
PHP

python3 "$RATCHET" init src --baseline "$BASE" >/dev/null
if [[ -f "$BASE" ]] && grep -q '"src/app.php"' "$BASE"; then
    log_pass "init writes baseline with relative sorted paths"
else
    log_fail "init" "$(cat "$BASE" 2>/dev/null)"
fi

EXIT_CODE=0
python3 "$RATCHET" check src/app.php --baseline "$BASE" >/dev/null || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "unchanged file passes check"
else
    log_fail "unchanged check" "exit $EXIT_CODE"
fi

# Regress: add branches
cat > src/app.php <<'PHP'
<?php
final class App {
    public function run(int $count): int {
        if ($count > 0) {
            if ($count > 5) {
                for ($idx = 0; $idx < $count; $idx++) {
                    if ($idx % 2 && $count) { $count--; }
                }
            }
        }
        return 0;
    }
}
PHP

EXIT_CODE=0
OUT=$(python3 "$RATCHET" check src/app.php --baseline "$BASE") || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUT" | grep -q "RATCHET001 complexity"; then
    log_pass "regression detected: exit 1 with RATCHET001 metric line"
else
    log_fail "regression" "exit=$EXIT_CODE out=$OUT"
fi

# Improve below original: update tightens
cat > src/app.php <<'PHP'
<?php
final class App {
    public function run(int $count): int {
        return max($count, 0);
    }
}
PHP
python3 "$RATCHET" update src/app.php --baseline "$BASE" >/dev/null
NEW_CPLX=$(grep '"src/app.php"' "$BASE" | jq -r '.complexity')
if [[ "$NEW_CPLX" == "0" ]]; then
    log_pass "green improvement tightens the high-water mark"
else
    log_fail "tighten" "complexity=$NEW_CPLX"
fi

# Update must NEVER loosen
cat > src/app.php <<'PHP'
<?php
final class App {
    public function run(int $count): int {
        if ($count > 0) { if ($count > 5) { return 1; } }
        return 0;
    }
}
PHP
python3 "$RATCHET" update src/app.php --baseline "$BASE" >/dev/null
STILL=$(grep '"src/app.php"' "$BASE" | jq -r '.complexity')
if [[ "$STILL" == "0" ]]; then
    log_pass "update never loosens (one-way ratchet)"
else
    log_fail "one-way" "complexity=$STILL"
fi

# New file: check adds baseline entry (born clean)
cat > src/fresh.php <<'PHP'
<?php
final class Fresh {}
PHP
python3 "$RATCHET" check src/fresh.php --baseline "$BASE" >/dev/null
if grep -q '"src/fresh.php"' "$BASE"; then
    log_pass "new file gets a baseline entry at first check"
else
    log_fail "new file" "no entry created"
fi

cd "$ROOT_DIR"
rm -rf "$WORK2"

test_summary
