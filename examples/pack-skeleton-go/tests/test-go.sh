#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; ((TESTS_PASSED++)); }
log_fail() { echo "  ✗ $1 — $2"; ((TESTS_FAILED++)); }

echo "=== Go Pack Tests ==="

# Source validator
source "$PACK_DIR/hooks/go-validator.sh"

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

# Test: GO003 detects init()
tmpfile=$(mktemp /tmp/test_go_XXXXXX)
cat > "$tmpfile" << 'GO'
package main

func init() {
    setupGlobals()
}
GO
VIOLATIONS=""
pack_validate_go "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "GO003"; then
    log_pass "GO003: detects init() function"
else
    log_fail "GO003: detects init()" "not detected"
fi

# Test: clean Go file passes
tmpfile2=$(mktemp /tmp/test_go_XXXXXX)
cat > "$tmpfile2" << 'GO'
package main

func main() {
    fmt.Println("hello")
}
GO
VIOLATIONS=""
pack_validate_go "$tmpfile2"
if [[ -z "$(echo -e "$VIOLATIONS" | grep -v '^$' | grep -v '^WARN:')" ]]; then
    log_pass "Clean Go file passes validation"
else
    log_fail "Clean Go file" "got: $(echo -e "$VIOLATIONS")"
fi

# Cleanup
rm -f "$tmpfile" "$tmpfile2"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
