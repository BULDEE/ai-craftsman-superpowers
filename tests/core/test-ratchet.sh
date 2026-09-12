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

# --- A row carries more than this command owns ---------------------------------
#
# `rules`, written into the same row by rule_baseline.py, was erased by the
# next `init` and by the next `update`, because both rebuilt the row from their
# own measurement and copied back only the keys they knew about. The symptom
# was the worst kind: a gate that quietly started refusing inherited debt again
# weeks after someone recorded it, with nothing in the diff to explain why.
#
# The same shape had already cost `reason` once. So the assertion is not "keep
# rules", it is "keep whatever you did not measure".
KEEP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ratchet-keep.XXXXXX")"
trap 'rm -rf "$KEEP_WORK"' EXIT

cat > "$KEEP_WORK/sample.sh" <<'SRC'
#!/usr/bin/env bash
run() {
    echo one
}
SRC

( cd "$KEEP_WORK" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" init sample.sh \
    --reason "a reason worth keeping" >/dev/null 2>&1 )

python3 - "$KEEP_WORK/.craftsman-baseline.json" <<'PY_SRC'
import json, sys
path = sys.argv[1]
rows = json.loads(open(path).read())
for row in rows:
    row["rules"] = {"SH001": 2}
    row["invented_by_someone_else"] = "still here"
open(path, "w").write("[\n" + ",\n".join(
    json.dumps(r, separators=(",", ":"), sort_keys=True) for r in rows) + "\n]\n")
PY_SRC

( cd "$KEEP_WORK" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" update sample.sh >/dev/null 2>&1 )
( cd "$KEEP_WORK" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" init sample.sh \
    --reason "a second mark" >/dev/null 2>&1 )

kept="$(python3 -c "
import json, sys
rows = json.loads(open(sys.argv[1]).read())
row = rows[0]
print('%s|%s|%s' % (row.get('rules'), row.get('invented_by_someone_else'), row.get('reason')))
" "$KEEP_WORK/.craftsman-baseline.json" 2>/dev/null)"

assert_contains "update and init keep the rule counts they did not measure" \
    "$kept" "SH001"
assert_contains "and any other key a future writer added" \
    "$kept" "still here"
assert_contains "and the reason, which cost this lesson once already" \
    "$kept" "a second mark"

# --- A metric must not move when prose moves -----------------------------------
#
# BRANCH_RE matched a control keyword anywhere on a line, so
# `logger.info("retrying if the lock is free")` carried two decision points.
# RATCHET001 refuses a file whose complexity rose above its mark, which made
# rewording a log message able to fail a build; and the other direction is
# worse, because a reworded message could LOWER the number, `update` would
# write that as the new mark, and a real branch added later would fit under a
# budget nobody earned.
LITERALS="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-literals.XXXXXX")"

_complexity_of() {
    python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure "$1" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["complexity"])' 2>/dev/null
}

cat > "$LITERALS/pricing.py" <<'PYSRC'
def price(tier, qty):
    if tier == "a":
        return qty
    logger.info("%s x %s for tier %s")
    return 0
PYSRC
before_reword=$(_complexity_of "$LITERALS/pricing.py")

cat > "$LITERALS/pricing.py" <<'PYSRC'
def price(tier, qty):
    if tier == "a":
        return qty
    logger.info("%s x %s tier %s")
    return 0
PYSRC
after_reword=$(_complexity_of "$LITERALS/pricing.py")

if [[ "$before_reword" == "$after_reword" && "$before_reword" == "1" ]]; then
    log_pass "rewording a log message does not move complexity (both $before_reword)"
else
    log_fail "rewording a log message does not move complexity" \
        "was $before_reword, became $after_reword"
fi

# The other direction, which is the one that corrupts a mark: a keyword ADDED
# inside a string must not raise the number either.
cat > "$LITERALS/prose.py" <<'PYSRC'
def send(message):
    logger.info("retrying")
    return message
PYSRC
quiet=$(_complexity_of "$LITERALS/prose.py")
cat > "$LITERALS/prose.py" <<'PYSRC'
def send(message):
    logger.info("retrying if the lock is free, for each waiter, while idle")
    return message
PYSRC
wordy=$(_complexity_of "$LITERALS/prose.py")
if [[ "$quiet" == "$wordy" ]]; then
    log_pass "keywords added inside a string do not raise complexity (both $quiet)"
else
    log_fail "keywords added inside a string do not raise complexity" \
        "$quiet became $wordy, so prose can fail a RATCHET001 build"
fi

# A real branch still counts, or the blanker would have bought silence instead
# of truth.
cat > "$LITERALS/real.py" <<'PYSRC'
def send(message):
    logger.info("retrying")
    if message:
        return 1
    return 0
PYSRC
real=$(_complexity_of "$LITERALS/real.py")
if [[ "$real" -gt "$quiet" ]]; then
    log_pass "a real branch still counts ($quiet without, $real with)"
else
    log_fail "a real branch still counts" "$quiet without, $real with"
fi

# Each dialect has a shape the C-like blanker alone would get wrong: a Python
# docstring, a TypeScript private field, a Rust lifetime, a PHP hash comment.
cat > "$LITERALS/doc.py" <<'PYSRC'
def g():
    """if for while in a docstring"""
    return 1
PYSRC
cat > "$LITERALS/priv.ts" <<'TSSRC'
class A {
  // if for while
  private label = `if for ${y} while`;
  #secret = 1;
  go(a: number) { if (a) { return 1 } return 0 }
}
TSSRC
printf 'fn pick<%s>(s: &%s str) -> usize {\n    if s.is_empty() { 0 } else { 1 }\n}\n' "'a" "'a" > "$LITERALS/life.rs"
cat > "$LITERALS/hash.php" <<'PHPSRC'
<?php
# if for while
class A {
  public function go($a) { if ($a) { return 1; } return 0; }
}
PHPSRC
for pair in "doc.py 0" "priv.ts 1" "life.rs 1" "hash.php 1"; do
    fixture="${pair%% *}"
    expected="${pair##* }"
    got=$(_complexity_of "$LITERALS/$fixture")
    if [[ "$got" == "$expected" ]]; then
        log_pass "literals blanked correctly in $fixture (complexity $got)"
    else
        log_fail "literals blanked correctly in $fixture" "expected $expected, got $got"
    fi
done

# The shapes two reviews found the first blanker getting wrong, one fixture
# each. `human` is a hand count. fan_out is asserted too, because the first
# version blanked the quotes with the string and IMPORT_RE needs them: every
# quoted import on TypeScript and Bash stopped counting, and 98 of this
# repository's marks lost their fan_out with nobody looking.
_metric_of() {
    python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure "$1" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['$2'])" 2>/dev/null
}
printf "import { a } from './a';\nimport { b } from './b';\nimport React from 'react';\nexport const f = () => 1;\n" > "$LITERALS/imp.ts"
printf 'source "./lib/a.sh"\nsource ./lib/b.sh\nsource "${DIR}/c.sh"\nf() { :; }\n' > "$LITERALS/src.sh"
printf 'f() {\n  [[ ${#args[@]} -gt 0 ]] && return 1\n  if [[ $# -eq 0 ]]; then return 2; fi\n  return 0\n}\ng() { :; }\n' > "$LITERALS/hash.sh"
printf 'const re = /[/*]/g;\nfunction g(a) { if (a) { return 1 } return 0 }\n' > "$LITERALS/regex.js"
printf 'function f(a,b) {\n  return <p>Don'"'"'t panic {a && <span/>} {b ? "x" : "y"}</p>;\n}\n' > "$LITERALS/jsx.tsx"
printf 'func f(a int) int {\n\ts := `C:\\`\n\tif a > 0 && s != "" { return 1 }\n\tif r := '"'"'"'"'"'; r == '"'"'"'"'"' && a > 1 { return 2 }\n\treturn 0\n}\n' > "$LITERALS/raw.go"
printf 'const q = `\n  if (x) for while\n  && ||\n`;\nfunction g(a) { if (a) return 1; return 0 }\n' > "$LITERALS/template.ts"
printf '<?php\nfunction f($a) {\n  $sql = <<<SQL\n  SELECT CASE WHEN x THEN 1 ELSE 0 END\n  SQL;\n  $t = <<<'"'"'TXT'"'"'\n  if for while case catch\n  TXT;\n  if ($a) { return 1; }\n  return 0;\n}\n' > "$LITERALS/heredoc.php"
printf 'export function a(x) {\n  if (x) { return 1 }\n  return 0\n}\nexport default function b() { return 2 }\n' > "$LITERALS/exported.ts"

