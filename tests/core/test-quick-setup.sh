#!/usr/bin/env bash
# =============================================================================
# Tests for /craftsman:setup --quick mode
# Validates that quick-setup content is present in setup.md.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

SETUP_CMD="$ROOT_DIR/skills/setup/SKILL.md"

echo ""
echo "=== Quick Setup Tests ==="

# --- File exists ---

if [[ -f "$SETUP_CMD" ]]; then
    log_pass "setup.md exists"
else
    log_fail "setup.md missing"
    test_summary
fi

# --- Quick mode documented ---

if grep -q '\-\-quick' "$SETUP_CMD"; then
    log_pass "--quick flag documented"
else
    log_fail "--quick flag not documented in setup.md"
fi

# --- Auto-detect stack ---

if grep -q 'composer.json' "$SETUP_CMD" && grep -q 'package.json' "$SETUP_CMD"; then
    log_pass "auto-detect uses composer.json and package.json"
else
    log_fail "auto-detect missing stack detection files"
fi

# --- Git user name extraction ---

if grep -q 'git config user.name' "$SETUP_CMD"; then
    log_pass "extracts name from git config"
else
    log_fail "missing git config user.name extraction"
fi

# --- Smart defaults ---

if grep -q 'strict' "$SETUP_CMD"; then
    log_pass "defaults to strict mode"
else
    log_fail "missing strict default"
fi

if grep -q 'acceleration' "$SETUP_CMD" && grep -q 'scope_creep' "$SETUP_CMD"; then
    log_pass "all biases enabled by default"
else
    log_fail "missing default biases"
fi

# --- Config guard ---

if grep -q '\-\-force' "$SETUP_CMD"; then
    log_pass "--force override documented"
else
    log_fail "missing --force flag for existing config"
fi

# --- Summary output ---

if grep -q 'Quick Setup Complete' "$SETUP_CMD"; then
    log_pass "quick setup summary output present"
else
    log_fail "missing quick setup summary"
fi

# --- Both modes documented ---

if grep -q 'Full interactive setup' "$SETUP_CMD" && grep -q 'Zero-question' "$SETUP_CMD"; then
    log_pass "both modes documented in modes table"
else
    log_fail "missing modes documentation table"
fi

# --- Situational onboarding (v4.3) ---

grep -q "craftsman-conventions.sh signals" "$SETUP_CMD" \
    && log_pass "setup consults situational signals" \
    || log_fail "signals step" "missing"

grep -q -- "--global" "$SETUP_CMD" \
    && log_pass "setup documents --global workshop profile" \
    || log_fail "--global" "missing"

grep -q "preferred_tools:" "$SETUP_CMD" \
    && log_pass "workshop profile records preferred_tools" \
    || log_fail "preferred_tools key" "missing"

SITU_COUNT=0
grep -qc "AskUserQuestion" "$SETUP_CMD" >/dev/null && \
SITU_COUNT=$(grep -c "Existing project or a new one\|Prototype or heading to production\|Solo or team\|Maximum help or maximum autonomy" "$SETUP_CMD")
[[ "$SITU_COUNT" -eq 4 ]] \
    && log_pass "exactly 4 situational questions documented" \
    || log_fail "situational questions" "found $SITU_COUNT"

grep -q "guided: true" "$SETUP_CMD" \
    && log_pass "guided mode key documented" \
    || log_fail "guided" "missing"

grep -q "ratchet.py.*init\|craftsman-baseline" "$SETUP_CMD" \
    && log_pass "setup bootstraps the ratchet baseline" \
    || log_fail "baseline bootstrap" "missing"

grep -q "committed" "$SETUP_CMD" \
    && log_pass "baseline commit instruction present" \
    || log_fail "baseline commit instruction" "missing"

test_summary
