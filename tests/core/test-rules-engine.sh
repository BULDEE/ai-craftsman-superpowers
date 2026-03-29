#!/usr/bin/env bash
# =============================================================================
# Rules Engine Tests
# Tests rules-engine.sh: 3-level config inheritance, custom rules, directory
# overrides, strictness fallback, and validation.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$label"
    else
        log_fail "$label" "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        log_pass "$label"
    else
        log_fail "$label" "expected to contain '$needle' in '$haystack'"
    fi
}

source "$ROOT_DIR/hooks/lib/rules-engine.sh"

# Temp dirs for test isolation
TEST_DIR="/tmp/craftsman-rules-tests-$$"
GLOBAL_DIR="$TEST_DIR/global"
PROJECT_DIR="$TEST_DIR/project"
mkdir -p "$GLOBAL_DIR" "$PROJECT_DIR"

# =============================================================================
# 1. Builtin rule defaults (strict mode)
# =============================================================================
echo ""
echo "=== 1. Builtin Rule Defaults (strict mode) ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
YAML

rules_init "$PROJECT_DIR"

assert_eq "PHP001 defaults to block in strict" "block" "$(rules_severity "PHP001")"
assert_eq "TS001 defaults to block in strict" "block" "$(rules_severity "TS001")"
assert_eq "LAYER001 defaults to block in strict" "block" "$(rules_severity "LAYER001")"
assert_eq "WARN001 defaults to warn in strict" "warn" "$(rules_severity "WARN001")"
assert_eq "PHP005 defaults to warn in strict" "warn" "$(rules_severity "PHP005")"

# =============================================================================
# 2. Project config overrides defaults
# =============================================================================
echo ""
echo "=== 2. Project Config Overrides Defaults ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  PHP001: warn
  TS001: ignore
  LAYER001: warn
YAML

rules_init "$PROJECT_DIR"

assert_eq "PHP001 overridden to warn" "warn" "$(rules_severity "PHP001")"
assert_eq "TS001 overridden to ignore" "ignore" "$(rules_severity "TS001")"
assert_eq "LAYER001 overridden to warn" "warn" "$(rules_severity "LAYER001")"
assert_eq "PHP002 still defaults to block (strict)" "block" "$(rules_severity "PHP002")"

# =============================================================================
# 3. Directory-level overrides (.craft-rules.yml)
# =============================================================================
echo ""
echo "=== 3. Directory-Level Overrides ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  PHP002: block
YAML

mkdir -p "$PROJECT_DIR/src/Infrastructure"
cat > "$PROJECT_DIR/src/Infrastructure/.craft-rules.yml" <<'YAML'
rules:
  PHP002: ignore
  LAYER001: warn
YAML

rules_init "$PROJECT_DIR"

# Project-level rule
assert_eq "PHP002 is block at project level" "block" "$(rules_severity "PHP002")"

# Directory override via file path
assert_eq "PHP002 is ignore in Infrastructure dir" "ignore" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Infrastructure/SomeRepo.php" "PHP002")"
assert_eq "LAYER001 is warn in Infrastructure dir" "warn" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Infrastructure/SomeRepo.php" "LAYER001")"

# Non-overridden rule uses project default
assert_eq "PHP001 still block in Infrastructure dir" "block" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Infrastructure/SomeRepo.php" "PHP001")"

# File not in Infrastructure uses project default
assert_eq "PHP002 is block outside Infrastructure" "block" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Domain/Entity.php" "PHP002")"

# =============================================================================
# 4. Custom rules (pattern, message, severity, languages)
# =============================================================================
echo ""
echo "=== 4. Custom Rules ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  CUSTOM001:
    pattern: "dd\\("
    message: "No dd() in production code"
    severity: block
    languages: [php]
  CUSTOM002:
    pattern: "console\\.log"
    message: "No console.log in production"
    severity: warn
    languages: [typescript, javascript]
YAML

rules_init "$PROJECT_DIR"

