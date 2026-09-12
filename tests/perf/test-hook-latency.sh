#!/usr/bin/env bash
# =============================================================================
# What the hooks actually cost, measured, on every change.
#
# Four documents claimed "Level 1: regex validation, under 50ms". Measured on
# the smallest input there is, a three-line PHP file, post-write-check.sh took
# 0.73s and bias-detector.sh 0.45s: 15 to 60 times the published figure,
# reproduced on two machines. A number nobody measures drifts, so the number in
# the documentation now comes from this file.
#
# The ceiling is expressed as a MULTIPLE of a calibration baseline measured in
# the same run, not as milliseconds. The hooks' cost is dominated by process
# starts (roughly 190 of them for one post-write run), and a fork costs what
# the machine costs: an absolute ceiling would pass on a workstation and flake
# on a loaded CI runner, which is the fastest way to have the ceiling deleted.
#
# Usage:
#   bash tests/perf/test-hook-latency.sh            # assert the ceilings
#   bash tests/perf/test-hook-latency.sh --report   # print the table only
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

RUNS="${CRAFTSMAN_PERF_RUNS:-7}"
REPORT_ONLY=false
[[ "${1:-}" == "--report" ]] && REPORT_ONLY=true

# The machine's own calibration memory lives OUTSIDE the sandbox this run
# creates and deletes. Captured before the two overrides below, because both of
# them point at the temporary directory: written there, the file was destroyed
# on exit, every run was the first run, and the derivation that reads it was
# dead code under a comment claiming it worked. The observable behaviour was
# identical to having no derivation at all, which is why it took executing it
# twice to see.
# Deliberately NOT CLAUDE_PLUGIN_DATA. This is a fact about the MACHINE, and
# every harness in this repository redirects that variable at a temporary
# directory: pointed there, the memory was written into a sandbox deleted on
# exit, so every run was the first run and the derivation below was dead code
# under a comment claiming it worked.
_PERF_STATE_DIR="${HOME}/.claude"
mkdir -p "$_PERF_STATE_DIR" 2>/dev/null || true

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-perf.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# HOME too, because `post-write-check.sh` reads ~/.claude/.craft-config.yml as
# the global rules layer: without this the benchmark measured whatever the
# developer happens to have there, and the number moved from machine to machine
# for reasons that have nothing to do with the code.
export HOME="$WORK/home"
mkdir -p "$HOME/.claude"

# The smallest realistic input: a file that violates nothing, in a repository
# with one commit. Anything larger measures the validators; this measures what
# every write pays before any finding exists.
PROJECT="$WORK/project"
mkdir -p "$PROJECT/src"
cat > "$PROJECT/src/A.php" <<'PHP'
<?php
declare(strict_types=1);
final class A {}
PHP
( cd "$PROJECT" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm one ) >/dev/null 2>&1

