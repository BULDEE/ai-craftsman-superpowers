#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo "  ✓ $1"; ((TESTS_PASSED++)); }
log_fail() { echo "  ✗ $1 — $2"; ((TESTS_FAILED++)); }

echo "=== Python Pack Tests ==="

# Source validator
source "$PACK_DIR/hooks/python-validator.sh"

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

# Test: PY001 detects bare except
tmpfile=$(mktemp /tmp/test_py_XXXXXX)
cat > "$tmpfile" << 'PY'
try:
    do_something()
except:
    pass
PY
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY001"; then
    log_pass "PY001: detects bare except"
else
    log_fail "PY001: detects bare except" "not detected"
fi

# Test: PY002 detects mutable default
tmpfile2=$(mktemp /tmp/test_py_XXXXXX)
cat > "$tmpfile2" << 'PY'
def process(items=[]):
    items.append("new")
    return items
PY
VIOLATIONS=""
pack_validate_python "$tmpfile2"
if echo -e "$VIOLATIONS" | grep -q "PY002"; then
    log_pass "PY002: detects mutable default argument"
else
    log_fail "PY002: detects mutable default" "not detected"
fi

# Test: PY003 detects wildcard import
tmpfile3=$(mktemp /tmp/test_py_XXXXXX)
cat > "$tmpfile3" << 'PY'
from os.path import *
PY
VIOLATIONS=""
pack_validate_python "$tmpfile3"
if echo -e "$VIOLATIONS" | grep -q "PY003"; then
    log_pass "PY003: detects wildcard import"
else
    log_fail "PY003: detects wildcard import" "not detected"
fi

# Test: clean file passes
tmpfile4=$(mktemp /tmp/test_py_XXXXXX)
cat > "$tmpfile4" << 'PY'
from typing import Optional

def greet(name: str) -> str:
    return f"Hello, {name}"
PY
VIOLATIONS=""
pack_validate_python "$tmpfile4"
if [[ -z "$(echo -e "$VIOLATIONS" | grep -v '^$' | grep -v '^WARN:')" ]]; then
    log_pass "Clean Python file passes validation"
else
    log_fail "Clean Python file" "got: $(echo -e "$VIOLATIONS")"
fi

# Cleanup
rm -f "$tmpfile" "$tmpfile2" "$tmpfile3" "$tmpfile4"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
