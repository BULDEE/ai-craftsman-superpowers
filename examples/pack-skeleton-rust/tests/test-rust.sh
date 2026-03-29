#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; ((TESTS_PASSED++)); }
log_fail() { echo "  ✗ $1 — $2"; ((TESTS_FAILED++)); }

echo "=== Rust Pack Tests ==="

# Source validator
source "$PACK_DIR/hooks/rust-validator.sh"

# Mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }

# Test: pack.yml exists
if [[ -f "$PACK_DIR/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "not found"
fi

# Test: RUST001 detects unwrap
# Note: tmpfile must not contain "test" in path — validator skips test files
tmpfile=$(mktemp /tmp/prod_rust_XXXXXX)
cat > "$tmpfile" << 'RUST'
fn main() {
    let value = some_result().unwrap();
}
RUST
VIOLATIONS=""
pack_validate_rust "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "RUST001"; then
    log_pass "RUST001: detects .unwrap()"
else
    log_fail "RUST001: detects .unwrap()" "not detected"
fi

# Test: RUST002 detects panic in lib
tmpfile2=$(mktemp /tmp/lib_rust_XXXXXX)
cat > "$tmpfile2" << 'RUST'
pub fn calculate(x: i32) -> i32 {
    if x < 0 {
        panic!("negative input");
    }
    x * 2
}
RUST
VIOLATIONS=""
pack_validate_rust "$tmpfile2"
if echo -e "$VIOLATIONS" | grep -q "RUST002"; then
    log_pass "RUST002: detects panic! in lib code"
else
    log_fail "RUST002: detects panic!" "not detected"
fi

# Test: clean file passes
tmpfile3=$(mktemp /tmp/prod_rust_clean_XXXXXX)
cat > "$tmpfile3" << 'RUST'
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
RUST
VIOLATIONS=""
pack_validate_rust "$tmpfile3"
if [[ -z "$(echo -e "$VIOLATIONS" | grep -v '^$' | grep -v '^WARN:')" ]]; then
    log_pass "Clean Rust file passes validation"
else
    log_fail "Clean Rust file" "got: $(echo -e "$VIOLATIONS")"
fi

# Cleanup
rm -f "$tmpfile" "$tmpfile2" "$tmpfile3"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
