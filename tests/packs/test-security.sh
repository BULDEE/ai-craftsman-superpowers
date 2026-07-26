#!/usr/bin/env bash
# =============================================================================
# Security validator tests (SEC001, SEC002, SEC003) - symfony and react packs
#
# A security gate is only useful if it is trusted: every true positive below is
# paired with safe counter-examples that MUST stay silent (env reads, bound
# parameters, documentation placeholders, plain UI copy).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

TEST_DIR="/tmp/craftsman-security-test-$$"
mkdir -p "$TEST_DIR"

VIOLATIONS=()
WARNINGS=()
add_violation() { VIOLATIONS+=("$1: $2"); }
add_warning() { WARNINGS+=("$1: $2"); }
line_has_ignore() { return 1; }
file_has_ignore() { return 1; }
reset_findings() { VIOLATIONS=(); WARNINGS=(); }

source "$ROOT_DIR/packs/symfony/hooks/security-validator.sh"
source "$ROOT_DIR/packs/react/hooks/security-validator.sh"

echo "=== PHP security (symfony pack) ==="

cat > "$TEST_DIR/Secret.php" <<'PHP'
<?php
final class Secret {
    private string $apiKey = "sk_live_abcdef1234567890abcdef";
    private string $password = "hunter2secret";
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Secret.php"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC001"; then
    log_pass "SEC001: hardcoded secret blocked"
else
    log_fail "SEC001" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/Clean.php" <<'PHP'
<?php
final class Clean {
    public function key(): string {
        return $_ENV['API_KEY'] ?? getenv('API_KEY');
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Clean.php"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "env var reads are safe (no false positive)"
else
    log_fail "false positive" "${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/Eval.php" <<'PHP'
<?php
final class Runner {
    public function run(string $code): void { eval($code); }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Eval.php"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC002"; then
    log_pass "SEC002: eval on variable blocked"
else
    log_fail "SEC002" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/Sqli.php" <<'PHP'
<?php
final class Repo {
    public function find(string $name): array {
        return $this->db->query("SELECT id FROM users WHERE name = '" . $name . "'");
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Sqli.php"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC003"; then
    log_pass "SEC003: SQL concatenation blocked"
else
    log_fail "SEC003" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/SqliInterp.php" <<'PHP'
<?php
final class InterpRepo {
    public function find(string $name): array {
        return $this->connection->executeQuery("SELECT id FROM users WHERE name = '$name'");
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/SqliInterp.php"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC003"; then
    log_pass "SEC003: SQL string interpolation blocked"
else
    log_fail "SEC003 interpolation" "${VIOLATIONS[*]:-none}"
fi

echo ""
echo "=== PHP safe counter-examples ==="

cat > "$TEST_DIR/Bound.php" <<'PHP'
<?php
final class BoundRepo {
    public function find(string $name, int $limit): array {
        $statement = $this->connection->prepare("SELECT id FROM users WHERE name = :name LIMIT :max");
        $statement->bindValue('name', $name);
        $statement->bindValue('max', $limit);
        return $this->connection->executeQuery("SELECT id FROM users WHERE id = ?", [$this->currentId]);
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Bound.php"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "bound parameters are safe (no SEC003 false positive)"
else
    log_fail "bound params false positive" "${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/Copy.php" <<'PHP'
<?php
final class Copy {
    public function label(string $item): string {
        $message = "Delete from cart: " . $item;
        return $message . " - Update your basket";
    }
    public function hint(): string {
        return "Ask an admin to evaluate($this->request) your access";
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Copy.php"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "plain UI copy is safe (no SEC002/SEC003 false positive)"
else
    log_fail "ui copy false positive" "${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/Config.php" <<'PHP'
<?php
final class Config {
    public function credentials(): array {
        return [
            'api_key' => $this->parameters->get('app.api_key'),
            'password' => "%env(DATABASE_PASSWORD)%",
            'token' => getenv('SERVICE_TOKEN'),
        ];
    }
}
PHP
reset_findings
pack_validate_php_security "$TEST_DIR/Config.php"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "container parameters and env placeholders are safe"
else
    log_fail "config false positive" "${VIOLATIONS[*]}"
fi

echo ""
echo "=== TS security (react pack) ==="

cat > "$TEST_DIR/token.ts" <<'TS'
const config = { token: "ghp_AbCdEf1234567890AbCdEf1234567890AbCd" };
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/token.ts"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC001"; then
    log_pass "SEC001 (ts): token literal blocked"
else
    log_fail "SEC001 ts" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/sqli.ts" <<'TS'
export const find = (db: Db, name: string) =>
    db.query(`SELECT id FROM users WHERE name = '${name}'`);
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/sqli.ts"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC003"; then
    log_pass "SEC003 (ts): template-literal SQL with variable blocked"
else
    log_fail "SEC003 ts" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/concat.ts" <<'TS'
export const find = (db: Db, name: string) =>
    db.execute("SELECT id FROM users WHERE name = " + name);
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/concat.ts"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC003"; then
    log_pass "SEC003 (ts): SQL string concatenation blocked"
else
    log_fail "SEC003 ts concat" "${VIOLATIONS[*]:-none}"
fi

cat > "$TEST_DIR/runner.ts" <<'TS'
export const run = (source: string) => new Function(source)();
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/runner.ts"
if printf '%s\n' "${VIOLATIONS[@]:-}" | grep -q "SEC002"; then
    log_pass "SEC002 (ts): new Function on input blocked"
else
    log_fail "SEC002 ts" "${VIOLATIONS[*]:-none}"
fi

echo ""
echo "=== TS safe counter-examples ==="

cat > "$TEST_DIR/env.ts" <<'TS'
export const apiKey = process.env.API_KEY ?? "";
export const token = import.meta.env.VITE_SERVICE_TOKEN;
export const secret: string = process.env.SESSION_SECRET as string;
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/env.ts"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "process.env / import.meta.env reads are safe (no false positive)"
else
    log_fail "env false positive" "${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/docs.ts" <<'TS'
// Never call eval(userInput): pass the value to a parser instead.
export const example = {
    apiKey: "YOUR_API_KEY_HERE",
    token: "<your-token-here>",
};
export const confirmLabel = (name: string) => `Delete ${name} from your list?`;
export const summary = (count: number) => `Update ${count} rows before you continue`;
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/docs.ts"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "doc placeholders and UI copy are safe (no false positive)"
else
    log_fail "docs false positive" "${VIOLATIONS[*]}"
fi

cat > "$TEST_DIR/params.ts" <<'TS'
export const find = (db: Db, id: string) =>
    db.query("SELECT id FROM users WHERE id = $1", [id]);
export const update = (db: Db, id: string, name: string) =>
    db.query("UPDATE users SET name = $2 WHERE id = $1", [id, name]);
TS
reset_findings
pack_validate_typescript_security "$TEST_DIR/params.ts"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "positional placeholders are safe (no SEC003 false positive)"
else
    log_fail "placeholder false positive" "${VIOLATIONS[*]}"
fi

echo ""
echo "=== Ignore directive ==="

cat > "$TEST_DIR/Ignored.php" <<'PHP'
<?php
final class Ignored {
    private string $apiKey = "sk_live_abcdef1234567890abcdef"; // craftsman-ignore: SEC001
}
PHP
reset_findings
line_has_ignore() { [[ "$1" == *"craftsman-ignore: $2"* ]]; }
pack_validate_php_security "$TEST_DIR/Ignored.php"
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
    log_pass "craftsman-ignore: SEC001 respected"
else
    log_fail "ignore directive" "${VIOLATIONS[*]}"
fi
line_has_ignore() { return 1; }

rm -rf "$TEST_DIR"

test_summary
