#!/usr/bin/env bash
# =============================================================================
# No subtest may leave a trace outside its own temp directories.
#
# A test that writes into the checkout or into ~/.claude makes every test that
# runs after it depend on the order. That is how a suite gets a failure it
# cannot reproduce: the script passes alone, fails in the suite, and the advice
# "run it yourself" cannot work because the state that caused it is gone.
#
# This audit runs every subtest the suite runs and reports the ones that leave
# something behind. It costs a full suite run, so it is opt-in:
#
#   CRAFTSMAN_ISOLATION_AUDIT=1 bash tests/core/test-suite-isolation.sh
#
# Without the variable it exits 0 after saying so, which keeps the default
# suite fast while leaving the audit one command away.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

if [[ "${CRAFTSMAN_ISOLATION_AUDIT:-0}" != "1" ]]; then
    echo ""
    echo "Suite isolation audit skipped (costs a full suite run)."
    echo "Run it with: CRAFTSMAN_ISOLATION_AUDIT=1 bash tests/core/test-suite-isolation.sh"
    exit 0
fi

echo ""
echo "=== Every subtest leaves the checkout and ~/.claude as it found them ==="

# The same list the runner uses, read from the runner so the two cannot drift.
mapfile -t SUBTESTS < <(
    grep -oE 'run_subtest "[^"]+" "\$SCRIPT_DIR/[^"]+"' "$ROOT_DIR/tests/run-tests.sh" \
        | sed 's/.*\$SCRIPT_DIR\///; s/"$//'
)

if [[ ${#SUBTESTS[@]} -eq 0 ]]; then
    log_fail "no subtest found in run-tests.sh" \
        "the audit below would pass without running anything"
    test_summary
fi
log_pass "found ${#SUBTESTS[@]} subtest(s) to audit"

# A signature of everything a subtest could plausibly disturb: the working
# tree as git sees it, and the top level of ~/.claude.
state_signature() {
    git -C "$ROOT_DIR" status --porcelain
    echo "---"
    find "${HOME}/.claude" -maxdepth 1 -type f -exec sh -c \
        'printf "%s %s\n" "$(shasum -a 256 "$1" | cut -d" " -f1)" "$1"' _ {} \; 2>/dev/null | sort
}

OFFENDERS=()
for rel in "${SUBTESTS[@]}"; do
    script="$ROOT_DIR/tests/$rel"
    [[ -f "$script" ]] || continue

    before=$(state_signature)
    bash "$script" >/dev/null 2>&1
    after=$(state_signature)

    if [[ "$before" == "$after" ]]; then
        log_pass "$rel leaves no trace"
    else
        OFFENDERS+=("$rel")
        log_fail "$rel mutates shared state" \
            "$(diff <(printf '%s' "$before") <(printf '%s' "$after") | head -6 | tr '\n' ' ')"
    fi
done

echo ""
if [[ ${#OFFENDERS[@]} -eq 0 ]]; then
    echo "No subtest mutates shared state: the suite's result cannot depend on order."
else
    echo "Order-dependent surface: ${OFFENDERS[*]}"
fi

test_summary
