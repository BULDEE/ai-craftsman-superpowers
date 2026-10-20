#!/usr/bin/env bash
# =============================================================================
# Structural ratchet tests (ADR-0025): metric core, baseline lifecycle.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

RATCHET="$ROOT_DIR/hooks/lib/ratchet.py"
INSTRUMENT=$(grep -oE '^RATCHET_INSTRUMENT = [0-9]+' "$RATCHET" | grep -oE '[0-9]+$')
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

# The prune must read the path inside the project, not the absolute one. It
# matched every segment, so `var` skipped every file under /var/www, which is
# where a deployed PHP application lives, and every fixture under macOS's
# /var/folders: the ratchet measured nothing there and said nothing.
VARWWW="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-var.XXXXXX")/var/www/app"
mkdir -p "$VARWWW/src" "$VARWWW/vendor/acme"
( cd "$VARWWW" && git init -q ) >/dev/null 2>&1
printf 'def f(a):\n    if a:\n        return 1\n    return 0\n' > "$VARWWW/src/p.py"
cp "$VARWWW/src/p.py" "$VARWWW/vendor/acme/p.py"
under_var=$(cd "$VARWWW" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure src/p.py 2>/dev/null | grep -c complexity)
vendored=$(cd "$VARWWW" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure vendor/acme/p.py 2>/dev/null | grep -c complexity)
if [[ "${under_var:-0}" -eq 1 && "${vendored:-0}" -eq 0 ]]; then
    log_pass "a project under /var/www is measured, and its vendor/ is still pruned"
else
    log_fail "a project under /var/www is measured, and its vendor/ is still pruned" \
        "src measured=$under_var vendor measured=$vendored"
fi
rm -rf "${VARWWW%/var/www/app}"

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
if [[ "$remarked" == "$INSTRUMENT 2" ]]; then
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
if [[ "$updated" == "$INSTRUMENT 3" ]]; then
    log_pass "update replaces an older mark instead of taking min() across instruments"
else
    log_fail "update replaces an older mark instead of taking min() across instruments" "got '$updated'"
fi

rm -rf "$INSTR"

# --- Inert until the project opts in, and anchored on the file ----------------
#
# `ratchet.py check` on a file with no mark anywhere used to CREATE a baseline
# next to the file (a new row for an unmarked file is right inside an existing
# mark; a new mark file is an opt-in nobody made). The hooks hid that behind a
# `$PWD/.craftsman-baseline.json` gate, which is the other defect: the rule
# baseline walks up from the file, the ratchet was anchored on the shell's
# directory, so a hook fired from `src/` of a marked project skipped the
# ratchet entirely (architecture review, MUST-FIX).
INERT=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ratchet-inert.XXXXXX")
mkdir -p "$INERT/src"
printf 'x() {\n  if a; then b; fi\n}\n' > "$INERT/src/f.sh"
( cd "$INERT/src" && python3 "$ROOT_DIR/hooks/lib/ratchet.py" check f.sh >/dev/null 2>&1; python3 "$ROOT_DIR/hooks/lib/ratchet.py" update f.sh >/dev/null 2>&1 )
if [[ ! -e "$INERT/src/.craftsman-baseline.json" && ! -e "$INERT/.craftsman-baseline.json" ]]; then
    log_pass "check and update on an unmarked project create no mark: inert until init"
else
    log_fail "check or update created a mark on an unmarked project" "$(ls -a "$INERT" "$INERT/src" | tr '\n' ' ')"
fi
( cd "$INERT" && git init -q && python3 "$ROOT_DIR/hooks/lib/ratchet.py" init >/dev/null 2>&1 )
printf 'x() {\n  if a; then b; fi\n  if c; then d; fi\n  if e; then f; fi\n}\n' > "$INERT/src/f.sh"
SUB_EXIT=0
SUB_OUT=$( cd "$INERT/src" && echo "{\"tool_input\":{\"file_path\":\"$INERT/src/f.sh\"}}" \
    | CLAUDE_PLUGIN_ROOT="$ROOT_DIR" CLAUDE_PLUGIN_OPTION_strictness=strict bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 ) || SUB_EXIT=$?