# Median, not mean: one slow run (a cold page cache, another process waking up)
# moves a mean and does not move a median.
# The MINIMUM for the verdict, the median for the report, and the difference
# between them is the whole difference between a benchmark and a coin toss.
#
# The first version asserted on the median and went red inside the full suite
# while passing on its own: the suite runs it last, on a machine still busy
# with everything before it, and a median absorbs that. Contention can only
# ever make a run slower, never faster, so the fastest of N runs is the closest
# thing to the uncontended cost that repeated sampling can give. The median is
# printed beside it, because the gap between the two says the machine was busy.
_min_ms() {
    local command="$1" runs="$2"
    python3 - "$command" "$runs" <<'PYTIME'
import subprocess, sys, time
command, runs = sys.argv[1], int(sys.argv[2])
samples = []
for _ in range(runs):
    started = time.time()
    subprocess.run(["bash", "-c", command], capture_output=True)
    samples.append((time.time() - started) * 1000)
samples.sort()
print("%.1f %.1f" % (samples[0], samples[len(samples) // 2]))
PYTIME
}

# The calibration wants one number, and it wants the uncontended one too.
_median_ms() {
    local pair
    pair="$(_min_ms "$1" "$2")" || return 1
    printf '%s' "${pair%% *}"
}

# The instrument before the experiment. `_median_ms` delegates to python3, and
# without it every median came back EMPTY: bash evaluates "" as 0 in an
# arithmetic test, so `[[ "" -le 220 ]]` is true and all three ceilings passed
# while nothing had been measured. A benchmark that reports success without
# measuring is the exact defect this file exists to end.
if ! command -v python3 >/dev/null 2>&1; then
    log_fail "the benchmark can run" "python3 not found, so nothing can be measured"
    test_summary
fi

_is_measurement() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# The calibration has the SHAPE of a hook, not merely its ingredients.
#
# A basket of `bash -c true`, one python3 start and one read was better than
# `true` alone and still wrong under load, measured: with twelve busy loops on
# ten cores the basket grew 1.3x while the hooks grew 1.95x, because a
# post-write run makes about 106 process starts and the basket makes three.
# The ratio then grew 1.5x on unchanged code, against a 1.4x margin, so the
# suite went red for a reason that had nothing to do with the change under
# test: exactly the flake this file's own comment says would get the ceiling
# deleted.
#
# So the baseline is fifty real forks plus one python3 start and one read. It
# grows the way the hooks grow because it is made of the same thing they are
# made of, which makes the ratio invariant to load by construction rather than
# by hope.
CALIBRATION_FORKS=50
CALIBRATION_WORKLOAD="for _ in \$(seq 1 $CALIBRATION_FORKS); do /bin/echo x >/dev/null; done; python3 -c pass; cat '$PROJECT/src/A.php' >/dev/null"

FLOOR_MS="$(_median_ms "$CALIBRATION_WORKLOAD" 7)"
if ! _is_measurement "$FLOOR_MS"; then
    log_fail "the calibration produced a number" "got '$FLOOR_MS'"
    test_summary
fi
[[ "$FLOOR_MS" == "0.0" ]] && FLOOR_MS="1.0"

echo "=== Hook latency ==="
echo "calibration: ${FLOOR_MS}ms (${CALIBRATION_FORKS} forks + one python3 + one read, fastest of 7)"
echo ""
printf '%-26s %11s %12s %10s %9s\n' "hook" "fastest" "median" "x baseline" "ceiling"

# What these ceilings can and cannot catch, stated rather than implied: at 1.4
# times the measured value they catch a doubling and a 50% regression (the
# latter by 2% of margin on a bad run), and they will not see a 30% one. Buying
# that sensitivity means a tighter margin than load invariance can carry.
#
# bias-detector.sh is the exception, at 1.8x. Its cost is the baseline's cost,
# so its ratio is about 1.00 and there is nothing left to normalise: a hook
# that costs what fifty forks cost is not measurable in multiples of fifty
# forks. Observed 1.00 to 1.30x across a 1.92x change in machine speed, so the
# real margin at 1.5x was 1.15x, tight enough to flake. It is guarded mostly by
# the wall-clock backstop, and that is a property of the hook being cheap, not
# a gap in the instrument.
#
# Roughly 1.4 times what the hooks measure today against the basket baseline,
# which leaves room for a slower machine and none for a regression that doubles
# the work. They are meant to be lowered when the number drops, never raised
# when it rises, and the sleeping-hook check below proves the tightest one can
# still fail.

RESULTS=""

# A ratio AND a wall-clock backstop. The ratio survives a slow machine; the
# backstop is what stops a ratio from absolving two seconds of real latency
# because the baseline was slow too.
# A wall-clock backstop, so no ratio can absolve real latency by pointing at a
# slow baseline. Above the slowest measurement here (a write with three
# violations, ~1.7s on a quiet machine), far below the point where a user would
# call the plugin broken, and lowered when the dirty path gets cheaper.
CEILING_MS_BACKSTOP=2500

# It is applied only on a quiet machine, and that is a statement about what a
# wall clock can and cannot attribute. The threshold is well ABOVE this
# machine's idle calibration, not inside its noise: at 12ms against an idle
# spread of 11.7 to 12.9ms, the only ceiling a ratio cannot absolve was armed
# or disarmed by a coin toss, two runs out of six on an idle laptop. Under sustained load every number here
# grows, including the fastest of N runs, and the growth belongs to the machine
# rather than to the code: enforcing an absolute figure there would fail this
# suite for the crime of running after the rest of it, which is how a benchmark
# gets deleted. The ratio still applies in both cases; only the absolute one is
# suspended, and the suspension is printed.
# Derived from this machine's own fastest calibration ever recorded, not from a
# number typed into a file whose thesis is that typed numbers do not travel.
# 210ms is right for this laptop and wrong for a slow CI container, where an
# idle calibration above it would suspend the backstop permanently while the
# output said "busy": a slow machine and a loaded one would be indistinguishable
# forever.
CALIBRATION_FLOOR_FILE="${_PERF_STATE_DIR}/craftsman-perf-calibration"
CALIBRATION_QUIET_MS=210
if [[ -f "$CALIBRATION_FLOOR_FILE" ]]; then
    _seen_floor="$(head -1 "$CALIBRATION_FLOOR_FILE" 2>/dev/null)"
    if _is_measurement "${_seen_floor:-}"; then
        CALIBRATION_QUIET_MS="$(python3 -c "print('%.1f' % (1.5 * $_seen_floor))")"
    fi
fi
# Record the fastest calibration this machine has ever produced, which is the
# closest thing it has to "idle".
if [[ ! -f "$CALIBRATION_FLOOR_FILE" ]] \
    || [[ "$(python3 -c "print(1 if $FLOOR_MS < $(head -1 "$CALIBRATION_FLOOR_FILE" 2>/dev/null || echo 999999) else 0)" 2>/dev/null || echo 0)" -eq 1 ]]; then
    printf '%s\n' "$FLOOR_MS" > "$CALIBRATION_FLOOR_FILE" 2>/dev/null || true
fi
MACHINE_IS_QUIET=$(python3 -c "print(1 if $FLOOR_MS <= $CALIBRATION_QUIET_MS else 0)" 2>/dev/null || echo 0)

# Did the memory actually survive the run that wrote it? A derivation that
# silently keeps falling back to the constant is indistinguishable from no
# derivation at all on a machine where the constant happens to fit, which is
# exactly how it shipped the first time.
CALIBRATION_MEMORY="absent"
if [[ -f "$CALIBRATION_FLOOR_FILE" ]]; then
    _stored="$(head -1 "$CALIBRATION_FLOOR_FILE" 2>/dev/null)"
    _is_measurement "${_stored:-}" && CALIBRATION_MEMORY="$_stored"
fi

measure_hook() {
    local label="$1" ceiling_factor="$2" command="$3"
    local pair fastest median ratio
    pair="$(_min_ms "$command" "$RUNS")"
    fastest="${pair%% *}"
    median="${pair##* }"
    if ! _is_measurement "$fastest" || ! _is_measurement "$median"; then
        # Reported as a failure and NOT carried into the verdict loop. Feeding
        # a zero through it printed `stays under 1.5x the baseline (0ms, 0x)`
        # in green beside the failure, because `0 <= 1.5` is true: a line
        # asserting a hook respects its ceiling when nothing was measured is
        # the same defect this whole file exists to remove, committed by the
        # file itself.
        log_fail "$label was measured" "the timing came back '$pair', so nothing was measured"
        printf '%-26s %9s %10s %9s %8sx\n' "$label" "not" "measured" "-" "$ceiling_factor"
        return 0
    fi
    ratio="$(python3 -c "print('%.2f' % ($fastest / $FLOOR_MS))")"
    # Both, because the gap between the fastest run and the median is the
    # signal that the machine was busy while measuring.
    printf '%-26s %9sms %10sms %9sx %8sx\n' "$label" "$fastest" "$median" "$ratio" "$ceiling_factor"
    RESULTS="${RESULTS}${label}|${fastest}|${ratio}|${ceiling_factor}"$'\n'
}

POST_PAYLOAD="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$PROJECT/src/A.php" "$PROJECT")"
PRE_PAYLOAD="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"<?php\\ndeclare(strict_types=1);\\nfinal class B {}\\n"},"cwd":"%s"}' \
    "$PROJECT/src/B.php" "$PROJECT")"
PROMPT_PAYLOAD='{"prompt":"add a value object for the invoice total"}'

cat > "$PROJECT/src/Dirty.php" <<'PHPDIRTY'
<?php
class Dirty {
    public function setName($name) { $this->name = $name; }
    public function query($id) { return "SELECT * FROM t WHERE id = " . $id; }
}
PHPDIRTY
DIRTY_PAYLOAD="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$PROJECT/src/Dirty.php" "$PROJECT")"

# The ceilings are per operating system, and that is a measured statement
# about what the ratio does and does not absorb. On one machine under load it
# absorbs 94% of the slowdown, because the basket grows the way the hooks grow.
# Across operating systems it absorbs nothing: the same commit measured
# post-write at 3.9x on macOS and 9.5x on an ubuntu runner, where a fork costs
# half as much (calibration 63ms against 135ms) while the hooks cost about the
# same, so the hooks' remaining cost there is not made of forks. Two variances,
# two mechanisms: the ratio for load, a table for the OS. The doubling check
# further down is the one assertion that transfers unchanged.
case "$(uname -s)" in
    Linux)  C_POST=13.5; C_PRE=10.5; C_BIAS=3.7;  C_DIRTY=23 ;;
    *)      C_POST=5.5;  C_PRE=3.2;  C_BIAS=1.8;  C_DIRTY=13 ;;
