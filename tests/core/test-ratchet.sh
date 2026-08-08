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

# A scoped init re-photographs what it was given and leaves the rest alone.
# It used to start from an empty dict, so `init one/file.sh` silently deleted
# every other row: on this project that turned a 146-row baseline into a
# 1-row one, erasing the whole debt record with no warning and no diff to
# review before the next commit.
mkdir -p other
cat > other/keep.php <<'PHP'
<?php
final class Keep {
    public function value(): int { return 1; }
}
PHP
python3 "$RATCHET" init . --baseline "$BASE" >/dev/null
ROWS_BEFORE=$(grep -c '^{' "$BASE")
python3 "$RATCHET" init src/app.php --baseline "$BASE" >/dev/null
ROWS_AFTER=$(grep -c '^{' "$BASE")

if [[ "$ROWS_AFTER" -eq "$ROWS_BEFORE" ]] && grep -q '"other/keep.php"' "$BASE"; then
    log_pass "scoped init keeps the rows it was not asked about"
else
    log_fail "scoped init" "baseline went from $ROWS_BEFORE to $ROWS_AFTER rows"
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

echo ""
echo "=== Gate integration (post-write-check) ==="

WORK3="/tmp/craftsman-ratchet-gate-$$"
mkdir -p "$WORK3/src"
PREV_PWD="$PWD"
cd "$WORK3"
git init -q .
cat > .craft-config.yml <<'YAML'
v: 4
strictness: strict
stack: symfony
YAML

cat > src/Gate.php <<'PHP'
<?php
declare(strict_types=1);
final class Gate {
    private function __construct() {}
    public static function create(): self { return new self(); }
}
PHP
python3 "$RATCHET" init src --baseline .craftsman-baseline.json >/dev/null

cat > src/Gate.php <<'PHP'
<?php
declare(strict_types=1);
final class Gate {
    private function __construct() {}
    public static function create(): self { return new self(); }
    public function tangle(int $value): int {
        if ($value) { if ($value > 1) { if ($value > 2) { return 3; } } }
        return 0;
    }
}
PHP

# Default: advisory even in strict mode, while the metric core is validated
EXIT_CODE=0
OUT=$(echo "{\"tool_input\":{\"file_path\":\"$WORK3/src/Gate.php\"}}" | \
    CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]] && echo "$OUT" | grep -q "RATCHET001"; then
    log_pass "default: regression warns without blocking (advisory period)"
else
    log_fail "advisory default" "exit=$EXIT_CODE out=$(echo "$OUT" | head -4)"
fi

# Explicit opt-in: RATCHET001: block makes it a hard gate
cat > .craft-config.yml <<'YAML'
v: 4
strictness: strict
stack: symfony
rules:
  RATCHET001: block
YAML
EXIT_CODE=0
OUT=$(echo "{\"tool_input\":{\"file_path\":\"$WORK3/src/Gate.php\"}}" | \
    CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]] && echo "$OUT" | grep -q "RATCHET001"; then
    log_pass "explicit opt-in: RATCHET001 block stops the regression"
else
    log_fail "gate block" "exit=$EXIT_CODE out=$(echo "$OUT" | head -4)"
fi

echo ""
echo "=== Guided mode ==="

cat > .craft-config.yml <<'YAML'
v: 4
strictness: strict
stack: symfony
guided: true
YAML

mkdir -p src/Domain
cat > src/Domain/G.php <<'PHP'
<?php
declare(strict_types=1);
namespace App\Domain;
final class G {
    public function bad(): array {
        return $this->db->executeQuery("SELECT name FROM users");
    }
}
PHP
EXIT_CODE=0
OUT=$(echo "{\"tool_input\":{\"file_path\":\"$WORK3/src/Domain/G.php\"}}" | \
    CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 2 ]] && echo "$OUT" | grep -q "Why this matters:"; then
    log_pass "guided mode: block message teaches in plain language"
else
    log_fail "guided message" "exit=$EXIT_CODE $(echo "$OUT" | tail -4)"
fi

cd "$PREV_PWD"
rm -rf "$WORK3"

echo ""
echo "=== Project boundary ==="

WORK6="/tmp/craftsman-ratchet-boundary-$$"
OUTSIDE="/tmp/craftsman-ratchet-outside-$$"
mkdir -p "$WORK6/src" "$OUTSIDE"
PREV_PWD="$PWD"
cd "$WORK6"

cat > src/In.php <<'PHP'
<?php
final class In {}
PHP
cat > "$OUTSIDE/Out.php" <<'PHP'
<?php
final class Out {}
PHP

