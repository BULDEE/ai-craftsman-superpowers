#!/usr/bin/env bash
# =============================================================================
# Session State Library Tests
# Tests hooks/lib/session_state.py shared module.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

LIB="$ROOT_DIR/hooks/lib/session_state.py"
TEMP_DIR="/tmp/craftsman-session-state-tests-$$"
mkdir -p "$TEMP_DIR"

trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo ""
echo "=== Session State Library Tests ==="

SF="$TEMP_DIR/session-state.json"

# =============================================================================
# Test 1: Write + Read JSON roundtrip
# =============================================================================
echo ""
echo "--- Write + Read ---"

python3 "$LIB" write "$SF" '{"key": "value", "count": 42}'
result=$(python3 "$LIB" read "$SF" key)
if [[ "$result" == "value" ]]; then
    log_pass "write + read string value"
else
    log_fail "write + read string value" "got: $result"
fi

result=$(python3 "$LIB" read "$SF" count)
if [[ "$result" == "42" ]]; then
    log_pass "read numeric value"
else
    log_fail "read numeric value" "got: $result"
fi

result=$(python3 "$LIB" read "$SF" missing "default_val")
if [[ "$result" == "default_val" ]]; then
    log_pass "read missing key returns default"
else
    log_fail "read missing key returns default" "got: $result"
fi

# =============================================================================
# Test 2: read-json
# =============================================================================
echo ""
echo "--- Read JSON ---"

result=$(python3 "$LIB" read-json "$SF")
if echo "$result" | jq -e '.key == "value"' >/dev/null 2>&1; then
    log_pass "read-json returns valid JSON with correct data"
else
    log_fail "read-json" "got: $result"
fi

# =============================================================================
# Test 3: Merge
# =============================================================================
echo ""
echo "--- Merge ---"

python3 "$LIB" merge "$SF" new_key '"hello"'
result=$(python3 "$LIB" read "$SF" new_key)
if [[ "$result" == "hello" ]]; then
    log_pass "merge adds new key"
else
    log_fail "merge adds new key" "got: $result"
fi

original=$(python3 "$LIB" read "$SF" key)
if [[ "$original" == "value" ]]; then
    log_pass "merge preserves existing keys"
else
    log_fail "merge preserves existing keys" "got: $original"
fi

# =============================================================================
# Test 4: Append with max size
# =============================================================================
echo ""
echo "--- Append ---"

rm -f "$SF"
python3 "$LIB" write "$SF" '{}'

for i in $(seq 1 5); do
    python3 "$LIB" append "$SF" items "{\"id\": $i}" 3
done

result=$(python3 "$LIB" read "$SF" items)
count=$(echo "$result" | jq 'length')
if [[ "$count" == "3" ]]; then
    log_pass "append respects max size (3)"
else
    log_fail "append max size" "expected 3, got: $count"
fi

first_id=$(echo "$result" | jq '.[0].id')
if [[ "$first_id" == "3" ]]; then
    log_pass "append keeps most recent items (first=3)"
else
    log_fail "append keeps most recent" "expected first_id=3, got: $first_id"
fi

# =============================================================================
# Test 5: Increment
# =============================================================================
echo ""
echo "--- Increment ---"

rm -f "$SF"
python3 "$LIB" write "$SF" '{}'

python3 "$LIB" increment "$SF" counter >/dev/null
python3 "$LIB" increment "$SF" counter >/dev/null
result=$(python3 "$LIB" increment "$SF" counter)
if [[ "$result" == "3" ]]; then
    log_pass "increment returns correct count after 3 calls"
else
    log_fail "increment" "expected 3, got: $result"
fi

# =============================================================================
# Test 6: check-flag
# =============================================================================
echo ""
echo "--- Check Flag ---"

python3 "$LIB" write "$SF" '{"verified": true, "debug": false}'

result=$(python3 "$LIB" check-flag "$SF" verified)
if [[ "$result" == "true" ]]; then
    log_pass "check-flag true"
else
    log_fail "check-flag true" "got: $result"