esac
echo "ceilings for $(uname -s): post-write ${C_POST}x, pre-write ${C_PRE}x, bias ${C_BIAS}x, dirty ${C_DIRTY}x"

measure_hook "post-write-check.sh" "$C_POST" \
    "cd '$PROJECT' && printf '%s' '$POST_PAYLOAD' | bash '$ROOT_DIR/hooks/post-write-check.sh' >/dev/null 2>&1"
measure_hook "pre-write-check.sh" "$C_PRE" \
    "cd '$PROJECT' && printf '%s' '$PRE_PAYLOAD' | bash '$ROOT_DIR/hooks/pre-write-check.sh' >/dev/null 2>&1"
measure_hook "bias-detector.sh" "$C_BIAS" \
    "cd '$PROJECT' && printf '%s' '$PROMPT_PAYLOAD' | bash '$ROOT_DIR/hooks/bias-detector.sh' >/dev/null 2>&1"

# A file that violates nothing measures the floor, and the floor is not what a
# user pays. Every recorded violation starts its own python3 for the metrics
# insert, so the cost of a real write scales with the findings in it: this is
# the path where the remaining latency lives, and no ceiling covered it.
measure_hook "post-write, 3 violations" "$C_DIRTY" \
    "cd '$PROJECT' && printf '%s' '$DIRTY_PAYLOAD' | bash '$ROOT_DIR/hooks/post-write-check.sh' >/dev/null 2>&1"

