#!/usr/bin/env bash
# =============================================================================
# Tooling detector tests: consume the project's declared tools, suggest only
# when nothing is declared, never install.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

DETECT="$ROOT_DIR/hooks/lib/tooling_detect.py"
FIXTURE="/tmp/craftsman-tooling-test-$$"
mkdir -p "$FIXTURE/php" "$FIXTURE/js-bare" "$FIXTURE/empty"

cat > "$FIXTURE/php/composer.json" <<'JSON'
{ "require-dev": { "phpstan/phpstan": "^1.0", "qossmic/deptrac": "^2.0", "phpunit/phpunit": "^11" } }
JSON

cat > "$FIXTURE/js-bare/package.json" <<'JSON'
{ "dependencies": { "react": "^19.0.0" } }
JSON

echo "=== Declared tooling is consumed ==="

OUT=$(python3 "$DETECT" "$FIXTURE/php")
if echo "$OUT" | grep -q "PHPStan" && echo "$OUT" | grep -q "vendor/bin/phpstan analyse"; then
    log_pass "PHP: declared PHPStan detected with its report command"
else
    log_fail "php detection" "$OUT"
fi

if echo "$OUT" | grep -q "Deptrac"; then
    log_pass "PHP: declared Deptrac detected"
else
    log_fail "deptrac detection" "$OUT"
fi

if echo "$OUT" | grep -q "Suggested"; then
    log_fail "suggestion scope" "should not suggest when tools are declared"
else
    log_pass "no suggestions when the project already declares tools"
fi

echo ""
echo "=== Suggestions only when nothing is declared ==="

OUT=$(python3 "$DETECT" "$FIXTURE/js-bare")
if echo "$OUT" | grep -q "no quality tool declared"; then
    log_pass "bare JS project: reports nothing declared"
else
    log_fail "bare project" "$OUT"
fi

if echo "$OUT" | grep -q "npm install --save-dev eslint"; then
    log_pass "bare JS project: suggests ESLint install command"
else
    log_fail "suggestion" "$OUT"
fi

if echo "$OUT" | grep -qi "installing\.\.\.\|installed successfully"; then
    log_fail "no-install guarantee" "detector must never install anything"
else
    log_pass "detector suggests, never installs"
fi

echo ""
echo "=== Fallback and JSON mode ==="

OUT=$(python3 "$DETECT" "$FIXTURE/empty")
if echo "$OUT" | grep -q "built-in churn ranking is the fallback"; then
    log_pass "no manifest: falls back to built-in ranking"
else
    log_fail "fallback" "$OUT"
fi

if python3 "$DETECT" "$FIXTURE/php" --json | jq -e '.languages.php.declared[0].report_command' >/dev/null 2>&1; then
    log_pass "--json emits machine-readable report commands"
else
    log_fail "json mode" "invalid JSON output"
fi

echo ""
echo "=== Security tooling is always surfaced ==="

cat > "$FIXTURE/php/composer.json" <<'JSON'
{ "require-dev": { "phpstan/phpstan": "^1.0", "roave/security-advisories": "dev-latest" } }
JSON

OUT=$(python3 "$DETECT" "$FIXTURE/php")
if echo "$OUT" | grep -q "composer audit"; then
    log_pass "security: composer audit always suggested for php"
else
    log_fail "security detection" "$OUT"
fi

if echo "$OUT" | grep -qi "gitleaks\|semgrep"; then
    log_pass "security: scanner suggestion present"
else
    log_fail "scanner suggestion" "$OUT"
fi

if echo "$OUT" | grep -q "Roave Security Advisories"; then
    log_pass "security: declared roave/security-advisories consumed"
else
    log_fail "roave detection" "$OUT"
fi

if python3 "$DETECT" "$FIXTURE/php" --json | jq -e '.security.php[0].command' >/dev/null 2>&1; then
    log_pass "--json exposes the security suggestions with their commands"
else
    log_fail "security json" "no .security.php entries"
fi

rm -rf "$FIXTURE"

test_summary
