#!/usr/bin/env bash
# =============================================================================
# Persistence validator tests (LAYER004, DB001, DB002, DB003) - both packs
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

TEST_DIR="/tmp/craftsman-persistence-test-$$"
mkdir -p "$TEST_DIR/src/Domain" "$TEST_DIR/src/Infrastructure" "$TEST_DIR/migrations" "$TEST_DIR/src/domain"

VIOLATIONS=()
WARNINGS=()
add_violation() { VIOLATIONS+=("$1: $2"); }
add_warning() { WARNINGS+=("$1: $2"); }
line_has_ignore() { return 1; }
file_has_ignore() { return 1; }
reset_findings() { VIOLATIONS=(); WARNINGS=(); }

source "$ROOT_DIR/packs/symfony/hooks/persistence-validator.sh"
source "$ROOT_DIR/packs/react/hooks/persistence-validator.sh"

echo "=== PHP Persistence (symfony pack) ==="

cat > "$TEST_DIR/src/Domain/Order.php" <<'PHP'
<?php
declare(strict_types=1);
namespace App\Domain;
final class Order {
    public function total(): int {
        $rows = $this->connection->executeQuery("SELECT price FROM order_lines");
        return 0;
    }
}
PHP
reset_findings
pack_validate_php_persistence "$TEST_DIR/src/Domain/Order.php"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "LAYER004"; then
    log_pass "LAYER004: raw SQL in Domain blocked"
else
    log_fail "LAYER004" "not detected: ${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/src/Infrastructure/ReportQuery.php" <<'PHP'
<?php
declare(strict_types=1);
namespace App\Infrastructure;
final class ReportQuery {
    public function all(): array {
        return $this->connection->fetchAllAssociative("SELECT * FROM reports");
    }
}
PHP
reset_findings
pack_validate_php_persistence "$TEST_DIR/src/Infrastructure/ReportQuery.php"
if printf '%s\n' "${WARNINGS[@]:-}" | grep -q "DB001"; then
    log_pass "DB001: SELECT * warned"
else
    log_fail "DB001" "not detected: ${WARNINGS[*]:-none}"
fi
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "LAYER004"; then
    log_fail "LAYER004 scope" "SQL in Infrastructure wrongly flagged"
else
    log_pass "LAYER004 scope: SQL in Infrastructure allowed"
fi

cat > "$TEST_DIR/migrations/Version20260726Migration.php" <<'PHP'
<?php
declare(strict_types=1);
final class Version20260726Migration {
    public function up(Schema $schema): void {}
}
PHP
reset_findings
pack_validate_php_persistence "$TEST_DIR/migrations/Version20260726Migration.php"
if printf '%s\n' "${WARNINGS[@]:-}" | grep -q "DB002"; then
    log_pass "DB002: migration without down() warned"
else
    log_fail "DB002" "not detected: ${WARNINGS[*]:-none}"
fi

cat > "$TEST_DIR/src/Infrastructure/Sync.php" <<'PHP'
<?php
declare(strict_types=1);
namespace App\Infrastructure;
final class Sync {
    public function run(array $orders): void {
        foreach ($orders as $order) {
            $customer = $this->customers->findOneBy(['id' => $order->customerId()]);
        }
    }
}
PHP
reset_findings
pack_validate_php_persistence "$TEST_DIR/src/Infrastructure/Sync.php"
if printf '%s\n' "${WARNINGS[@]:-}" | grep -q "DB003"; then
    log_pass "DB003: query in loop warned (N+1)"
else
    log_fail "DB003" "not detected: ${WARNINGS[*]:-none}"
fi

echo ""
echo "=== TypeScript Persistence (react pack) ==="

cat > "$TEST_DIR/src/domain/user.ts" <<'TS'
import { PrismaClient } from "@prisma/client";
export const findUser = (id: string) => new PrismaClient().user.findUnique({ where: { id } });
TS
reset_findings
pack_validate_typescript_persistence "$TEST_DIR/src/domain/user.ts"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "LAYER004"; then
    log_pass "LAYER004 (ts): db client in domain/ blocked"
else
    log_fail "LAYER004 ts" "not detected: ${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/sync.ts" <<'TS'
export async function syncAll(ids: string[], db: Db) {
    for (const id of ids) {
        const user = await db.query("SELECT * FROM users WHERE id = $1", [id]);
    }
}
TS
reset_findings
pack_validate_typescript_persistence "$TEST_DIR/sync.ts"
if printf '%s\n' "${WARNINGS[@]:-}" | grep -q "DB001"; then
    log_pass "DB001 (ts): SELECT * warned"
else
    log_fail "DB001 ts" "not detected: ${WARNINGS[*]:-none}"
fi
if printf '%s\n' "${WARNINGS[@]:-}" | grep -q "DB003"; then
    log_pass "DB003 (ts): awaited query in loop warned"
else
    log_fail "DB003 ts" "not detected: ${WARNINGS[*]:-none}"
fi

# Clean file produces no findings
cat > "$TEST_DIR/src/Domain/Price.php" <<'PHP'
<?php
declare(strict_types=1);
namespace App\Domain;
final class Price {
    private function __construct(private readonly int $amount) {}
    public static function fromInt(int $amount): self { return new self($amount); }
}
PHP
reset_findings
pack_validate_php_persistence "$TEST_DIR/src/Domain/Price.php"
if [[ ${#VIOLATIONS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    log_pass "clean Value Object: zero persistence findings"
else
    log_fail "false positive" "V=${VIOLATIONS[*]:-} W=${WARNINGS[*]:-}"
fi

rm -rf "$TEST_DIR"

test_summary
