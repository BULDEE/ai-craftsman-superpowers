#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Symfony Pack Tests ==="

# Source validators
source "$ROOT_DIR/packs/symfony/hooks/php-validator.sh"
source "$ROOT_DIR/packs/symfony/hooks/layer-validator.sh"
source "$ROOT_DIR/packs/symfony/static-analysis/phpstan.sh"

# Provide mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="test"

# Test: pack.yml exists and is valid
if [[ -f "$ROOT_DIR/packs/symfony/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "file not found"
fi

# Test: pack_validate_php detects missing strict_types
tmpfile=$(mktemp /tmp/test_php_XXXXXX)
cat > "$tmpfile" << 'PHP'
<?php
class Foo {}
PHP
VIOLATIONS=""
pack_validate_php "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "PHP001"; then
    log_pass "PHP001: detects missing strict_types"
else
    log_fail "PHP001: detects missing strict_types" "not detected"
fi

# Test: pack_validate_php detects non-final class
if echo -e "$VIOLATIONS" | grep -q "PHP002"; then
    log_pass "PHP002: detects non-final class"
else
    log_fail "PHP002: detects non-final class" "not detected"
fi

# Test: pack_validate_php passes clean file
tmpfile2=$(mktemp /tmp/test_php_XXXXXX)
cat > "$tmpfile2" << 'PHP'
<?php

declare(strict_types=1);

final class Foo
{
    private function __construct() {}
}
PHP
VIOLATIONS=""
pack_validate_php "$tmpfile2"
if [[ -z "$(echo -e "$VIOLATIONS" | grep -v '^$' | grep -v '^WARN:')" ]]; then
    log_pass "Clean PHP file passes validation"
else
    log_fail "Clean PHP file passes validation" "got: $(echo -e "$VIOLATIONS")"
fi

# Test: pack_validate_php_layers detects domain→infra import
tmpfile3=$(mktemp /tmp/test_php_XXXXXX)
cat > "$tmpfile3" << 'PHP'
<?php
namespace App\Domain\Entity;
use App\Infrastructure\Repository\FooRepo;
PHP
VIOLATIONS=""
pack_validate_php_layers "$tmpfile3"
if echo -e "$VIOLATIONS" | grep -q "LAYER001"; then
    log_pass "LAYER001: detects Domain→Infrastructure import"
else
    log_fail "LAYER001: detects Domain→Infrastructure import" "not detected"
fi

# Test: _pack_sa_phpstan_map_error mapping
result=$(_pack_sa_phpstan_map_error "src/Foo.php:42:Undefined variable \$bar")
if [[ "$result" == "PHPSTAN002" ]]; then
    log_pass "PHPStan: undefined variable → PHPSTAN002"
else
    log_fail "PHPStan: undefined variable → PHPSTAN002" "got $result"
fi

# Test: All referenced files in pack.yml exist
echo ""
echo "--- File references ---"
for f in hooks/php-validator.sh hooks/layer-validator.sh static-analysis/phpstan.sh; do
    if [[ -f "$ROOT_DIR/packs/symfony/$f" ]]; then
        log_pass "Reference exists: $f"
    else
        log_fail "Reference exists: $f" "file not found"
    fi
done

# Test: scaffold-types directory
if [[ -f "$ROOT_DIR/packs/symfony/commands/scaffold-types/api-resource.md" ]]; then
    log_pass "api-resource scaffold type exists"
else
    log_fail "api-resource scaffold type exists" "file not found"
fi

# Cleanup
rm -f "$tmpfile" "$tmpfile2" "$tmpfile3"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
