#!/usr/bin/env bash
# =============================================================================
# Rule calibration: the carve-outs and suppressions added in v4.0.2.
#
# A rule that fires where the framework leaves no alternative is not finding a
# defect, it is wrong about the file, and the developer learns to suppress it.
# Every carve-out below is paired with the case it must NOT silence, so a
# carve-out that grew too wide fails here rather than in someone's codebase.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

TEST_DIR="/tmp/craftsman-calibration-$$"
mkdir -p "$TEST_DIR"

VIOLATIONS=()
WARNINGS=()
FILE_PATTERN="src/**"
add_violation() { VIOLATIONS+=("$1: $2"); }
add_warning() { WARNINGS+=("$1: $2"); }
metrics_record_violation() { return 0; }
reset_findings() { VIOLATIONS=(); WARNINGS=(); }
line_has_ignore() {
    local line="$1" rule="$2"
    [[ "$line" == *"craftsman-ignore: ${rule}"* ]]
}

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/packs/symfony/hooks/php-validator.sh"
source "$ROOT_DIR/packs/symfony/hooks/layer-validator.sh"
source "$ROOT_DIR/packs/react/hooks/typescript-validator.sh"

fired() {
    printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "^${1}:"
}

echo ""
echo "=== PHP002 does not demand that a Doctrine entity be final ==="

cat > "$TEST_DIR/Order.php" <<'PHP'
<?php
declare(strict_types=1);

#[ORM\Entity(repositoryClass: OrderRepository::class)]
class Order
{
    private int $id;
}
PHP
reset_findings
_check_php002 "$TEST_DIR/Order.php"
if ! fired "PHP002"; then
    log_pass "an ORM entity is left alone (the proxy has to extend it)"
else
    log_fail "PHP002" "told a Doctrine entity to be final: ${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/Annotated.php" <<'PHP'
<?php
declare(strict_types=1);

/**
 * @ORM\Entity
 */
class LegacyOrder
{
    private int $id;
}
PHP
reset_findings
_check_php002 "$TEST_DIR/Annotated.php"
if ! fired "PHP002"; then
    log_pass "the annotation form is recognised too"
else
    log_fail "PHP002" "${VIOLATIONS[*]}"
fi

# The counter-test: an ordinary class must still be caught, or the carve-out
# above is satisfied by a rule that stopped working entirely.
cat > "$TEST_DIR/Service.php" <<'PHP'
<?php
declare(strict_types=1);

class OrderService
{
    public function handle(): void {}
}
PHP
reset_findings
_check_php002 "$TEST_DIR/Service.php"
if fired "PHP002"; then
    log_pass "an ordinary class is still told to be final"
else
    log_fail "PHP002" "the rule no longer fires at all"
fi

echo ""
echo "=== TS002 does not fight the framework over a default export ==="

REQUIRED_DEFAULT=(page.tsx layout.tsx route.ts middleware.ts Button.stories.tsx vite.config.ts)
for name in "${REQUIRED_DEFAULT[@]}"; do
    printf 'export default function X() { return null }\n' > "$TEST_DIR/$name"
    reset_findings
    _check_ts002 "$TEST_DIR/$name"
    if ! fired "TS002"; then
        log_pass "no finding in ${name} (the framework resolves the default)"
    else
        log_fail "TS002" "fired on ${name}, where a default export is mandatory"
    fi
done

mkdir -p "$TEST_DIR/pages"
printf 'export default function Home() { return null }\n' > "$TEST_DIR/pages/index.tsx"
reset_findings
_check_ts002 "$TEST_DIR/pages/index.tsx"
if ! fired "TS002"; then
    log_pass "no finding under pages/ (the pages router resolves the default)"
else
    log_fail "TS002" "fired under pages/"
fi

printf 'export default class Widget {}\n' > "$TEST_DIR/Widget.ts"
reset_findings
_check_ts002 "$TEST_DIR/Widget.ts"
if fired "TS002"; then
    log_pass "an ordinary module is still told to use named exports"
