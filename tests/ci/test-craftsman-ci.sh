#!/usr/bin/env bash
# =============================================================================
# craftsman-ci CLI Tests
# Tests ci/craftsman-ci.sh behavior across all supported rules and options.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
CLI="$ROOT_DIR/ci/craftsman-ci.sh"

# Reuse core fixtures where applicable (moved from tests/hooks/ to tests/core/ in v2.5.0)
HOOK_FIXTURES="$ROOT_DIR/tests/core/fixtures"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

# =============================================================================
# Guard: CLI must exist and be executable
# =============================================================================
if [[ ! -f "$CLI" ]]; then
    echo "FATAL: craftsman-ci.sh not found at $CLI" >&2
    exit 1
fi

chmod +x "$CLI"

# =============================================================================
# Helper: run CLI, return "exit_code|output"
# =============================================================================
run_ci() {
    local output exit_code
    output=$(bash "$CLI" "$@" 2>&1)
    exit_code=$?
    echo "${exit_code}|${output}"
}

# =============================================================================
# 1. Exit code tests
# =============================================================================
echo ""
echo "=== Exit Code Tests ==="

# Clean PHP file → exit 0
result=$(run_ci "$FIXTURES_DIR/valid-entity.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid PHP file → exit 0 (clean)"
else
    log_fail "Valid PHP should exit 0" "got exit $exit_code"
fi

# Clean TS file → exit 0
result=$(run_ci "$FIXTURES_DIR/valid-component.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid TS file → exit 0 (clean)"
else
    log_fail "Valid TS should exit 0" "got exit $exit_code"
fi

# Invalid PHP (missing strict_types) → exit 2
result=$(run_ci "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Invalid PHP (missing strict_types) → exit 2 (violations)"
else
    log_fail "Missing strict_types should exit 2" "got exit $exit_code"
fi

# Invalid TS (any type + default export) → exit 2
result=$(run_ci "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Invalid TS (any type) → exit 2 (violations)"
else
    log_fail "TS with any should exit 2" "got exit $exit_code"
fi

# Layer violation → exit 2
result=$(run_ci "$FIXTURES_DIR/invalid-layer-violation.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Layer violation PHP → exit 2 (violations)"
else
    log_fail "Layer violation should exit 2" "got exit $exit_code"
fi

# =============================================================================
# 2. Rule detection tests
# =============================================================================
echo ""
echo "=== Rule Detection Tests ==="

# PHP001 detected
result=$(run_ci --format text "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | grep -q "PHP001"; then
    log_pass "PHP001 (missing strict_types) detected in text output"
else
    log_fail "PHP001 should appear in output" "$output"
fi

# PHP002 detected (using hook fixture)
result=$(run_ci --format text "$HOOK_FIXTURES/invalid-no-final.php")
output="${result#*|}"
if echo "$output" | grep -q "PHP002"; then
    log_pass "PHP002 (missing final) detected in text output"
else
    log_fail "PHP002 should appear in output" "$output"
fi

# TS001 detected
result=$(run_ci --format text "$FIXTURES_DIR/invalid-any.ts")
output="${result#*|}"
if echo "$output" | grep -q "TS001"; then
    log_pass "TS001 (any type) detected in text output"
else
    log_fail "TS001 should appear in output" "$output"
fi

# TS002 detected (default export in invalid-any.ts)
result=$(run_ci --format text "$FIXTURES_DIR/invalid-any.ts")
output="${result#*|}"
if echo "$output" | grep -q "TS002"; then
    log_pass "TS002 (default export) detected in text output"
else
    log_fail "TS002 should appear in output" "$output"
fi

# LAYER001 detected
result=$(run_ci --format text "$FIXTURES_DIR/invalid-layer-violation.php")
output="${result#*|}"
if echo "$output" | grep -q "LAYER001"; then
    log_pass "LAYER001 (domain imports infra) detected in text output"
else
    log_fail "LAYER001 should appear in output" "$output"
fi

# =============================================================================
# 3. JSON output format tests
# =============================================================================
echo ""
echo "=== JSON Output Tests ==="

# JSON output is valid JSON
result=$(run_ci --format json "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | python3 -m json.tool >/dev/null 2>&1; then
    log_pass "JSON output is valid JSON"
else
    log_fail "JSON output should be valid JSON" "${output:0:200}"
fi

# JSON has required top-level keys
result=$(run_ci --format json "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'version' in d
assert 'timestamp' in d
assert 'config' in d
assert 'summary' in d
assert 'violations' in d
" 2>/dev/null; then
    log_pass "JSON has all required top-level keys (version, timestamp, config, summary, violations)"
else
    log_fail "JSON missing required keys" "${output:0:200}"
fi

# JSON summary has correct fields
result=$(run_ci --format json "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d['summary']
assert 'files_scanned' in s
assert 'violations' in s
assert 'warnings' in s
" 2>/dev/null; then
    log_pass "JSON summary has files_scanned, violations, warnings fields"
else
    log_fail "JSON summary missing fields" "${output:0:200}"
fi

# JSON config has strictness and stack
result=$(run_ci --format json "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
c = d['config']
assert 'strictness' in c
assert 'stack' in c
" 2>/dev/null; then
    log_pass "JSON config has strictness and stack fields"
else
    log_fail "JSON config missing fields" "${output:0:200}"
fi

# JSON violation has required fields
result=$(run_ci --format json "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d['violations']) > 0
v = d['violations'][0]
assert 'rule' in v
assert 'file' in v
assert 'line' in v
assert 'message' in v
assert 'severity' in v
" 2>/dev/null; then
    log_pass "JSON violation has rule, file, line, message, severity"
else
    log_fail "JSON violation missing fields" "${output:0:200}"
fi

# JSON violations count matches exit code 2
result=$(run_ci --format json "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
output="${result#*|}"
violations_count=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" 2>/dev/null || echo "-1")
if [[ "$exit_code" == "2" && "$violations_count" -gt 0 ]]; then
    log_pass "JSON summary.violations > 0 when exit code is 2"
else
    log_fail "JSON violations count should match exit 2" "exit=$exit_code violations=$violations_count"
fi

# Clean file: JSON violations array is empty
result=$(run_ci --format json "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
violations_count=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" 2>/dev/null || echo "-1")
if [[ "$violations_count" == "0" ]]; then
    log_pass "Clean file: JSON violations count is 0"
else
    log_fail "Clean file should have 0 violations" "got $violations_count"
fi

# =============================================================================
# 4. Text output format tests
# =============================================================================
echo ""
echo "=== Text Output Tests ==="

# Text output header present
result=$(run_ci --format text "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
if echo "$output" | grep -q "craftsman-ci"; then
    log_pass "Text output contains craftsman-ci header"
else
    log_fail "Text output should contain header" "${output:0:200}"
fi

# Text output shows config
result=$(run_ci --format text "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
if echo "$output" | grep -qE "Config:.*strict"; then
    log_pass "Text output shows Config line"
else
    log_fail "Text output should show Config" "${output:0:200}"
fi

# Text output shows file path for violations
result=$(run_ci --format text "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | grep -q "invalid-no-strict.php"; then
    log_pass "Text output shows filename for violations"
else
    log_fail "Text output should show filename" "${output:0:200}"
fi

# Text output shows violation summary line
result=$(run_ci --format text "$FIXTURES_DIR/invalid-no-strict.php")
output="${result#*|}"
if echo "$output" | grep -qE "violation|warning"; then
    log_pass "Text output shows violation summary"
else
    log_fail "Text output should show summary line" "${output:0:200}"
fi

# =============================================================================
# 5. Config flag tests
# =============================================================================
echo ""
echo "=== --config Flag Tests ==="

# Create temp config file
TEMP_DIR="/tmp/craftsman-ci-tests-$$"
mkdir -p "$TEMP_DIR"

# Config with stack=react should skip PHP rules
cat > "$TEMP_DIR/react-config.yml" <<'YAML'
strictness: strict
stack: react
YAML

result=$(run_ci --format json --config "$TEMP_DIR/react-config.yml" "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "--config with stack=react skips PHP rules (exit 0 on PHP file)"
else
    log_fail "--config stack=react should skip PHP" "got exit $exit_code"
fi

# Config with stack=symfony should skip TS rules
cat > "$TEMP_DIR/symfony-config.yml" <<'YAML'
strictness: strict
stack: symfony
YAML

result=$(run_ci --format json --config "$TEMP_DIR/symfony-config.yml" "$FIXTURES_DIR/invalid-any.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "--config with stack=symfony skips TS rules (exit 0 on TS file)"
else
    log_fail "--config stack=symfony should skip TS" "got exit $exit_code"
fi

# Config with strictness=relaxed should produce exit 1 (warnings) not exit 2 (violations)
cat > "$TEMP_DIR/relaxed-config.yml" <<'YAML'
strictness: relaxed
stack: fullstack
YAML

result=$(run_ci --format json --config "$TEMP_DIR/relaxed-config.yml" "$FIXTURES_DIR/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "1" ]]; then
    log_pass "--config strictness=relaxed converts violations to warnings (exit 1)"
else
    log_fail "--config relaxed should exit 1 (warnings)" "got exit $exit_code"
fi

# Config JSON reflects --config values
result=$(run_ci --format json --config "$TEMP_DIR/relaxed-config.yml" "$FIXTURES_DIR/valid-entity.php")
output="${result#*|}"
stack_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['config']['stack'])" 2>/dev/null || echo "")
strictness_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['config']['strictness'])" 2>/dev/null || echo "")
if [[ "$stack_val" == "fullstack" && "$strictness_val" == "relaxed" ]]; then
    log_pass "--config values reflected in JSON output (strictness=relaxed, stack=fullstack)"
else
    log_fail "--config values should appear in JSON" "stack=$stack_val strictness=$strictness_val"
fi

rm -rf "$TEMP_DIR"

# =============================================================================
# 6. Stack filtering via env var tests
# =============================================================================
echo ""
echo "=== Stack Filtering (env var) Tests ==="

# stack=react via env var skips PHP
export CLAUDE_PLUGIN_OPTION_stack="react"
result=$(run_ci "$FIXTURES_DIR/invalid-no-strict.php")
unset CLAUDE_PLUGIN_OPTION_stack
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "CLAUDE_PLUGIN_OPTION_stack=react skips PHP rules (exit 0)"
else
    log_fail "Env stack=react should skip PHP" "got exit $exit_code"
fi

# stack=symfony via env var skips TS
export CLAUDE_PLUGIN_OPTION_stack="symfony"
result=$(run_ci "$FIXTURES_DIR/invalid-any.ts")
unset CLAUDE_PLUGIN_OPTION_stack
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "CLAUDE_PLUGIN_OPTION_stack=symfony skips TS rules (exit 0)"
else
    log_fail "Env stack=symfony should skip TS" "got exit $exit_code"
fi

# =============================================================================
# 7. Path scanning tests
# =============================================================================
echo ""
echo "=== Path Scanning Tests ==="

# Scan directory: finds PHP and TS violations
result=$(run_ci --format json "$FIXTURES_DIR/")
exit_code="${result%%|*}"
output="${result#*|}"
files_scanned=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" 2>/dev/null || echo "0")
if [[ "$exit_code" == "2" && "$files_scanned" -gt 1 ]]; then
    log_pass "Directory scan finds violations across multiple files (exit 2, ${files_scanned} files)"
else
    log_fail "Directory scan should find multiple files" "exit=$exit_code files=$files_scanned"
fi

# Scan specific single file path
result=$(run_ci --format json "$FIXTURES_DIR/valid-entity.php")
exit_code="${result%%|*}"
output="${result#*|}"
files_scanned=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" 2>/dev/null || echo "0")
if [[ "$exit_code" == "0" && "$files_scanned" == "1" ]]; then
    log_pass "Specific file path: scans exactly 1 file"
else
    log_fail "Specific file scan should report 1 file" "exit=$exit_code files=$files_scanned"
fi

# Non-existent path: graceful handling
result=$(run_ci --format json "/nonexistent/path/")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Non-existent path: exits 0 gracefully (no files, no violations)"
else
    log_fail "Non-existent path should exit 0" "got exit $exit_code"
fi

# =============================================================================
# 8. Reuse hook fixtures (compatibility check)
# =============================================================================
echo ""
echo "=== Hook Fixture Compatibility Tests ==="

# Hook's valid-entity.php should pass
result=$(run_ci "$HOOK_FIXTURES/valid-entity.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Hook fixture valid-entity.php passes craftsman-ci (compatible)"
else
    log_fail "Hook valid-entity should pass" "got exit $exit_code"
fi

# Hook's invalid-no-strict.php should fail
result=$(run_ci "$HOOK_FIXTURES/invalid-no-strict.php")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Hook fixture invalid-no-strict.php fails craftsman-ci (compatible)"
else
    log_fail "Hook invalid-no-strict should fail" "got exit $exit_code"
fi

# Hook's invalid-any.ts should fail
result=$(run_ci "$HOOK_FIXTURES/invalid-any.ts")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]]; then
    log_pass "Hook fixture invalid-any.ts fails craftsman-ci (compatible)"
else
    log_fail "Hook invalid-any should fail" "got exit $exit_code"
fi

# Hook's with-craftsman-ignore.php: still uses same logic
result=$(run_ci "$HOOK_FIXTURES/with-craftsman-ignore.php")
# craftsman-ci doesn't handle inline craftsman-ignore for file-level rules by default
# but should still exit consistently
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" || "$exit_code" == "1" || "$exit_code" == "2" ]]; then
    log_pass "Hook fixture with-craftsman-ignore.php handled without crash (exit $exit_code)"
else
    log_fail "with-craftsman-ignore should not crash" "got exit $exit_code"
fi

# =============================================================================
# 9. CI vs Hooks rule parity tests
# Verifies that CI output detects the same rules as hooks for identical fixtures
# =============================================================================
echo ""
echo "=== CI/Hooks Parity Tests ==="

# CI detects same PHP rules as hooks on shared fixture
result=$(run_ci --format json "$HOOK_FIXTURES/invalid-no-strict.php")
output="${result#*|}"
ci_rules=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rules = sorted(set(v['rule'] for v in d['violations']))
print(' '.join(rules))
" 2>/dev/null || echo "")
if echo "$ci_rules" | grep -q "PHP001"; then
    log_pass "CI detects PHP001 on shared hook fixture (parity confirmed)"
else
    log_fail "CI should detect PHP001 on hook fixture" "got rules: $ci_rules"
fi

# CI detects same TS rules as hooks on shared fixture
result=$(run_ci --format json "$HOOK_FIXTURES/invalid-any.ts")
output="${result#*|}"
ci_rules=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rules = sorted(set(v['rule'] for v in d['violations']))
print(' '.join(rules))
" 2>/dev/null || echo "")
if echo "$ci_rules" | grep -q "TS001" && echo "$ci_rules" | grep -q "TS002"; then
    log_pass "CI detects TS001+TS002 on shared hook fixture (parity confirmed)"
else
    log_fail "CI should detect TS001+TS002 on hook fixture" "got rules: $ci_rules"
fi

# CI detects LAYER001 on shared fixture
result=$(run_ci --format json "$HOOK_FIXTURES/invalid-layer-violation.php")
output="${result#*|}"
ci_rules=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rules = sorted(set(v['rule'] for v in d['violations']))
print(' '.join(rules))
" 2>/dev/null || echo "")
if echo "$ci_rules" | grep -q "LAYER001"; then
    log_pass "CI detects LAYER001 on shared hook fixture (parity confirmed)"
else
    log_fail "CI should detect LAYER001 on hook fixture" "got rules: $ci_rules"
fi

# =============================================================================
# 10. Standalone mode (no Claude Code env vars)
# =============================================================================
echo ""
echo "=== Standalone Mode Tests ==="

# Unset all Claude-specific env vars and verify CI still works
(
    unset CLAUDE_PLUGIN_ROOT
    unset CLAUDE_PLUGIN_DATA
    unset CLAUDE_PLUGIN_OPTION_strictness
    unset CLAUDE_PLUGIN_OPTION_stack
    result=$(bash "$CLI" --format json "$FIXTURES_DIR/invalid-no-strict.php" 2>&1)
    exit_code=$?
    echo "${exit_code}|${result}"
)
standalone_result=$( (
    unset CLAUDE_PLUGIN_ROOT
    unset CLAUDE_PLUGIN_DATA
    unset CLAUDE_PLUGIN_OPTION_strictness
    unset CLAUDE_PLUGIN_OPTION_stack
    bash "$CLI" --format json "$FIXTURES_DIR/invalid-no-strict.php" 2>&1
    echo "EXIT:$?"
) )
standalone_exit=$(echo "$standalone_result" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
standalone_output=$(echo "$standalone_result" | grep -v 'EXIT:')
if [[ "$standalone_exit" == "2" ]]; then
    log_pass "Standalone mode: exits 2 on invalid file (no Claude env vars)"
else
    log_fail "Standalone mode should exit 2" "got exit $standalone_exit"
fi

if echo "$standalone_output" | python3 -m json.tool >/dev/null 2>&1; then
    log_pass "Standalone mode: produces valid JSON output"
else
    log_fail "Standalone mode should produce valid JSON" "${standalone_output:0:200}"
fi

# =============================================================================
# 11. --help flag test
# =============================================================================
echo ""
echo "=== CLI Interface Tests ==="

result=$(bash "$CLI" --help)
exit_code=$?
if [[ "$exit_code" == "0" ]]; then
    log_pass "--help exits 0"
else
    log_fail "--help should exit 0" "got exit $exit_code"
fi

if echo "$result" | grep -q "craftsman-ci"; then
    log_pass "--help shows craftsman-ci in output"
else
    log_fail "--help should mention craftsman-ci" "${result:0:100}"
fi

# =============================================================================
# Summary
# =============================================================================
test_summary