echo ""
if [[ "$CALIBRATION_MEMORY" == "absent" ]]; then
    echo "calibration memory: none yet, threshold is the ${CALIBRATION_QUIET_MS}ms fallback"
else
    echo "calibration memory: ${CALIBRATION_MEMORY}ms fastest ever seen here, quiet threshold ${CALIBRATION_QUIET_MS}ms"
fi
if [[ "$MACHINE_IS_QUIET" -eq 1 ]]; then
    echo "wall-clock backstop: ${CEILING_MS_BACKSTOP}ms, applied"
else
    echo "wall-clock backstop: suspended, the ${FLOOR_MS}ms calibration says this machine is busy (quiet is <= ${CALIBRATION_QUIET_MS}ms)"
fi
echo ""

if [[ "$REPORT_ONLY" == true ]]; then
    exit 0
fi

while IFS='|' read -r label median ratio ceiling; do
    [[ -z "$label" ]] && continue
    over_backstop=0
    if [[ "$MACHINE_IS_QUIET" -eq 1 ]]; then
        over_backstop=$(python3 -c "print(1 if $median > $CEILING_MS_BACKSTOP else 0)" 2>/dev/null || echo 1)
    fi
    # Decimal, so bash cannot compare it. The ratios are single digits now that
    # the baseline has the hooks' shape, and rounding them to whole numbers
    # threw away most of the resolution the ceiling needs.
    under_ceiling=$(python3 -c "print(1 if $ratio <= $ceiling else 0)" 2>/dev/null || echo 0)
    if [[ "$under_ceiling" -eq 1 && "$over_backstop" -eq 0 ]]; then
        log_pass "$label stays under ${ceiling}x the baseline (${median}ms, ${ratio}x)"
    elif [[ "$over_backstop" -eq 1 ]]; then
        log_fail "$label crossed the wall-clock backstop" \
            "${median}ms, backstop is ${CEILING_MS_BACKSTOP}ms, whatever the ratio says"
    else
        log_fail "$label crossed its ceiling" \
            "${median}ms is ${ratio}x the ${FLOOR_MS}ms baseline, ceiling is ${ceiling}x"
    fi
