#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Python Pack Tests ==="

# Source validator
source "$ROOT_DIR/packs/python/hooks/python-validator.sh"

# Provide mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="test"

# Test: pack.yml exists
if [[ -f "$ROOT_DIR/packs/python/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "file not found"
fi

# Test: PY001 detects short variable names
tmpfile=$(mktemp /tmp/test_py_XXXXXX.py)
cat > "$tmpfile" << 'PYTHON'
def process():
    ab = 42
    cd = "hello"
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY001"; then
    log_pass "PY001: detects short variable names"
else
    log_fail "PY001: detects short variable names" "not detected"
fi

# Test: PY001 allows conventional names
cat > "$tmpfile" << 'PYTHON'
for i in range(10):
    x = i * 2
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY001"; then
    log_fail "PY001: allows conventional names" "false positive on i, x"
else
    log_pass "PY001: allows conventional names"
fi

# Test: PY002 detects long functions
cat > "$tmpfile" << 'PYTHON'
def very_long_function():
    line1 = 1
    line2 = 2
    line3 = 3
    line4 = 4
    line5 = 5
    line6 = 6
    line7 = 7
    line8 = 8
    line9 = 9
    line10 = 10
    line11 = 11
    line12 = 12
    line13 = 13
    line14 = 14
    line15 = 15
    line16 = 16
    line17 = 17
    line18 = 18
    line19 = 19
    line20 = 20
    line21 = 21
    line22 = 22
    line23 = 23
    line24 = 24
    line25 = 25
    line26 = 26
    return line26
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY002"; then
    log_pass "PY002: detects long functions"
else
    log_fail "PY002: detects long functions" "not detected"
fi

# Test: PY004 detects bare except
cat > "$tmpfile" << 'PYTHON'
try:
    do_something()
except:
    pass
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY004"; then
    log_pass "PY004: detects bare except"
else
    log_fail "PY004: detects bare except" "not detected"
fi

# Test: PY005 detects mutable default arguments
cat > "$tmpfile" << 'PYTHON'
def add_item(item, items=[]):
    items.append(item)
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PY005"; then
    log_pass "PY005: detects mutable default arguments"
else
    log_fail "PY005: detects mutable default arguments" "not detected"
fi

# Test: WARN-PY001 detects too many parameters
cat > "$tmpfile" << 'PYTHON'
def too_many(a, b, c, d, e):
    pass
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "WARN-PY001"; then
    log_pass "WARN-PY001: detects 4+ parameters"
else
    log_fail "WARN-PY001: detects 4+ parameters" "not detected"
fi

# Test: Clean Python file passes without violations
cat > "$tmpfile" << 'PYTHON'
"""Clean module."""

def calculate_total(items: list) -> int:
    total_amount = 0
    for item in items:
        total_amount += item.price
    return total_amount
PYTHON
VIOLATIONS=""
pack_validate_python "$tmpfile"
if [[ -z "$VIOLATIONS" ]]; then
    log_pass "Clean Python file: no violations"
else
    log_fail "Clean Python file: no violations" "got: $(echo -e "$VIOLATIONS")"
fi

rm -f "$tmpfile"
echo "=== Python Pack Tests Complete ==="
