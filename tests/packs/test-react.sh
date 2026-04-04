#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== React Pack Tests ==="

# Source validators
source "$ROOT_DIR/packs/react/hooks/typescript-validator.sh"
source "$ROOT_DIR/packs/react/hooks/layer-validator.sh"
source "$ROOT_DIR/packs/react/static-analysis/eslint.sh"

# Provide mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="test"

# Test: pack.yml exists
if [[ -f "$ROOT_DIR/packs/react/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "file not found"
fi

# Test: pack_validate_typescript detects 'any' type
tmpfile=$(mktemp /tmp/test_ts_XXXXXX)
cat > "$tmpfile" << 'TS'
const foo: any = "bar";
export default foo;
TS
VIOLATIONS=""
pack_validate_typescript "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "TS001"; then
    log_pass "TS001: detects 'any' type"
else
    log_fail "TS001: detects 'any' type" "not detected"
fi

# Test: detects default export
if echo -e "$VIOLATIONS" | grep -q "TS002"; then
    log_pass "TS002: detects default export"
else
    log_fail "TS002: detects default export" "not detected"
fi

# Test: clean TS file passes
tmpfile2=$(mktemp /tmp/test_ts_XXXXXX)
cat > "$tmpfile2" << 'TS'
export const foo: string = "bar";
TS
VIOLATIONS=""
pack_validate_typescript "$tmpfile2"
if [[ -z "$(echo -e "$VIOLATIONS" | grep -v '^$' | grep -v '^WARN:')" ]]; then
    log_pass "Clean TS file passes validation"
else
    log_fail "Clean TS file passes validation" "got: $(echo -e "$VIOLATIONS")"
fi

# Test: layer violation
tmpdir="/tmp/test_domain_$$"
tmpfile3="$tmpdir/domain/test.ts"
mkdir -p "$(dirname "$tmpfile3")"
cat > "$tmpfile3" << 'TS'
import { Repo } from "../infrastructure/repo";
TS
VIOLATIONS=""
pack_validate_typescript_layers "$tmpfile3"
if echo -e "$VIOLATIONS" | grep -q "LAYER001"; then
    log_pass "LAYER001: detects domain→infrastructure import"
else
    log_fail "LAYER001: detects domain→infrastructure import" "not detected"
fi

# Test: ESLint error mapping
result=$(_pack_sa_eslint_map_error "src/foo.ts: line 5, Error - msg (no-explicit-any)")
if [[ "$result" == "ESLINT001" ]]; then
    log_pass "ESLint: no-explicit-any → ESLINT001"
else
    log_fail "ESLint: no-explicit-any → ESLINT001" "got $result"
fi

# Test: All referenced files exist
echo ""
echo "--- File references ---"
for f in hooks/typescript-validator.sh hooks/layer-validator.sh static-analysis/eslint.sh; do
    if [[ -f "$ROOT_DIR/packs/react/$f" ]]; then
        log_pass "Reference exists: $f"
    else
        log_fail "Reference exists: $f" "file not found"
    fi
done

# Cleanup
rm -f "$tmpfile" "$tmpfile2"
rm -rf "$tmpdir"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
