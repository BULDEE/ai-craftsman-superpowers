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
echo ""
echo "=== A rule that cannot run says so ==="

# PY001, PY002, GOD001 and NEST001 all shell out to python3, and each returned
# silently without it. On a machine with no python3 the pack reported every
# file clean and nothing said otherwise, which is the failure the sqlite3 guard
# in metrics-db.sh closed for the metrics layer.
PY_NOPY=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-nopy.XXXXXX")
for _bin in bash sh grep sed awk cat head tail wc tr cut sort ls rm mkdir dirname basename; do
    ln -sf "$(command -v "$_bin")" "$PY_NOPY/$_bin" 2>/dev/null
done
printf 'def f():\n    ab = 1\n    return ab\n' > "$PY_NOPY/sample.py"

NOPY_ERR=$(PATH="$PY_NOPY" "$PY_NOPY/bash" -c "
    cd '$ROOT_DIR'
    source packs/python/hooks/python-validator.sh
    add_violation() { :; }; add_warning() { :; }
    pack_validate_python '$PY_NOPY/sample.py'
    pack_validate_python '$PY_NOPY/sample.py'
" 2>&1 >/dev/null)

if printf '%s' "$NOPY_ERR" | grep -q "python3 not found"; then
    log_pass "a missing python3 is announced instead of silently skipping the rules"
else
    log_fail "silent fail-open" "the pack reported clean with no python3 and said nothing"
fi

# Announced once per process: the point is to be noticed, not to be noisy.
NOPY_COUNT=$(printf '%s' "$NOPY_ERR" | grep -c "python3 not found")
if [[ "$NOPY_COUNT" -eq 1 ]]; then
    log_pass "the warning fires once per process, not once per rule per file"
else
    log_fail "noisy warning" "$NOPY_COUNT announcements for two files"
fi
rm -rf "$PY_NOPY"

echo "=== Python Pack Tests Complete ==="
