#!/usr/bin/env bash
# =============================================================================
# The runner must actually run every test this repository ships.
#
# Nine suites were defined in run-tests.sh and never called from main():
# hostile-repo, ratchet, design-panel, okf-knowledge, dashboard,
# tooling-detect, verify-loop, observation, instincts. The suite reported
# 213/0 while the entire hostile-repository security suite sat unexecuted.
# A green suite that skips a third of its files is worse than a red one: it
# reports coverage it does not have.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

RUNNER="$ROOT_DIR/tests/run-tests.sh"

echo ""
echo "=== Every test function the runner defines is called ==="

DEFINED=$(grep -oE "^test_[a-z_0-9]+\(\)" "$RUNNER" | tr -d '()' | sort -u)
CALLED=$(sed -n '/^main()/,/^}/p' "$RUNNER" | grep -oE "^[[:space:]]+test_[a-z_0-9]+$" | tr -d ' ' | sort -u)

if [[ -z "$DEFINED" || -z "$CALLED" ]]; then
    log_fail "could not read the runner's functions" \
        "defined='${DEFINED//$'\n'/,}' called='${CALLED//$'\n'/,}' - the comparison would pass vacuously"
    test_summary
fi

# test_skill_structure is called from the per-skill loop, not from main's list.
ORPHANS=$(comm -23 <(printf '%s\n' "$DEFINED") <(printf '%s\n' "$CALLED") \
    | grep -v '^test_skill_structure$' || true)

if [[ -z "$ORPHANS" ]]; then
    log_pass "no test function is defined and then never called"
else
    log_fail "dead test functions" "$(printf '%s' "$ORPHANS" | tr '\n' ' ')"
fi

echo ""
echo "=== Every test file is reachable from the runner ==="

# Pack suites are globbed by test_pack_suites, so tests/packs/ is covered by
# construction. Every other directory names its files one by one and is where a
# new file goes unnoticed.
#
# tests/templates/ was missing from this list, which is exactly how
# test-templates.sh came to sit unexecuted with four red assertions while the
# suite reported green. This guard existed to catch that and did not, because
# it enumerated the directories instead of discovering them.
#
# tests/lib/ is excluded on purpose: it holds test-helpers.sh, a library that
# the suites source rather than a suite the runner calls.
UNREFERENCED=""
CHECKED=0
for script in "$ROOT_DIR"/tests/core/test-*.sh "$ROOT_DIR"/tests/ci/test-*.sh \
              "$ROOT_DIR"/tests/adapters/test-*.sh "$ROOT_DIR"/tests/templates/test-*.sh; do
    [[ -f "$script" ]] || continue
    CHECKED=$((CHECKED + 1))
    name="$(basename "$script")"
    # This file is the guard itself; it is named below like any other.
    grep -q "$name" "$RUNNER" || UNREFERENCED="${UNREFERENCED} ${name}"
done

if [[ $CHECKED -eq 0 ]]; then
    log_fail "no test file found" "the check above verified nothing"
elif [[ -z "$UNREFERENCED" ]]; then
    log_pass "all ${CHECKED} test files outside tests/packs are named in the runner"
else
    log_fail "test files the runner never mentions" "$UNREFERENCED"
fi

echo ""
echo "=== The pack suite loop still globs a real directory ==="

PACK_COUNT=$(find "$ROOT_DIR/tests/packs" -maxdepth 1 -name 'test-*.sh' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$PACK_COUNT" -gt 0 ]] && grep -q 'packs_dir"/test-\*\.sh' "$RUNNER"; then
    log_pass "${PACK_COUNT} pack suite(s) are picked up by the glob"
else
    log_fail "pack suites unreachable" \
        "found ${PACK_COUNT} file(s) and the runner's glob did not match"
fi

test_summary