for spec in \
    "imp.ts|fan_out|3|quoted imports still count as fan_out" \
    "src.sh|fan_out|3|sourced libraries still count as fan_out" \
    "hash.sh|complexity|2|\$# and \${#arr[@]} are not comments" \
    "hash.sh|max_fn_lines|5|and the function span is not swallowed after them" \
    "regex.js|complexity|1|a /[/*]/ regex does not open a block comment to end of file" \
    "jsx.tsx|complexity|2|an apostrophe in JSX text does not eat the && and the ternary" \
    "raw.go|complexity|4|a Go raw string has no escapes and a rune is not a string" \
    "template.ts|complexity|1|a multi-line template literal is blanked whole" \
    "heredoc.php|complexity|1|PHP heredoc and nowdoc are blanked" \
    "exported.ts|max_fn_lines|4|exported functions are seen by the span finder"
do
    IFS='|' read -r fixture metric expected why <<< "$spec"
    got=$(_metric_of "$LITERALS/$fixture" "$metric")
    if [[ "$got" == "$expected" ]]; then
        log_pass "$why ($fixture $metric=$got)"
    else
        log_fail "$why" "$fixture $metric expected $expected, got $got"
    fi
done

# `ignores` is the one metric measured on the RAW source: a craftsman-ignore
# marker lives in a comment by definition, so blanking comments first would
# count zero on every file and the ratchet would stop noticing suppressions
# piling up.
cat > "$LITERALS/suppressed.py" <<'PYSRC'
# craftsman-ignore: PY002
def g():
    return 1
