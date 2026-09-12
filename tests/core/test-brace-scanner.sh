#!/usr/bin/env bash
# =============================================================================
# One brace walk for every brace-delimited pack (#38).
#
# packs/go and packs/rust each carried a scanner, 134 lines identical between
# them, and the next fix to the brace stack would have been carried by hand
# three times. hooks/lib/brace_scanner.py holds the walk once; a pack supplies
# a profile. Asserted through a THIRD language that exists only here, because
# "adding a language means writing a profile" is the claim, and the two real
# packs passing their own suites unchanged proves the extraction, not the
# claim. Then the guard: neither pack may grow its own walk back.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Brace scanner (#38) ==="

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-brace.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# A language nobody ships: `proc name(a, b) {`, control heads `when`/`loop`,
# containers `module Name {`. Twelve lines of profile, no scanner.
cat > "$WORK/third_lang.py" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
from brace_scanner import Profile, balanced_group, drop_ignored, split_params, walk_braces

PROC_RE = re.compile(r"\bproc\b\s*(\w+)?\s*\(")
CONTROL_RE = re.compile(r"(?:^|[^.\w])(when|loop)\b|\belse\b")
MODULE_RE = re.compile(r"\bmodule\s+(\w+)")

def params(header):
    match = PROC_RE.search(header)
    if not match:
        return []
    inner = balanced_group(header, header.index("(", match.end() - 1)).strip()
    return split_params(inner) if inner else []

def first_param_is_ctx(scan, cursor, header, name, plist):
    if plist and plist[0] != "ctx":
        scan.report("THIRD001", "line %d: %s() does not take ctx first" % (scan.line(cursor), name))

def sum_modules(scan, frame, span):
    if frame["kind"] == "container":
        scan.state["modules"] = scan.state.get("modules", 0) + 1

profile = Profile(function_re=PROC_RE, control_re=CONTROL_RE, parameter_list=params,
                  container_re=MODULE_RE, on_function=first_param_is_ctx,
                  on_close=sum_modules, function_word="proc", loc_max=int(sys.argv[3]))
raw = open(sys.argv[2]).read()
scan = walk_braces(raw, profile)
exempt = lambda rule, lines, index: index > 0 and "@silence " + rule in lines[index - 1]
for rule, message in drop_ignored(scan.findings, raw, also_exempt=exempt):
    print("%s|%s" % (rule, message))
print("modules|%d" % scan.state.get("modules", 0))
PY

cat > "$WORK/sample.third" <<'SRC'
module Billing {
    proc charge(ctx, amount, currency, memo) {
        when amount > 0 {
            loop item in items {
                when item.ok {
                    emit(item)
                }
            }
        }
    }
    proc refund(amount, ctx) {
        return amount
    }
    proc tiny(ctx) {
        a()
        b()
        c()
    }
}
module Audit {
    proc log(ctx) { }
}
SRC

OUT="$(python3 "$WORK/third_lang.py" "$ROOT_DIR/hooks/lib" "$WORK/sample.third" 50)"
assert_contains "PARAM001 from the shared walk, on the third language's own head" \
    "$OUT" "PARAM001|line 2: charge() has 4 parameters (max 3)"
assert_contains "NEST001 from the shared walk, at the third level" \
    "$OUT" "NEST001|line 5: control flow nested 3 levels deep: extract a proc"
assert_contains "the on_function hook sees every proc head" "$OUT" "THIRD001|line 11: refund() does not take ctx first"
if echo "$OUT" | grep -q "THIRD001|line 2"; then
    log_fail "the hook is judged per head" "charge() takes ctx first and was reported"
else
    log_pass "the hook is judged per head (charge takes ctx first, refund does not)"
fi
assert_contains "the on_close hook sees every container frame" "$OUT" "modules|2"
if echo "$OUT" | grep -q "LOC001"; then
    log_fail "LOC001 stays quiet under the profile's own limit" "$(echo "$OUT" | grep LOC001)"
else
    log_pass "LOC001 stays quiet under the profile's own limit (50)"
fi

# The limit is the profile's: lower it and the same file trips LOC001.
OUT_TIGHT="$(python3 "$WORK/third_lang.py" "$ROOT_DIR/hooks/lib" "$WORK/sample.third" 3)"
assert_contains "LOC001 when the profile lowers its limit to 3" \
    "$OUT_TIGHT" "LOC001|line 2: charge() body is 8 lines (max 3): extract a proc"

# The ignore filter, both syntaxes: the shared one on the line, the profile's own above it.
cat > "$WORK/ignored.third" <<'SRC'
proc a(w, x, y, z) { } # craftsman-ignore: PARAM001
# @silence PARAM001
proc b(w, x, y, z) { }
proc c(w, x, y, z) { }
SRC
OUT_IGN="$(python3 "$WORK/third_lang.py" "$ROOT_DIR/hooks/lib" "$WORK/ignored.third" 50)"
if [[ "$(echo "$OUT_IGN" | grep -c PARAM001)" == "1" ]] && echo "$OUT_IGN" | grep -q "PARAM001|line 4: c()"; then
    log_pass "craftsman-ignore on the line and the language's own exemption above it both hold; c() is reported"
else
    log_fail "the ignore filter honours both syntaxes" "$OUT_IGN"
fi

# split_params on generics: the angle brackets nest only when asked.
GEN="$(python3 -c "
import sys; sys.path.insert(0, '$ROOT_DIR/hooks/lib')
from brace_scanner import split_params
print(len(split_params('a: Map<K, V>, b: u8', angle_brackets=True)), len(split_params('a: Map<K, V>, b: u8')), len(split_params('f: impl Fn(u32) -> u32, g: u8', angle_brackets=True)))
")"
if [[ "$GEN" == "2 3 2" ]]; then
    log_pass "split_params nests <> only for a language that asks, and -> does not close one"