if echo "$SUB_OUT" | grep -q "RATCHET001"; then
    log_pass "a hook fired from a subdirectory still finds the project's mark and reports the regression"
else
    log_fail "the ratchet is anchored on the file, not on the shell's directory" "exit=$SUB_EXIT out=$(echo "$SUB_OUT" | tr '\n' ' ' | cut -c1-120)"
fi
rm -rf "$INERT"

echo ""
echo "=== CR-288: a body whose brace opens on its own line is measured ==="
# PSR-12 puts a method's opening brace on its own line. The span finder only
# looked for `{` on the header, fell back to indentation, and closed the
# function on that brace, at the same indent: every PSR-12 method measured
# complexity 0 and max_fn_lines 1, so the ratchet saw nothing in the PHP it
# was built for, and file_lines was the only number that ever moved.
SPAN=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ratchet-span.XXXXXX")
cat > "$SPAN/Psr12.php" <<'PHP'
<?php
final class Invoice
{
    public function total(int $amount): int
    {
        if ($amount > 100) {
            return $amount * 3;
        }
        if ($amount > 10) {
            return $amount * 2;
        }
        return $amount;
    }
}
PHP
cat > "$SPAN/Multi.php" <<'PHP'
<?php
final class Order
{
    public function ship(
        int $quantity,
        string $carrier,
    ): string {
        if ($quantity > 0 && $carrier !== '') {
            return $carrier;
        }
        return 'none';
    }
}
PHP
cat > "$SPAN/indent.py" <<'PY'
def ship(
    quantity,
    carrier,
):
    labels = {
        "fast": 1,
    }
    if quantity and carrier:
        return labels
    return None
PY
measure_of() { python3 "$RATCHET" measure "$SPAN/$1" | jq -c '{complexity, max_fn_lines}'; }
PSR=$(measure_of Psr12.php)
if [[ "$PSR" == '{"complexity":2,"max_fn_lines":10}' ]]; then
    log_pass "a PSR-12 method (brace on its own line) is measured: $PSR"
else
    log_fail "PSR-12 method span" "got $PSR, want complexity 2 over 10 lines"
fi
MULTI=$(measure_of Multi.php)
if [[ "$MULTI" == '{"complexity":2,"max_fn_lines":9}' ]]; then
    log_pass "a signature over several lines is measured to its closing brace: $MULTI"
else
    log_fail "multi-line signature span" "got $MULTI"
fi
INDENT=$(measure_of indent.py)
if [[ "$INDENT" == '{"complexity":1,"max_fn_lines":11}' ]]; then
    log_pass "an indented body after a signature over several lines is measured, a dict literal is not a brace body: $INDENT"
else
    log_fail "indentation body after a multi-line signature" "got $INDENT"
fi
cat > "$SPAN/aligned.py" <<'PY'
def ship(quantity,
         carrier):
    if quantity:
        return carrier
    return None
PY
ALIGNED=$(measure_of aligned.py)
if [[ "$ALIGNED" == '{"complexity":1,"max_fn_lines":6}' ]]; then
    log_pass "continuation lines aligned on the parenthesis do not end the body: $ALIGNED"
else
    log_fail "aligned continuation" "got $ALIGNED"
fi
cat > "$SPAN/oneliner.php" <<'PHP'
<?php
final class Line
{
    public function total(int $amount): int { return $amount * 2; }
    public function half(int $amount): int { return $amount > 1 ? intdiv($amount, 2) : 0; }
}
PHP
ONE=$(measure_of oneliner.php)
if [[ "$ONE" == '{"complexity":1,"max_fn_lines":1}' ]]; then
    log_pass "control: one-line methods keep their one-line span: $ONE"
else
    log_fail "one-line methods" "got $ONE"
fi
rm -rf "$SPAN"

