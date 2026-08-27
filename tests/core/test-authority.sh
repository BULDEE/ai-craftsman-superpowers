#!/usr/bin/env bash
# =============================================================================
# Authority hierarchy tests.
#
# The owner's rule: a user directive outranks a deterministic rule, which
# outranks a learned instinct, which outranks a model judgment. A model may
# warn, ask, or propose an instinct. It may never overrule a directive and it
# may never block.
#
# These tests exist because an invariant a caller can opt out of is a comment.
# Each one is written so that removing the wiring makes it fail, not so that it
# passes against a gate that never ran.
#
# craftsman-ignore: SH004
# The fixtures below contain `eval` on purpose: SH004 is the blocking rule this
# suite uses to prove that the deterministic tier still blocks and that a user
# directive can outrank it. A test for a rule has to contain what the rule
# looks for.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

HOOK="$ROOT_DIR/hooks/post-write-check.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/authority.XXXXXX")
trap 'rm -rf "$WORK"; cleanup_test_env' EXIT

run_on() {
    local file="$1"
    echo "{\"tool_input\":{\"file_path\":\"$file\"}}" | bash "$HOOK" 2>&1
    return $?
}

exit_of() {
    local file="$1"
    echo "{\"tool_input\":{\"file_path\":\"$file\"}}" | bash "$HOOK" >/dev/null 2>&1
    echo $?
}

echo ""
echo "=== Authority Hierarchy Tests ==="
echo ""
echo "--- the fourth tier stays unimplemented until it has a caller ---"

# A first version of this suite asserted on an add_advice function. It had no
# caller: instincts surface at SessionStart and the model tier waits on the
# evaluation harness, so the seam was speculative generality and was cut. What
# survives is the constraint, recorded where the next implementer will read it.
if grep -q "no wiring to CRITICAL_VIOLATIONS" "$HOOK"; then
    log_pass "the constraint on a future semantic tier is recorded in the hook"
else
    log_fail "the constraint on a future semantic tier is recorded" \
        "whoever wires the model tier has nothing telling them it cannot block"
fi

echo "--- the deterministic tier CAN still block (the check can fail) ---"

# Liveness: without this, every absence assertion above would also pass against
# a hook that does nothing at all.
cat > "$WORK/blocking.sh" <<'PROBE'
#!/usr/bin/env bash
demo() {
    eval "$1"
}
PROBE
blocking_exit=$(exit_of "$WORK/blocking.sh")
if [[ "$blocking_exit" == "2" ]]; then
    log_pass "precondition: a deterministic rule still blocks with exit 2"
else
    log_fail "precondition: a deterministic rule still blocks" \
        "got exit $blocking_exit, so the absence assertions prove nothing"
fi

echo ""
echo "--- a user directive outranks every tier ---"

mkdir -p "$WORK/relaxed"
cat > "$WORK/relaxed/blocking.sh" <<'PROBE'
#!/usr/bin/env bash
demo() {
    eval "$1"
}
PROBE
# The `rules:` key is required: the parser asks for that section by name, so a
# bare top-level entry is read as nothing and the rule keeps blocking. The
# verdict message used to suggest exactly that bare form, and this fixture is
# what caught it.
cat > "$WORK/relaxed/.craft-rules.yml" <<'RULES'
rules:
  SH004: ignore
RULES

relaxed_out=$(run_on "$WORK/relaxed/blocking.sh")
relaxed_exit=$(exit_of "$WORK/relaxed/blocking.sh")
if [[ "$relaxed_exit" == "0" ]] && ! echo "$relaxed_out" | grep -q "SH004"; then
    log_pass "a rule the user set to ignore reaches no tier and does not block"
else
    log_fail "a user directive must outrank the deterministic tier" \
        "exit=$relaxed_exit output=$(echo "$relaxed_out" | head -2)"
fi

echo ""
echo "--- advice never raises the exit code ---"

cat > "$WORK/advisory.sh" <<'PROBE'
#!/usr/bin/env bash
set -u
pv="short name, advisory only"
echo "$pv"
PROBE
advisory_exit=$(exit_of "$WORK/advisory.sh")
advisory_out=$(run_on "$WORK/advisory.sh")
if [[ "$advisory_exit" == "0" ]]; then
    log_pass "an advisory-only file exits 0"
else
    log_fail "an advisory-only file must exit 0" "got exit $advisory_exit"
fi

if echo "$advisory_out" | grep -q "BLOCKED"; then
    log_fail "an advisory verdict must not render as BLOCKED" "$(echo "$advisory_out" | head -1)"
else
    log_pass "an advisory verdict does not render as BLOCKED"
fi

test_summary
