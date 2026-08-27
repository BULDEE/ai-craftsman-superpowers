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

pattern=$(bias_combined_pattern ACCELERATION curated) \
    && assert_contains "curated ACCELERATION holds aa's pattern" "$pattern" "aa-fast" \
    || log_fail "curated ACCELERATION should resolve" "returned non-zero"
pattern=$(bias_combined_pattern ACCELERATION curated) || pattern=""
assert_not_contains "curated ACCELERATION excludes signal-mode bb" "$pattern" "bb-schnell"

pattern=$(bias_combined_pattern ACCELERATION signal) \
    && assert_contains "signal ACCELERATION holds bb's pattern" "$pattern" "bb-schnell" \
    || log_fail "signal ACCELERATION should resolve" "returned non-zero"

echo ""
echo "--- Empty-category guard (an empty regex matches EVERYTHING) ---"

if echo "totally clean prompt" | grep -Eq ""; then
    log_pass "precondition: empty pattern does match any prompt (the trap is real)"
else
    log_fail "precondition" "empty pattern no longer matches all; guard rationale changed"
fi

if pattern=$(bias_combined_pattern OVER_OPT curated); then
    log_fail "OVER_OPT with no contributor must return non-zero" "got: '$pattern'"
else
    log_pass "unclaimed category returns non-zero (caller skips the grep)"
fi

grep_ran=false
if pattern=$(bias_combined_pattern OVER_OPT curated); then
    grep_ran=true
    echo "x" | grep -Eq "$pattern" || true
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
pattern=$(bias_combined_pattern OVER_OPT signal) \
    && assert_contains "new conf file registers with zero code edits" "$pattern" "cc-generic" \
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

echo ""
echo "--- BCP 47 tags: a region or script subtag must register, not vanish ---"

# fr-CA, pt-BR, zh-Hant are the tags a contributor reaches for the moment a
# dialect diverges. A tag is not a bash identifier, so the suffix is derived;
# before that derivation existed, such a conf registered nothing and the hook
# still exited 0. Silent absence is the failure this feature exists to remove.
BCP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bias-registry-bcp47.XXXXXX")
cat > "$BCP_DIR/fr-CA.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("fr-CA")
BIAS_FR_CA_MODE="signal"
BIAS_FR_CA_ACCELERATION="ca-presse|Ca-presse"
EOF

bias_registry_init "$BCP_DIR"
pattern=$(bias_combined_pattern ACCELERATION signal) \
    && assert_contains "fr-CA registers under a sanitized suffix" "$pattern" "ca-presse" \
    || log_fail "fr-CA should register" "ACCELERATION signal returned non-zero"

if [[ "${BIAS_REGISTERED_LANGS[0]:-}" == "fr-CA" ]]; then
    log_pass "the tag itself stays BCP 47, only the variable suffix is sanitized"
else
    log_fail "tag preservation" "got '${BIAS_REGISTERED_LANGS[0]:-}' instead of fr-CA"
fi

echo ""
echo "--- a conf whose variables do not match its tag is reported, not ignored ---"

cat > "$BCP_DIR/zz-broken.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("zz-broken")
BIAS_ZZ-BROKEN_MODE="signal"
BIAS_ZZ-BROKEN_ACCELERATION="never-loaded"
EOF

audit_err=$(bias_registry_init "$BCP_DIR" 2>&1 >/dev/null)
if echo "$audit_err" | grep -q "zz-broken"; then
    log_pass "a half-registered language is named on stderr"
else
    log_fail "broken conf must be reported" "stderr was: '$audit_err'"
fi

pattern=$(bias_combined_pattern ACCELERATION signal) || pattern=""
assert_not_contains "a broken conf contributes no pattern" "$pattern" "never-loaded"

if [[ " ${BIAS_REGISTERED_LANGS[*]} " != *" zz-broken "* ]]; then
    log_pass "the broken tag is dropped, never left half-registered"
else
    log_fail "broken tag dropped" "still present: ${BIAS_REGISTERED_LANGS[*]}"
fi
rm -rf "$BCP_DIR"

test_summary