echo ""
echo "=== CR-288: the gate holds function-level debt, CI sees slack ==="
# Measured 2026-10-20 on this repository: 473 budget raises in 116 commits,
# 270 of them on file_lines alone, 15% on a function-level metric of
# production code. A file that grows with a feature is not debt (LOC001, the
# rule that owns file length, is advisory permanently), so file_lines and
# fan_out leave the mark. And the mark only tightened after a Write or Edit
# through the local hook: 13 rows were looser than their file, one by 212
# lines, which `check --tight` now refuses in the repository's own CI.
SIG=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ratchet-signal.XXXXXX")
mkdir -p "$SIG/src"
( cd "$SIG" && git init -q )
cat > "$SIG/src/order.php" <<'PHP'
<?php
final class Order {
    public function total(int $count): int {
        if ($count > 0) { return $count; }
        return 0;
    }
}
PHP
( cd "$SIG" && python3 "$RATCHET" init src >/dev/null )
ROW=$(grep '"src/order.php"' "$SIG/.craftsman-baseline.json" | sed 's/,$//')
if [[ -n "$ROW" ]] && echo "$ROW" | jq -e 'has("file_lines") or has("fan_out") | not' >/dev/null 2>&1 \
    && echo "$ROW" | jq -e 'has("complexity") and has("max_fn_lines") and has("ignores")' >/dev/null 2>&1; then
    log_pass "a mark records complexity, max_fn_lines and ignores, not file_lines or fan_out"
else
    log_fail "the mark still records file size" "$ROW"
fi

cat > "$SIG/src/order.php" <<'PHP'
<?php
use App\Domain\Invoice;
use App\Domain\Customer;
final class Order {
    public function total(int $count): int {
        if ($count > 0) { return $count; }
        return 0;
    }
    public function lines(): array { return []; }
    public function customer(): string { return 'c'; }
}
PHP
EXIT_CODE=0
OUT=$( cd "$SIG" && python3 "$RATCHET" check src/order.php ) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 && -z "$OUT" ]]; then
    log_pass "a file that only grew (more lines, more imports) passes check"
else
    log_fail "file growth still fails the ratchet" "exit=$EXIT_CODE out=$OUT"
fi

cat > "$SIG/src/order.php" <<'PHP'
<?php
final class Order {
    public function total(int $count): int {
        if ($count > 0) { return $count; }
        if ($count < -10) { return -1; }
        return 0;
    }
}
PHP
EXIT_CODE=0
OUT=$( cd "$SIG" && python3 "$RATCHET" check src/order.php ) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 1 ]] && echo "$OUT" | grep -q "RATCHET001 complexity" && echo "$OUT" | grep -q "RATCHET001 max_fn_lines"; then
    log_pass "control: a function that grew still fails check"
else
    log_fail "function-level regression no longer caught" "exit=$EXIT_CODE out=$OUT"
fi

printf '[\n{"complexity":1,"fan_out":3,"file_lines":40,"ignores":0,"instrument":%s,"max_fn_lines":9,"path":"src/order.php","reason":"legacy row"}\n]\n' "$INSTRUMENT" \
    > "$SIG/.craftsman-baseline.json"
( cd "$SIG" && python3 "$RATCHET" update src/order.php >/dev/null )
ROW=$(grep '"src/order.php"' "$SIG/.craftsman-baseline.json" | sed 's/,$//')
if echo "$ROW" | jq -e '(has("file_lines") or has("fan_out") | not) and .reason == "legacy row"' >/dev/null 2>&1; then
    log_pass "update drops the retired metrics of an older row and keeps its reason"
else
    log_fail "an older row keeps file_lines or fan_out after update" "$ROW"
fi

printf '[\n{"complexity":7,"ignores":0,"instrument":%s,"max_fn_lines":30,"path":"src/order.php"}\n]\n' "$INSTRUMENT" \
    > "$SIG/.craftsman-baseline.json"
EXIT_CODE=0
OUT=$( cd "$SIG" && python3 "$RATCHET" check src/order.php ) || EXIT_CODE=$?
TIGHT_EXIT=0
TIGHT_OUT=$( cd "$SIG" && python3 "$RATCHET" check src/order.php --tight ) || TIGHT_EXIT=$?
if [[ $EXIT_CODE -eq 0 && $TIGHT_EXIT -eq 1 ]] && echo "$TIGHT_OUT" | grep -q "slack complexity 7 -> 2" \
    && echo "$TIGHT_OUT" | grep -q "ratchet.py update src/order.php"; then
    log_pass "check --tight refuses a mark looser than the file and names the update"
else
    log_fail "slack not refused" "plain exit=$EXIT_CODE tight exit=$TIGHT_EXIT out=$TIGHT_OUT"