assert_eq "CUSTOM001 severity is block" "block" "$(rules_severity "CUSTOM001")"
assert_eq "CUSTOM001 pattern" 'dd\(' "$(rules_pattern "CUSTOM001")"
assert_eq "CUSTOM001 message" "No dd() in production code" "$(rules_message "CUSTOM001")"

assert_eq "CUSTOM002 severity is warn" "warn" "$(rules_severity "CUSTOM002")"
assert_eq "CUSTOM002 pattern" 'console\.log' "$(rules_pattern "CUSTOM002")"
assert_eq "CUSTOM002 message" "No console.log in production" "$(rules_message "CUSTOM002")"

# Custom list for language
custom_php=$(rules_custom_list "php")
assert_contains "CUSTOM001 in php custom list" "CUSTOM001" "$custom_php"

custom_ts=$(rules_custom_list "typescript")
assert_contains "CUSTOM002 in typescript custom list" "CUSTOM002" "$custom_ts"

# CUSTOM001 should NOT be in typescript list
custom_ts_no=$(rules_custom_list "typescript")
if echo "$custom_ts_no" | grep -qF "CUSTOM001"; then
    log_fail "CUSTOM001 should NOT be in typescript list" "found it"
else
    log_pass "CUSTOM001 is not in typescript custom list"
fi

# =============================================================================
# 5. Global + project merge (project overrides global)
# =============================================================================
echo ""
echo "=== 5. Global + Project Merge ==="

_rules_reset
cat > "$GLOBAL_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: moderate
stack: symfony
rules:
  PHP001: warn
  PHP002: block
  TS001: block
YAML

cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  PHP001: block
YAML

rules_init "$PROJECT_DIR" "$GLOBAL_DIR"

# Project overrides global for strictness
assert_eq "Strictness is strict (project wins)" "block" "$(rules_severity "LAYER001")"

# PHP001: project says block, global says warn => project wins
assert_eq "PHP001: project block overrides global warn" "block" "$(rules_severity "PHP001")"

# PHP002: only global says block => inherited from global
assert_eq "PHP002: inherited from global as block" "block" "$(rules_severity "PHP002")"

# TS001: only global says block => inherited from global
assert_eq "TS001: inherited from global as block" "block" "$(rules_severity "TS001")"

# =============================================================================
# 6. Custom rule validation (bad regex skipped)
# =============================================================================
echo ""
echo "=== 6. Custom Rule Validation ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  BADREGEX:
    pattern: "[invalid("
    message: "Bad regex rule"
    severity: block
    languages: [php]
  BADSEVERITY:
    pattern: "something"
    message: "Bad severity"
    severity: fatal
    languages: [php]
  NOLANG:
    pattern: "something"
    message: "No languages"
    severity: block
    languages: []
  GOODRULE:
    pattern: "dump\\("
    message: "No dump()"
    severity: warn
    languages: [php]
YAML

_stderr_file="/tmp/craftsman-rules-stderr-$$"
rules_init "$PROJECT_DIR" 2>"$_stderr_file"
stderr_output=$(cat "$_stderr_file")
rm -f "$_stderr_file"

# Bad regex => severity set to ignore
assert_eq "BADREGEX severity forced to ignore" "ignore" "$(rules_severity "BADREGEX")"

# Bad severity => severity set to ignore
assert_eq "BADSEVERITY severity forced to ignore" "ignore" "$(rules_severity "BADSEVERITY")"

# No languages => severity set to ignore
assert_eq "NOLANG severity forced to ignore" "ignore" "$(rules_severity "NOLANG")"

# Good rule should work normally
assert_eq "GOODRULE severity is warn" "warn" "$(rules_severity "GOODRULE")"

# Stderr should contain warnings
assert_contains "Stderr warns about BADREGEX" "BADREGEX" "$stderr_output"
assert_contains "Stderr warns about BADSEVERITY" "BADSEVERITY" "$stderr_output"
assert_contains "Stderr warns about NOLANG" "NOLANG" "$stderr_output"

# =============================================================================
# 7. Strictness fallback (moderate, relaxed)
# =============================================================================
echo ""
echo "=== 7. Strictness Fallback ==="

