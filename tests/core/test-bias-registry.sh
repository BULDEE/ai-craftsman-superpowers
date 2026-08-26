#!/usr/bin/env bash
# =============================================================================
# Bias Registry Tests (ADR-0030)
# The engine knows the SHAPE of the pattern set and none of its content:
# adding a language is adding a conf file, with no edit to any hook.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

REGISTRY="$ROOT_DIR/hooks/lib/bias-registry.sh"
FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bias-registry-fixtures.XXXXXX")
trap 'rm -rf "$FIXTURE_DIR"; cleanup_test_env' EXIT

cat > "$FIXTURE_DIR/aa.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("aa")
BIAS_AA_MODE="curated"
BIAS_AA_ACCELERATION="aa-fast|aa-hurry"
BIAS_AA_SCOPE_CREEP="aa-also-add"
EOF

cat > "$FIXTURE_DIR/bb.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("bb")
BIAS_BB_MODE="signal"
BIAS_BB_ACCELERATION="bb-schnell"
EOF

echo ""
echo "=== Bias Registry Tests ==="
echo ""

# shellcheck source=/dev/null
source "$REGISTRY"
bias_registry_init "$FIXTURE_DIR"

echo "--- Mode separation and aggregation ---"

pat=$(bias_combined_pattern ACCELERATION curated) \
    && assert_contains "curated ACCELERATION holds aa's pattern" "$pat" "aa-fast" \
    || log_fail "curated ACCELERATION should resolve" "returned non-zero"
pat=$(bias_combined_pattern ACCELERATION curated) || pat=""
assert_not_contains "curated ACCELERATION excludes signal-mode bb" "$pat" "bb-schnell"

pat=$(bias_combined_pattern ACCELERATION signal) \
    && assert_contains "signal ACCELERATION holds bb's pattern" "$pat" "bb-schnell" \
    || log_fail "signal ACCELERATION should resolve" "returned non-zero"

echo ""
echo "--- Empty-category guard (an empty regex matches EVERYTHING) ---"

if echo "totally clean prompt" | grep -Eq ""; then
    log_pass "precondition: empty pattern does match any prompt (the trap is real)"
else
    log_fail "precondition" "empty pattern no longer matches all; guard rationale changed"
fi

if pat=$(bias_combined_pattern OVER_OPT curated); then
    log_fail "OVER_OPT with no contributor must return non-zero" "got: '$pat'"
else
    log_pass "unclaimed category returns non-zero (caller skips the grep)"
fi

grep_ran=false
if pat=$(bias_combined_pattern OVER_OPT curated); then
    grep_ran=true
    echo "x" | grep -Eq "$pat" || true
fi
if [[ "$grep_ran" == "false" ]]; then
    log_pass "caller idiom never reaches grep for an unclaimed category"
else
    log_fail "caller idiom" "grep ran against an unclaimed category"
fi

echo ""
echo "--- Add a language without touching code ---"

cat > "$FIXTURE_DIR/cc.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("cc")
BIAS_CC_MODE="signal"
BIAS_CC_OVER_OPT="cc-generic"
EOF

bias_registry_init "$FIXTURE_DIR"
pat=$(bias_combined_pattern OVER_OPT signal) \
    && assert_contains "new conf file registers with zero code edits" "$pat" "cc-generic" \
    || log_fail "cc.conf should register" "OVER_OPT signal returned non-zero"

echo ""
echo "--- Re-init resets state (no leakage across pattern sets) ---"

EMPTY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bias-registry-empty.XXXXXX")
bias_registry_init "$EMPTY_DIR"
if bias_combined_pattern ACCELERATION curated >/dev/null; then
    log_fail "re-init on empty dir" "previous set's patterns leaked"
else
    log_pass "re-init on empty dir clears every previous pattern"
fi
rm -rf "$EMPTY_DIR"

echo ""
echo "--- set -u safety: partial conf declares only some categories ---"

bias_registry_init "$FIXTURE_DIR"
if out=$(bias_combined_pattern SCOPE_CREEP signal 2>&1); then
    log_fail "SCOPE_CREEP signal (nobody declares it)" "resolved unexpectedly: '$out'"
else
    if [[ -z "$out" ]]; then
        log_pass "missing BIAS_<LANG>_<CATEGORY> vars never trip set -u"
    else
        log_fail "set -u safety" "stderr/stdout not clean: '$out'"
    fi
fi

test_summary