else
    log_fail "split_params generics" "got '$GEN', expected '2 3 2'"
fi

# An option the profile does not know is refused, not dropped: a typo in
# on_function would otherwise silence a whole rule with no signal.
TYPO="$(python3 -c "
import re, sys; sys.path.insert(0, '$ROOT_DIR/hooks/lib')
from brace_scanner import Profile
try:
    Profile(function_re=re.compile('x'), control_re=re.compile('y'), parameter_list=lambda h: [], on_functon=lambda *a: None, loc_mx=1)
    print('accepted')
except TypeError as error:
    print(error)
")"
assert_contains "a misspelled profile option is refused by name" "$TYPO" "unknown option(s) loc_mx, on_functon"

# A language whose declarations end without a brace: the header runs from the
# previous brace, so `proc short(a) = a + 1` would name the next brace. The
# profile narrows the header to its last statement through head_of.
cat > "$WORK/expr.third" <<'SRC'
proc short(ctx) = 1
proc long(ctx, a, b, c) {
    x()
}
SRC
HEADLESS="$(python3 - "$ROOT_DIR/hooks/lib" "$WORK/expr.third" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
from brace_scanner import Profile, balanced_group, split_params, walk_braces
PROC_RE = re.compile(r"\bproc\b\s*(\w+)?\s*\(")
def params(header):
    match = PROC_RE.search(header)
    if not match:
        return []
    inner = balanced_group(header, header.index("(", match.end() - 1)).strip()
    return split_params(inner) if inner else []
raw = open(sys.argv[2]).read()
plain = walk_braces(raw, Profile(function_re=PROC_RE, control_re=re.compile(r"\bwhen\b"), parameter_list=params))
last = walk_braces(raw, Profile(function_re=PROC_RE, control_re=re.compile(r"\bwhen\b"), parameter_list=params,
                                head_of=lambda header: header.rsplit("\n", 1)[-1]))
print("plain:", [m for _, m in plain.findings])
print("head_of:", [m for _, m in last.findings])
PY
)"
assert_contains "without head_of the earlier declaration names the brace and long() is missed" "$HEADLESS" "plain: \[\]"
assert_contains "with head_of narrowing to the last line, long() is measured" "$HEADLESS" "head_of: \['line 2: long() has 4 parameters"

# --- The guard: the walk exists once ------------------------------------------
for scanner in packs/go/hooks/go_structure.py packs/rust/hooks/rust_structure.py; do
    if grep -qE "^class _?Scan\b|^def _open_brace|^def _close_brace|^def line_of|^def drop_ignored" "$ROOT_DIR/$scanner"; then
        log_fail "$scanner carries no brace walk of its own" \
            "$(grep -nE '^class _?Scan\b|^def _open_brace|^def _close_brace|^def line_of|^def drop_ignored' "$ROOT_DIR/$scanner" | tr '\n' ' ')"
    else
        log_pass "$scanner carries no brace walk of its own"
    fi
    if grep -q "from brace_scanner import" "$ROOT_DIR/$scanner"; then
        log_pass "$scanner imports the shared walk"
    else
        log_fail "$scanner imports the shared walk" "no import"
    fi
done

# The pack scanners resolve the engine through CLAUDE_PLUGIN_ROOT first, so an
# external pack installed elsewhere still finds it.
EXT="$WORK/external-pack/hooks"
mkdir -p "$EXT"
cp "$ROOT_DIR/packs/go/hooks/go_structure.py" "$EXT/"
printf 'package main\n\nfunc Big(a, b, c, d int) {}\n' > "$WORK/big.go"
EXT_OUT="$(CLAUDE_PLUGIN_ROOT="$ROOT_DIR" python3 "$EXT/go_structure.py" "$WORK/big.go" 2>&1)"
assert_contains "a pack copied outside the plugin finds the walk through CLAUDE_PLUGIN_ROOT" "$EXT_OUT" "PARAM001"

# And when it cannot find it, that is not a clean file: the scanner says so
# and exits 2, and the validator that reads it warns instead of reporting
# nothing. Before this, a traceback on stderr was discarded by the validator
# and the four-parameter function above read as clean.
LOST_OUT="$(CLAUDE_PLUGIN_ROOT=/nonexistent python3 "$EXT/go_structure.py" "$WORK/big.go" 2>&1)"; LOST_RC=$?
if [[ "$LOST_RC" == "2" ]] && echo "$LOST_OUT" | grep -q "cannot load the engine's brace walk"; then
    log_pass "a scanner that cannot load the walk says so and exits 2 rather than reporting clean"
else
    log_fail "a scanner that cannot load the walk says so and exits 2" "rc=$LOST_RC: $LOST_OUT"
fi
VALIDATOR_OUT="$(cd "$WORK" && CLAUDE_PLUGIN_ROOT=/nonexistent bash -c "
    add_violation() { echo \"finding \$1\"; }; add_warning() { echo \"finding \$1\"; }; line_has_ignore() { return 1; }; metrics_record_violation() { true; }; FILE_PATTERN=x
    _GO_PACK_DIR_OVERRIDE='$EXT'
    source '$ROOT_DIR/packs/go/hooks/go-validator.sh'
    _GO_STRUCTURE_PY='$EXT/go_structure.py'
    pack_validate_go '$WORK/big.go'" 2>&1)"
if echo "$VALIDATOR_OUT" | grep -q "craftsman: go structure scan did not run" && ! echo "$VALIDATOR_OUT" | grep -q "finding PARAM001"; then
    log_pass "the validator reports the scan that did not run, once, instead of a clean file"
else
    log_fail "the validator reports the scan that did not run instead of a clean file" "$VALIDATOR_OUT"
fi

test_summary