# --- moderate ---
_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: moderate
stack: fullstack
YAML

rules_init "$PROJECT_DIR"

assert_eq "moderate: LAYER001 defaults to block" "block" "$(rules_severity "LAYER001")"
assert_eq "moderate: PHP001 defaults to warn" "warn" "$(rules_severity "PHP001")"
assert_eq "moderate: TS001 defaults to warn" "warn" "$(rules_severity "TS001")"
assert_eq "moderate: WARN001 defaults to warn" "warn" "$(rules_severity "WARN001")"
assert_eq "moderate: PHP005 defaults to warn" "warn" "$(rules_severity "PHP005")"

# --- relaxed ---
_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: relaxed
stack: fullstack
YAML

rules_init "$PROJECT_DIR"

assert_eq "relaxed: PHP001 defaults to warn" "warn" "$(rules_severity "PHP001")"
assert_eq "relaxed: LAYER001 defaults to warn" "warn" "$(rules_severity "LAYER001")"
assert_eq "relaxed: TS001 defaults to warn" "warn" "$(rules_severity "TS001")"
assert_eq "relaxed: WARN001 defaults to warn" "warn" "$(rules_severity "WARN001")"

# =============================================================================
# 8. rules_severity_for_file with directory walk-up
# =============================================================================
echo ""
echo "=== 8. Directory Walk-Up ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
YAML

mkdir -p "$PROJECT_DIR/src/Infrastructure/Persistence/Doctrine"
cat > "$PROJECT_DIR/src/Infrastructure/.craft-rules.yml" <<'YAML'
rules:
  PHP002: ignore
YAML

rules_init "$PROJECT_DIR"

# File deep in Infrastructure should walk up and find .craft-rules.yml
assert_eq "Walk-up: PHP002 is ignore deep in Infrastructure" "ignore" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Infrastructure/Persistence/Doctrine/UserRepo.php" "PHP002")"

# A .craft-rules.yml in a deeper directory overrides the parent one
cat > "$PROJECT_DIR/src/Infrastructure/Persistence/.craft-rules.yml" <<'YAML'
rules:
  PHP002: warn
YAML

# Clear directory cache
_rules_reset_dir_cache

assert_eq "Walk-up: deeper .craft-rules.yml wins for PHP002" "warn" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Infrastructure/Persistence/Doctrine/UserRepo.php" "PHP002")"

# File outside Infrastructure uses project default
assert_eq "Walk-up: PHP002 outside Infrastructure is block" "block" \
    "$(rules_severity_for_file "$PROJECT_DIR/src/Domain/User.php" "PHP002")"

# =============================================================================
# 9. No config file => defaults apply
# =============================================================================
echo ""
echo "=== 9. No Config File ==="

_rules_reset
rm -f "$PROJECT_DIR/.craft-config.yml"

rules_init "$PROJECT_DIR"

# Default strictness is strict
assert_eq "No config: PHP001 defaults to block (strict)" "block" "$(rules_severity "PHP001")"
assert_eq "No config: WARN001 defaults to warn" "warn" "$(rules_severity "WARN001")"
assert_eq "No config: PHP005 defaults to warn" "warn" "$(rules_severity "PHP005")"

# =============================================================================
# 10. Custom rule pattern with special characters
# =============================================================================
echo ""
echo "=== 10. Custom Rule Patterns ==="

_rules_reset
cat > "$PROJECT_DIR/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  CUSTOM_VAR:
    pattern: "\\$_(?:GET|POST|REQUEST)"
    message: "No direct superglobal access"
    severity: block
    languages: [php]
YAML

rules_init "$PROJECT_DIR" 2>/dev/null

assert_eq "CUSTOM_VAR severity" "block" "$(rules_severity "CUSTOM_VAR")"
assert_eq "CUSTOM_VAR message" "No direct superglobal access" "$(rules_message "CUSTOM_VAR")"

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "$TEST_DIR"

echo ""
echo "==================================="
echo -e " ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e " ${RED}Failed:${NC} $TESTS_FAILED"
echo "==================================="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
