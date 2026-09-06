#!/usr/bin/env bash
# =============================================================================
# The legacy worked example has to still work.
#
# A worked example is documentation whose consumer is a reader running it. The
# only way it stays true is if something runs it: a walkthrough quoting output
# the code no longer produces is worse than no walkthrough, because a reader
# who replays it and gets something else stops trusting the rest of the docs.
#
# So this drives demo.sh end to end and asserts on what it printed, including
# the step that must go RED. The first version of the demo printed OK there,
# because Python revalidated a cached .pyc whose (mtime, size) had not changed,
# and it would have taught the opposite of its own lesson.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

DEMO="$ROOT_DIR/examples/legacy/demo.sh"
WALKTHROUGH="$ROOT_DIR/examples/legacy/03-from-arrival-to-safety.md"
FIXTURE="$ROOT_DIR/examples/legacy/fixture"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-legacy-example.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "=== Legacy worked example ==="

# --- The three steps of the fixture are each self-contained -------------------

for step in step1 step2 step3; do
    if ( cd "$FIXTURE/$step" && PYTHONDONTWRITEBYTECODE=1 \
         python3 -m unittest test_pricing >/dev/null 2>&1 ); then
        log_pass "$step: the net is green on its own"
    else
        log_fail "$step: the net is green on its own" \
            "$(cd "$FIXTURE/$step" && python3 -m unittest test_pricing 2>&1 | tail -3)"
    fi
done

# The claim the walkthrough makes about step 3 is that the net was not touched.
if diff -q "$FIXTURE/step2/test_pricing.py" "$FIXTURE/step3/test_pricing.py" >/dev/null; then
    log_pass "the refactor happened under a net that was not edited"
else
    log_fail "the refactor happened under a net that was not edited" \
        "step2 and step3 tests differ"
fi

# --- The net catches a change, which is the only thing that makes it a net ----

BREAK="$WORK/break"
mkdir -p "$BREAK"
cp "$FIXTURE/step1/pricing.py" "$FIXTURE/step1/test_pricing.py" "$BREAK/"
python3 - "$BREAK/pricing.py" <<'PY'
import sys
path = sys.argv[1]
source = open(path).read()
assert "BULK_THRESHOLD = 10" in source
open(path, "w").write(source.replace("BULK_THRESHOLD = 10", "BULK_THRESHOLD = 11", 1))
PY
if ( cd "$BREAK" && PYTHONDONTWRITEBYTECODE=1 \
     python3 -m unittest test_pricing >/dev/null 2>&1 ); then
    log_fail "the net goes red on an off-by-one in the bulk threshold" \
        "the deliberate break passed"
else
    log_pass "the net goes red on an off-by-one in the bulk threshold"
fi

# --- The refactor is measurably a refactor ------------------------------------

measure() {
    python3 "$ROOT_DIR/hooks/lib/ratchet.py" measure "$1" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print('%s %s' % (d['complexity'], d['max_fn_lines']))"
}
before="$(measure "$FIXTURE/step1/pricing.py")"
after="$(measure "$FIXTURE/step3/pricing.py")"

if [[ "$before" == "4 21" && "$after" == "1 15" ]]; then
    log_pass "the numbers the walkthrough quotes are the numbers the tool prints"
else
    log_fail "the numbers the walkthrough quotes are the numbers the tool prints" \
        "before='$before' after='$after', walkthrough says '4 21' then '1 15'"
fi

# --- The demo runs, and says what the walkthrough says it says ----------------

# A checksum of the fixture, not `git status`: the check has to hold on a
# working copy where these files are not committed yet, which is exactly when
# someone is editing them.
fixture_fingerprint() {
    find "$FIXTURE" -type f | sort | xargs cksum | cksum
}
before_run="$(fixture_fingerprint)"

demo_out="$WORK/demo.out"
if bash "$DEMO" > "$demo_out" 2>&1; then
    log_pass "demo.sh runs to completion"
else
    log_fail "demo.sh runs to completion" "$(tail -5 "$demo_out")"
fi

demo_text="$(cat "$demo_out")"

assert_contains "the demo reaches its last step" "$demo_text" "=== Done ==="
assert_contains "the demo shows the net failing on the deliberate break" \
    "$demo_text" "FAILED (failures=2)"
assert_contains "the demo shows the before measurement" \
    "$demo_text" '"complexity": 4'
assert_contains "the demo shows the after measurement" \
    "$demo_text" '"complexity": 1'
assert_contains "the demo shows the ratchet refusing the regression" \
    "$demo_text" "RATCHET001 complexity 1 -> 4"

# A demo that leaves state behind is a demo whose second run differs from its
# first, which is the one property a replayable example cannot lose. It works
# in a temporary directory, so the fixture it copies from must come out
# byte-identical, including the .pyc files a test run would otherwise leave.
if [[ "$(fixture_fingerprint)" == "$before_run" ]]; then
    log_pass "the demo leaves the fixture untouched"
else
    log_fail "the demo leaves the fixture untouched" \
        "the fixture checksum changed across the run"
fi

# --- The gate's own verdict on the fixture, as quoted --------------------------
#
# The walkthrough prints a warning count. A count is the easiest number in a
# document to leave stale, and the one a reader is most likely to check first.
GATE_DIR="$WORK/gate"
mkdir -p "$GATE_DIR"
cp -r "$FIXTURE" "$GATE_DIR/fixture"
( cd "$GATE_DIR" && git init -q && git add -A ) >/dev/null 2>&1
gate_out="$( cd "$GATE_DIR" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
    bash "$ROOT_DIR/ci/craftsman-ci.sh" fixture 2>&1 | tail -1 )"

if printf '%s' "$gate_out" | grep -q "0 violations"; then
    log_pass "the fixture raises no violation, only advisory findings"
else
    log_fail "the fixture raises no violation, only advisory findings" "$gate_out"
fi

gate_count="$(printf '%s' "$gate_out" | sed -nE 's/.*, ([0-9]+) warning.*/\1/p')"
if [[ -n "$gate_count" ]] && grep -qF "$gate_count warning(s) in 6 file(s)" "$WALKTHROUGH"; then
    log_pass "the walkthrough quotes the warning count the gate prints"
else
    log_fail "the walkthrough quotes the warning count the gate prints" \
        "gate says '${gate_count:-?}', walkthrough says something else"
fi

# --- The walkthrough quotes output the demo actually produces ------------------

walkthrough_text="$(cat "$WALKTHROUGH")"

for quoted in \
    '"complexity": 4, "file_lines": 48, "max_fn_lines": 21' \
    '"complexity": 1, "file_lines": 70, "max_fn_lines": 15' \
    'Ran 6 tests' \
    'AssertionError: 114.0 != 120.0' \
    'RATCHET001 complexity 1 -> 4'
do
    if printf '%s' "$demo_text" | grep -qF -- "$quoted"; then
        if printf '%s' "$walkthrough_text" | grep -qF -- "$quoted"; then
            log_pass "the walkthrough quotes real output: ${quoted:0:40}"
        else
            log_fail "the walkthrough quotes real output: ${quoted:0:40}" \
                "the demo prints it, the walkthrough does not"
        fi
    else
        log_fail "the walkthrough quotes real output: ${quoted:0:40}" \
            "the demo no longer prints it"
    fi
done

test_summary