else
    log_fail "TS002" "the rule no longer fires at all"
fi

printf 'export default class Widget {} // craftsman-ignore: TS002\n' > "$TEST_DIR/Ignored.ts"
reset_findings
_check_ts002 "$TEST_DIR/Ignored.ts"
if ! fired "TS002"; then
    log_pass "craftsman-ignore: TS002 is honoured on the line"
else
    log_fail "TS002" "line-level suppression ignored"
fi

# A suppressed line must not cover a later one that carries no marker.
cat > "$TEST_DIR/Two.ts" <<'TS'
export default class A {} // craftsman-ignore: TS002
export default class B {}
TS
reset_findings
_check_ts002 "$TEST_DIR/Two.ts"
if fired "TS002"; then
    log_pass "a suppressed line does not cover the rest of the file"
else
    log_fail "TS002" "one ignore silenced a second unsuppressed occurrence"
fi

echo ""
echo "=== TS003 takes a line-level suppression ==="

printf 'const n = value!.length\nconst m = other!\n' > "$TEST_DIR/Bang.ts"
reset_findings
_check_ts003 "$TEST_DIR/Bang.ts"
if fired "TS003"; then
    log_pass "a non-null assertion is still reported"
else
    log_fail "TS003" "the rule no longer fires at all"
fi

printf 'const m = other! // craftsman-ignore: TS003\n' > "$TEST_DIR/BangIgnored.ts"
reset_findings
_check_ts003 "$TEST_DIR/BangIgnored.ts"
if ! fired "TS003"; then
    log_pass "craftsman-ignore: TS003 is honoured on the line"
else
    log_fail "TS003" "line-level suppression ignored"
fi

echo ""
echo "=== The layer rules follow the project's own root namespace ==="

LAYER_PROJECT="$TEST_DIR/acme"
mkdir -p "$LAYER_PROJECT/src/Domain"
cat > "$LAYER_PROJECT/composer.json" <<'JSON'
{"autoload": {"psr-4": {"Acme\\Billing\\": "src/"}}}
JSON
cat > "$LAYER_PROJECT/src/Domain/Invoice.php" <<'PHP'
<?php
declare(strict_types=1);

namespace Acme\Billing\Domain;

use Acme\Billing\Infrastructure\Doctrine\InvoiceRepository;

final class Invoice {}
PHP
reset_findings
pack_validate_php_layers "$LAYER_PROJECT/src/Domain/Invoice.php"
if fired "LAYER001"; then
    log_pass "a renamed root namespace is still checked (Acme\\Billing, not App)"
else
    log_fail "LAYER001" "the rule only ever worked on the Symfony skeleton default"
fi

cat > "$LAYER_PROJECT/src/Domain/Clean.php" <<'PHP'
<?php
declare(strict_types=1);

namespace Acme\Billing\Domain;

use Acme\Billing\Domain\Money;

final class Clean {}
PHP
reset_findings
pack_validate_php_layers "$LAYER_PROJECT/src/Domain/Clean.php"
if ! fired "LAYER001"; then
    log_pass "an in-layer import is not a violation"
else
    log_fail "LAYER001" "false positive: ${VIOLATIONS[*]}"
fi

APP_PROJECT="$TEST_DIR/skeleton"
mkdir -p "$APP_PROJECT/src/Domain"
cat > "$APP_PROJECT/src/Domain/User.php" <<'PHP'
<?php
declare(strict_types=1);

namespace App\Domain;

use App\Infrastructure\Doctrine\UserRepository;

final class User {}
PHP
reset_findings
pack_validate_php_layers "$APP_PROJECT/src/Domain/User.php"
if fired "LAYER001"; then
    log_pass "the App fallback still applies with no composer.json to read"
else
    log_fail "LAYER001" "the default root regressed"
fi

rm -rf "$TEST_DIR"
test_summary