fi

( cd "$SIG" && python3 "$RATCHET" update src/order.php >/dev/null )
TIGHT_EXIT=0
TIGHT_OUT=$( cd "$SIG" && python3 "$RATCHET" check src/order.php --tight ) || TIGHT_EXIT=$?
if [[ $TIGHT_EXIT -eq 0 && -z "$TIGHT_OUT" ]]; then
    log_pass "check --tight passes once the mark is tightened"
else
    log_fail "--tight after update" "exit=$TIGHT_EXIT out=$TIGHT_OUT"
fi
printf 'final class Invoice {}\n' > "$SIG/src/invoice.php"
UNMARKED_EXIT=0
UNMARKED_OUT=$( cd "$SIG" && python3 "$RATCHET" check src/invoice.php --tight ) || UNMARKED_EXIT=$?
if [[ $UNMARKED_EXIT -eq 1 ]] && echo "$UNMARKED_OUT" | grep -q "unmarked src/invoice.php"; then
    log_pass "check --tight refuses a touched file with no committed row"
else
    log_fail "an unmarked file passes --tight" "exit=$UNMARKED_EXIT out=$UNMARKED_OUT"
fi
rm -rf "$SIG"

if grep -qE 'ratchet\.py check "\$file" --tight' "$ROOT_DIR/.github/workflows/ci.yml"; then
    log_pass "the repository's CI runs the ratchet with --tight"
else
    log_fail "ci.yml does not pass --tight" "Structural Ratchet job"
fi

# A ruler change re-takes the numbers, never the rest of the row. The re-take
# replaced the whole row with a fresh measure, so the reason and the rule
# baseline's counts (`rules`, written into the same row) went with it: bumping
# the instrument would have made every user's inherited rule debt block again.
KEEP=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ratchet-keep.XXXXXX")
mkdir -p "$KEEP/src"
( cd "$KEEP" && git init -q )
printf 'def ship(order):\n    if order:\n        return order\n    return None\n' > "$KEEP/src/ship.py"
OLD_ROW='{"complexity":0,"ignores":0,"instrument":1,"max_fn_lines":1,"path":"src/ship.py","reason":"kept reason","rules":{"PY001":2}}'
printf '[\n%s\n]\n' "$OLD_ROW" > "$KEEP/.craftsman-baseline.json"
( cd "$KEEP" && python3 "$RATCHET" check src/ship.py >/dev/null 2>&1 )
AFTER_CHECK=$(jq -c '.[0] | {reason, rules, complexity, instrument}' "$KEEP/.craftsman-baseline.json")
printf '[\n%s\n]\n' "$OLD_ROW" > "$KEEP/.craftsman-baseline.json"
( cd "$KEEP" && python3 "$RATCHET" update src/ship.py >/dev/null 2>&1 )
AFTER_UPDATE=$(jq -c '.[0] | {reason, rules, complexity, instrument}' "$KEEP/.craftsman-baseline.json")
WANT="{\"reason\":\"kept reason\",\"rules\":{\"PY001\":2},\"complexity\":1,\"instrument\":$INSTRUMENT}"
if [[ "$AFTER_CHECK" == "$WANT" && "$AFTER_UPDATE" == "$WANT" ]]; then
    log_pass "a re-take after an instrument change keeps the reason and the rule counts"
else
    log_fail "an instrument change erases the row" "check=$AFTER_CHECK update=$AFTER_UPDATE"
fi
rm -rf "$KEEP"

# The committed mark itself: one reason per row (git keeps the history), and
# no retired metric. 87 KB of which 55% was concatenated reasons before.
MARK_CHECK=$(python3 - "$ROOT_DIR/.craftsman-baseline.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
bad = [r["path"] for r in rows if "file_lines" in r or "fan_out" in r]
long = [r["path"] for r in rows if len(r.get("reason", "")) > 500]
print(f"retired={len(bad)} long_reasons={len(long)} {bad[:2]} {long[:2]}")
PY
)
if [[ "$MARK_CHECK" == "retired=0 long_reasons=0 "* ]]; then
    log_pass "the repository's mark holds no retired metric and no reason past 500 characters"
else
    log_fail "the repository's mark" "$MARK_CHECK"
fi

test_summary