PYSRC
ignores=$(python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure "$LITERALS/suppressed.py" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["ignores"])' 2>/dev/null)
if [[ "$ignores" == "1" ]]; then
    log_pass "a craftsman-ignore marker is still counted after comments are blanked"
else
    log_fail "a craftsman-ignore marker is still counted" "got '$ignores'"
fi

rm -rf "$LITERALS"

# --- A mark from an older instrument is not a mark -----------------------------
#
# The blanker above changes what an untouched file measures, and not in one
# direction: a function whose docstring holds `def example():` measured
# complexity 0 and max_fn_lines 4 under the old ruler (FN_RE cut the span at
# the fake def) and measures 5 and 17 under the new one. Compared blindly,
# `check` reported RATCHET001 on a file nobody edited, and a plugin upgrade put
# CI in the red. So every mark carries the instrument that took it, and an
# older one is re-taken rather than judged.
INSTR="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-instrument.XXXXXX")"
mkdir -p "$INSTR/src"
( cd "$INSTR" && git init -q ) >/dev/null 2>&1
cat > "$INSTR/src/inner.py" <<'PYSRC'
def outer(a):
    """Example:
    def example():
        pass
    """
    if a:
        return 1
    if a > 1:
        return 2
    return 0
PYSRC
# What instrument 1 wrote for this file, deliberately low, with no
# `instrument` key at all, which is what every baseline in the wild carries.
printf '[{"path":"src/inner.py","complexity":0,"file_lines":10,"max_fn_lines":4,"fan_out":0,"ignores":0}]\n' \
    > "$INSTR/.craftsman-baseline.json"
old_mark_code=0
old_mark_err=$( cd "$INSTR" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" check src/inner.py 2>&1 >/dev/null ) || old_mark_code=$?
if [[ "$old_mark_code" -eq 0 ]]; then
    log_pass "a mark taken by an older instrument does not fail an untouched file"
else
    log_fail "a mark taken by an older instrument does not fail an untouched file" \
        "exit $old_mark_code: the plugin upgrade alone turned the build red"
fi
assert_contains "and the re-mark is said on stderr, not done in silence" \
    "$old_mark_err" "older instrument"

remarked=$( cd "$INSTR" && python3 -c "
import json
entry = json.load(open('.craftsman-baseline.json'))[0]
print('%s %s' % (entry.get('instrument'), entry.get('complexity')))")
if [[ "$remarked" == "2 2" ]]; then
    log_pass "the re-taken mark carries the current instrument and the current number"
else
    log_fail "the re-taken mark carries the current instrument and the current number" "got '$remarked'"
fi

# The ratchet still ratchets. Against the re-taken mark, a real third branch is
# a regression, or the versioning would have bought silence instead of truth.
cat > "$INSTR/src/inner.py" <<'PYSRC'
def outer(a):
    if a:
        return 1
    if a > 1:
        return 2
    if a > 2:
        return 3
    return 0
PYSRC
real_code=0
( cd "$INSTR" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" check src/inner.py >/dev/null 2>&1 ) || real_code=$?
if [[ "$real_code" -eq 1 ]]; then
    log_pass "a real regression against the current instrument still fires"
else
    log_fail "a real regression against the current instrument still fires" "exit $real_code"
fi

# `update` replaces an old mark rather than tightening against it: a min()
# between two rulers is a number neither of them measured.
printf '[{"path":"src/inner.py","complexity":0,"file_lines":10,"max_fn_lines":4,"fan_out":0,"ignores":0}]\n' \
    > "$INSTR/.craftsman-baseline.json"
( cd "$INSTR" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" update src/inner.py >/dev/null 2>&1 )
updated=$( cd "$INSTR" && python3 -c "
import json
entry = json.load(open('.craftsman-baseline.json'))[0]
print('%s %s' % (entry.get('instrument'), entry.get('complexity')))")
if [[ "$updated" == "2 3" ]]; then
    log_pass "update replaces an older mark instead of taking min() across instruments"
else
    log_fail "update replaces an older mark instead of taking min() across instruments" "got '$updated'"
fi

rm -rf "$INSTR"

test_summary