done <<< "$RESULTS"

# The instrument, seen red on purpose, in the same run that trusts it. A
# ceiling nobody has watched fail is a ceiling nobody knows is wired up.
#
# The synthetic regression is PROPORTIONAL to what was just measured, not a
# fixed 0.4s. A fixed sleep proved the point on an idle laptop and proved
# nothing under load, where the baseline itself grew past it: the check then
# reported that the ceilings could not catch a 400ms regression, which was true
# and useless. Doubling the tightest hook is the regression the tightest ceiling
# exists to catch, and it is the same regression at any machine speed.
TIGHTEST="$(printf '%s' "$RESULTS" | awk -F'|' '
    NF >= 4 && $2 + 0 > 0 { if (best == "" || $2 + 0 < best) { best = $2 + 0; ceiling = $4 } }
    END { printf "%s %s", (best == "" ? 0 : best), (ceiling == "" ? 0 : ceiling) }')"
TIGHTEST_MS="${TIGHTEST%% *}"
SMALLEST_CEILING="${TIGHTEST##* }"

if _is_measurement "$TIGHTEST_MS" && [[ "$TIGHTEST_MS" != "0" ]]; then
    DOUBLE_SECONDS="$(python3 -c "print('%.3f' % (2 * $TIGHTEST_MS / 1000.0))")"
    SLOW_MS="$(_median_ms "sleep $DOUBLE_SECONDS" 3)"
    SLOW_RATIO="$(python3 -c "print('%.2f' % ($SLOW_MS / $FLOOR_MS))" 2>/dev/null || echo 0)"
    crosses=$(python3 -c "print(1 if $SLOW_RATIO > $SMALLEST_CEILING else 0)" 2>/dev/null || echo 0)
    if [[ "$crosses" -eq 1 ]]; then
        log_pass "doubling the tightest hook does cross its ceiling (${SLOW_MS}ms, ${SLOW_RATIO}x > ${SMALLEST_CEILING}x)"
    else
        log_fail "doubling the tightest hook does cross its ceiling" \
            "measured ${SLOW_MS}ms, ${SLOW_RATIO}x, under the ${SMALLEST_CEILING}x ceiling: a doubling would ship unnoticed"
    fi
else
    log_fail "the instrument could be checked against itself" \
        "no measurement to derive a synthetic regression from"
fi

# The memory is asserted, not assumed. Written into the sandbox, it vanished
# with the sandbox and nothing said so.
if [[ "$CALIBRATION_MEMORY" != "absent" ]]; then
    log_pass "the calibration memory survives a run (${CALIBRATION_MEMORY}ms)"
else
    log_fail "the calibration memory survives a run" \
        "nothing at $CALIBRATION_FLOOR_FILE, so the quiet threshold can only ever be the typed constant"
fi

# The published figure has to be the measured one, or it drifts again. These
# four documents quote the benchmark; the assertion is that they quote it at
# all, not that a number in prose equals a number measured here, which would
# fail on every machine.
for doc in "CLAUDE.md" "README.md" "README.fr.md" "docs/guides/semantic-level-1-5.md"; do
    if grep -q "tests/perf/test-hook-latency.sh" "$ROOT_DIR/$doc" 2>/dev/null; then
        log_pass "$doc points at the benchmark for its latency figure"
    else
        log_fail "$doc points at the benchmark for its latency figure" \
            "still quoting a number with no measurement behind it"
    fi
done

test_summary