fi

result=$(python3 "$LIB" check-flag "$SF" debug)
if [[ "$result" == "false" ]]; then
    log_pass "check-flag false"
else
    log_fail "check-flag false" "got: $result"
fi

result=$(python3 "$LIB" check-flag "$SF" missing)
if [[ "$result" == "false" ]]; then
    log_pass "check-flag missing key returns false"
else
    log_fail "check-flag missing" "got: $result"
fi

# =============================================================================
# Test 7: Atomic write safety (file not corrupted on error)
# =============================================================================
echo ""
echo "--- Atomic Safety ---"

python3 "$LIB" write "$SF" '{"safe": true}'
# Read non-existent file returns empty state
result=$(python3 "$LIB" read-json "$TEMP_DIR/nonexistent.json")
if [[ "$result" == "{}" ]]; then
    log_pass "read non-existent file returns empty state"
else
    log_fail "read non-existent" "got: $result"
fi

# Original file still intact
result=$(python3 "$LIB" check-flag "$SF" safe)
if [[ "$result" == "true" ]]; then
    log_pass "original file preserved after non-existent read"
else
    log_fail "original file preserved" "got: $result"
fi

# =============================================================================
# Test 8: record-violation + detect-patterns
# =============================================================================
echo ""
echo "--- Record Violation & Detect Patterns ---"

rm -f "$SF"

# Record 3 violations for PHP001 in same directory
python3 "$LIB" record-violation "$SF" "src/Entity/A.php" "src/Entity" '["PHP001"]'
python3 "$LIB" record-violation "$SF" "src/Entity/B.php" "src/Entity" '["PHP001"]'
python3 "$LIB" record-violation "$SF" "src/Entity/C.php" "src/Entity" '["PHP001", "PHP002"]'

# Check violations recorded
violations=$(python3 "$LIB" read "$SF" blocked_violations)
count=$(echo "$violations" | jq 'keys | length')
if [[ "$count" == "3" ]]; then
    log_pass "record-violation: 3 files tracked"
else
    log_fail "record-violation: expected 3 files" "got: $count"
fi

# Check patterns tracked
patterns=$(python3 "$LIB" read "$SF" patterns)
php001_files=$(echo "$patterns" | jq '.PHP001."src/Entity" | length')
if [[ "$php001_files" == "3" ]]; then
    log_pass "record-violation: PHP001 tracks 3 files in dir"
else
    log_fail "record-violation: PHP001 dir files" "got: $php001_files"
fi

# Detect cross-file patterns (3+ files with PHP001)
result=$(python3 "$LIB" detect-patterns "$SF")
if echo "$result" | grep -q "PATTERN:PHP001:3 files"; then
    log_pass "detect-patterns: finds PATTERN:PHP001:3 files"
else
    log_fail "detect-patterns: expected PATTERN:PHP001:3 files" "got: $result"
fi

if echo "$result" | grep -q "DIR_PATTERN:PHP001:src/Entity:3 files"; then
    log_pass "detect-patterns: finds DIR_PATTERN for src/Entity"
else
    log_fail "detect-patterns: expected DIR_PATTERN" "got: $result"
fi

# No duplicate entries on re-record
python3 "$LIB" record-violation "$SF" "src/Entity/A.php" "src/Entity" '["PHP001"]'
patterns=$(python3 "$LIB" read "$SF" patterns)
php001_files=$(echo "$patterns" | jq '.PHP001."src/Entity" | length')
if [[ "$php001_files" == "3" ]]; then
    log_pass "record-violation: no duplicates on re-record"
else
    log_fail "record-violation: duplicates detected" "got: $php001_files"
fi

# =============================================================================
# Test 9: Invalid command
# =============================================================================
echo ""
echo "--- Error Handling ---"

python3 "$LIB" invalid-cmd 2>/dev/null
exit_code=$?
if [[ "$exit_code" != "0" ]]; then
    log_pass "invalid command exits non-zero ($exit_code)"
else
    log_fail "invalid command should fail" "got exit 0"
fi

test_summary