python3 "$RATCHET" init src --baseline .craftsman-baseline.json >/dev/null
python3 "$RATCHET" check "$OUTSIDE/Out.php" --baseline .craftsman-baseline.json >/dev/null 2>&1
python3 "$RATCHET" update "$OUTSIDE/Out.php" --baseline .craftsman-baseline.json >/dev/null 2>&1

if ! grep -q "craftsman-ratchet-outside" .craftsman-baseline.json; then
    log_pass "file outside the project never enters the baseline"
else
    log_fail "project boundary" "absolute outside path leaked into the committed baseline"
fi

if ! grep -qE '"path":"/' .craftsman-baseline.json; then
    log_pass "baseline holds only project-relative paths"
else
    log_fail "absolute path" "$(grep -oE '"path":"[^"]*"' .craftsman-baseline.json | head -2)"
fi

cd "$PREV_PWD"
rm -rf "$WORK6" "$OUTSIDE"

# =============================================================================
# A span ends where the function ends, not where the next one starts
# =============================================================================
echo ""
echo "=== Function spans stop at the body ==="

# Spans used to run header-to-header, so every line between two functions was
# charged to the earlier one. In a sequential test script that is the whole
# file: a 7-line helper measured 600 lines and 119 decision points, which reads
# as debt and invites a refactor that fixes nothing.
SPAN_DIR="/tmp/craftsman-ratchet-span-$$"
mkdir -p "$SPAN_DIR"
cat > "$SPAN_DIR/sequential.sh" <<'SEQ'
#!/usr/bin/env bash
helper() {
    echo "three"
    echo "lines"
}

# 20 lines of top-level script follow, belonging to no function.
for i in 1 2 3; do
    if [[ "$i" == "2" ]]; then
        echo "two"
    elif [[ "$i" == "3" ]]; then
        echo "three"
    fi
done
while read -r line; do
    case "$line" in
        a) echo a ;;
        b) echo b ;;
    esac
done < /dev/null
SEQ

SEQ_MAX=$(python3 "$RATCHET" measure "$SPAN_DIR/sequential.sh" 2>/dev/null \
    | grep -oE '"max_fn_lines":[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
if [[ -n "$SEQ_MAX" && "$SEQ_MAX" -le 6 ]]; then
    log_pass "a short helper followed by top-level code measures its own body (${SEQ_MAX} lines)"
else
    log_fail "function span leaks into top-level code" \
        "max_fn_lines=${SEQ_MAX:-unset}, expected the helper's own 4 lines, not the rest of the file"
fi
rm -rf "$SPAN_DIR"

# =============================================================================
# Loosening a budget requires a stated reason
# =============================================================================
echo ""
echo "=== init --reason ==="

WORK7="/tmp/craftsman-ratchet-reason-$$"
mkdir -p "$WORK7/src"
PREV_PWD="$PWD"
cd "$WORK7"
printf '#!/usr/bin/env bash\nset -u\nfoo() { echo a; }\n' > src/s.sh

# Directory and bare forms are adoption and --repair, not a loosening. Three
# suites already call `init .`, `init src` and `init deep`.
python3 "$RATCHET" init src --baseline b.json >/dev/null 2>&1
dir_rc=$?
if [[ $dir_rc -eq 0 ]]; then
    log_pass "control: photographing a directory needs no reason"
else
    log_fail "init on a directory was refused" "exit $dir_rc - the assertions below are undetermined"
fi

python3 "$RATCHET" init src/s.sh --baseline b.json >/dev/null 2>&1
file_rc=$?
if [[ $file_rc -eq 2 ]]; then
    log_pass "re-photographing one file without --reason is refused"
else
    log_fail "silent loosening allowed" \
        "exit $file_rc - a budget can be raised leaving only numbers in the diff"
fi

python3 "$RATCHET" init src/s.sh --baseline b.json --reason "seam work" >/dev/null 2>&1
if grep -q '"reason":"seam work"' b.json 2>/dev/null; then
    log_pass "the stated reason is persisted in the entry"
else
    log_fail "reason not recorded" "$(grep -o '"path":"src/s.sh"[^}]*' b.json 2>/dev/null | head -1)"
fi

# A later tightening rebuilds the entry from the measurement, which dropped the
# reason and left the raised figure unexplained.
python3 "$RATCHET" update src/s.sh --baseline b.json >/dev/null 2>&1
if grep -q '"reason":"seam work"' b.json 2>/dev/null; then
    log_pass "the reason survives a subsequent update"
else
    log_fail "reason lost on update" "the record of why a budget was raised is gone"
fi

cd "$PREV_PWD"
rm -rf "$WORK7"

test_summary
