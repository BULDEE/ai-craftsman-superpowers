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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-perf.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"

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
_median_ms() {
    local command="$1" runs="$2"
    python3 - "$command" "$runs" <<'PY'
import subprocess, sys, time
command, runs = sys.argv[1], int(sys.argv[2])
samples = []
for _ in range(runs):
    started = time.time()
    subprocess.run(["bash", "-c", command], capture_output=True)
    samples.append((time.time() - started) * 1000)
samples.sort()
print("%.1f" % samples[len(samples) // 2])
PY
}

# Calibration: what one bash process costs on this machine, right now. Every
# ceiling below is a multiple of this.
FLOOR_MS="$(_median_ms "true" 11)"
if [[ -z "$FLOOR_MS" ]] || [[ "$FLOOR_MS" == "0.0" ]]; then
    FLOOR_MS="1.0"
fi

echo "=== Hook latency ==="
echo "calibration: one bash process = ${FLOOR_MS}ms (median of 11)"
echo ""
printf '%-26s %10s %12s %10s\n' "hook" "median" "x baseline" "ceiling"

# The ceilings are roughly 1.4 times what the hooks measure today, which leaves
# room for a slower machine and none for a regression that doubles the work.
# They are meant to be lowered when the number drops, not raised when it rises.

RESULTS=""

measure_hook() {
    local label="$1" ceiling_factor="$2" command="$3"
    local median ratio
    median="$(_median_ms "$command" "$RUNS")"
    ratio="$(python3 -c "print('%.0f' % (${median:-0} / ${FLOOR_MS}))")"
    printf '%-26s %9sms %11sx %9sx\n' "$label" "$median" "$ratio" "$ceiling_factor"
    RESULTS="${RESULTS}${label}|${median}|${ratio}|${ceiling_factor}"$'\n'
}

POST_PAYLOAD="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$PROJECT/src/A.php" "$PROJECT")"
PRE_PAYLOAD="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"<?php\\ndeclare(strict_types=1);\\nfinal class B {}\\n"},"cwd":"%s"}' \
    "$PROJECT/src/B.php" "$PROJECT")"
PROMPT_PAYLOAD='{"prompt":"add a value object for the invoice total"}'

measure_hook "post-write-check.sh" 220 \
    "cd '$PROJECT' && printf '%s' '$POST_PAYLOAD' | bash '$ROOT_DIR/hooks/post-write-check.sh' >/dev/null 2>&1"
measure_hook "pre-write-check.sh" 110 \
    "cd '$PROJECT' && printf '%s' '$PRE_PAYLOAD' | bash '$ROOT_DIR/hooks/pre-write-check.sh' >/dev/null 2>&1"
measure_hook "bias-detector.sh" 70 \
    "cd '$PROJECT' && printf '%s' '$PROMPT_PAYLOAD' | bash '$ROOT_DIR/hooks/bias-detector.sh' >/dev/null 2>&1"

echo ""

if [[ "$REPORT_ONLY" == true ]]; then
    exit 0
fi

while IFS='|' read -r label median ratio ceiling; do
    [[ -z "$label" ]] && continue
    if [[ "$ratio" -le "$ceiling" ]]; then
        log_pass "$label stays under ${ceiling}x the baseline (${median}ms, ${ratio}x)"
    else
        log_fail "$label crossed its ceiling" \
            "${median}ms is ${ratio}x the ${FLOOR_MS}ms baseline, ceiling is ${ceiling}x"
    fi
done <<< "$RESULTS"

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
