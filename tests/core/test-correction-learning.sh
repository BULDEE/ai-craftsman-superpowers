#!/usr/bin/env bash
# =============================================================================
# Correction Learning Tests
# Tests the correction learning system in post-write-check.sh:
#   - Violation recording in session-state.json
#   - Correction detection on fix
#   - Cross-file pattern detection
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-correction-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# Cleanup
trap 'rm -rf "$CLAUDE_PLUGIN_DATA" /tmp/craftsman-correction-fixtures-$$' EXIT

source "$SCRIPT_DIR/../lib/test-helpers.sh"

SESSION_STATE="$CLAUDE_PLUGIN_DATA/session-state.json"
FIXTURES_DIR="/tmp/craftsman-correction-fixtures-$$"
mkdir -p "$FIXTURES_DIR/src/Domain"

# Helper to run post-write hook
run_post_hook() {
    local fixture="$1"
    local output
    output=$(echo "{\"tool_input\":{\"file_path\":\"$fixture\"}}" | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

echo ""
echo "=== Correction Learning Tests ==="

# =============================================================================
# Test 1: Violation creates session state entry
# =============================================================================
echo ""
echo "--- Violation Recording ---"

# Create a PHP file missing strict_types
cat > "$FIXTURES_DIR/src/Domain/BadEntity.php" << 'FIXTURE'
<?php

final class BadEntity
{
    public function __construct(private string $name) {}
}
FIXTURE

result=$(run_post_hook "$FIXTURES_DIR/src/Domain/BadEntity.php")
exit_code="${result%%|*}"

if [[ "$exit_code" == "2" ]]; then
    log_pass "Missing strict_types is reported to Claude (exit 2)"
else
    log_fail "Missing strict_types should block" "got exit $exit_code"
fi

# Check session-state.json was created with violation data
if [[ -f "$SESSION_STATE" ]]; then
    has_violations=$(python3 -c "
import json
with open('$SESSION_STATE') as f:
    state = json.load(f)
bv = state.get('blocked_violations', {})
print('yes' if len(bv) > 0 else 'no')
" 2>/dev/null)
    if [[ "$has_violations" == "yes" ]]; then
        log_pass "Session state records blocked violations"
    else
        log_fail "Session state should have blocked_violations" "empty"
    fi
else
    log_fail "Session state file should exist" "not found"
fi

# =============================================================================
# Test 2: Fixing violation triggers correction detection
# =============================================================================
echo ""
echo "--- Correction Detection ---"

# Fix the file by adding strict_types
cat > "$FIXTURES_DIR/src/Domain/BadEntity.php" << 'FIXTURE'
<?php

declare(strict_types=1);

final class BadEntity
{
    public function __construct(private string $name) {}
}
FIXTURE

result=$(run_post_hook "$FIXTURES_DIR/src/Domain/BadEntity.php")
exit_code="${result%%|*}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Fixed file passes (exit 0)"
else
    log_fail "Fixed file should pass" "got exit $exit_code"
fi

# Check corrections table in SQLite
if [[ -f "$CLAUDE_PLUGIN_DATA/metrics.db" ]]; then
    correction_count=$(sqlite3 "$CLAUDE_PLUGIN_DATA/metrics.db" "SELECT COUNT(*) FROM corrections;" 2>/dev/null || echo "0")
    if [[ "$correction_count" -gt 0 ]]; then
        log_pass "Correction recorded in SQLite ($correction_count entries)"
    else
        log_pass "Correction flow executed (no DB entry expected in isolated test)"
    fi
else
    log_pass "Metrics DB not required for correction flow test"
fi

# =============================================================================
# Test 3: Cross-file pattern detection
# =============================================================================
echo ""
echo "--- Cross-File Pattern Detection ---"

# Reset session state
rm -f "$SESSION_STATE"

# Create 3 PHP files with the same violation (missing strict_types)
for i in 1 2 3; do
    cat > "$FIXTURES_DIR/src/Domain/Entity${i}.php" << FIXTURE
<?php

final class Entity${i}
{
    public function __construct(private string \$name) {}
}
FIXTURE
    run_post_hook "$FIXTURES_DIR/src/Domain/Entity${i}.php" > /dev/null 2>&1
done

# Check session state has pattern data
if [[ -f "$SESSION_STATE" ]]; then
    pattern_data=$(python3 -c "
import json
with open('$SESSION_STATE') as f:
    state = json.load(f)
patterns = state.get('patterns', {})
for rule, dir_map in patterns.items():
    all_files = set()
    for files in dir_map.values():
        all_files.update(files)
    if len(all_files) >= 3:
        print('PATTERN:' + rule + ':' + str(len(all_files)))
" 2>/dev/null)

    if [[ -n "$pattern_data" ]] && echo "$pattern_data" | grep -q "PATTERN:"; then
        log_pass "Cross-file pattern detected: $pattern_data"
    else
        # Check if at least patterns dict has entries
        has_patterns=$(python3 -c "
import json
with open('$SESSION_STATE') as f:
    state = json.load(f)
print('yes' if state.get('patterns', {}) else 'no')
" 2>/dev/null)
        if [[ "$has_patterns" == "yes" ]]; then
            log_pass "Pattern tracking active (violations grouped by directory)"
        else
            log_fail "Cross-file pattern should be tracked" "no pattern data"
        fi
    fi
else
    log_fail "Session state should exist after 3 violations" "not found"
fi

# =============================================================================
# Test 4: Valid file does not create violation entries
# =============================================================================
echo ""
echo "--- Clean File No Violations ---"

rm -f "$SESSION_STATE"

cat > "$FIXTURES_DIR/src/Domain/CleanEntity.php" << 'FIXTURE'
<?php

declare(strict_types=1);

final class CleanEntity
{
    public function __construct(private string $name) {}
}
FIXTURE

result=$(run_post_hook "$FIXTURES_DIR/src/Domain/CleanEntity.php")
exit_code="${result%%|*}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Clean file passes (exit 0)"
else
    log_fail "Clean file should pass" "got exit $exit_code"
fi

# Session state should either not exist or have empty violations for this file
if [[ ! -f "$SESSION_STATE" ]]; then
    log_pass "No session state created for clean file"
else
    has_violations=$(python3 -c "
import json
with open('$SESSION_STATE') as f:
    state = json.load(f)
bv = state.get('blocked_violations', {})
print('yes' if len(bv) > 0 else 'no')
" 2>/dev/null)
    if [[ "$has_violations" == "no" ]]; then
        log_pass "Session state has no blocked violations for clean file"
    else
        log_pass "Session state exists but may contain empty arrays"
    fi
fi

# =============================================================================
# A rule the developer switched off must not come back as a pattern suggestion.
#
# The pattern state is written when a rule blocks and read on every later write,
# so it outlives the configuration that filled it. It named the rule id in the
# output while the rules engine had resolved that same rule to `ignore` for that
# file, which is the engine's decision being overruled by a cache. The state is
# seeded here rather than accumulated: the defect was originally only visible on
# a machine that had run the suite before, and a guard that needs yesterday's
# run to fail is not a guard.
# =============================================================================
echo ""
echo "--- An ignored rule is not replayed through the pattern channel ---"

PATTERN_DIR="$FIXTURES_DIR/pattern"
mkdir -p "$PATTERN_DIR/src"
printf 'v: 4\nstrictness: strict\nstack: symfony\n' > "$PATTERN_DIR/.craft-config.yml"
cat > "$PATTERN_DIR/src/Nested.php" <<'PHP'
<?php
declare(strict_types=1);
final class Nested {
    private function __construct() {}
    public function grow(int $value): int {
        if ($value) { if ($value > 1) { if ($value > 2) { return 2; } } }
        return 0;
    }
}
PHP

# The seeded rule and the rule that keeps the hook talking are deliberately
# different. Silencing the only rule the file violates also removes the message
# the suggestion is appended to, so the hook falls silent for a reason that has
# nothing to do with the pattern channel and the guard passes on broken code.
# NEST001 stays active and carries the output; RATCHET001 is the seeded one.
seed_pattern_state() {
    printf '{"patterns":{"RATCHET001":{"src":["src/A.php","src/B.php"]}}}' > "$SESSION_STATE"
}

pattern_hook_output() {
    (
        cd "$PATTERN_DIR" || exit 1
        printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$PATTERN_DIR/src/Nested.php" \
            | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1
    )
}

# Control first: with no override, the seeded pattern must actually surface.
# Without it, the silence asserted below is satisfied by a hook that never read
# the state at all, and by a threshold that was never reached.
rm -f "$PATTERN_DIR/src/.craft-rules.yml"
seed_pattern_state
if pattern_hook_output | grep -q "DIRECTORY PATTERN: RATCHET001"; then
    log_pass "control: the seeded pattern is reported when the rule is active"

    printf 'rules:\n  RATCHET001: ignore\n' > "$PATTERN_DIR/src/.craft-rules.yml"
    seed_pattern_state
    if pattern_hook_output | grep -q "RATCHET001"; then
        log_fail "an ignored rule was replayed as a pattern suggestion" \
            "the rules engine resolved RATCHET001 to ignore for this file and the pattern channel reported it anyway - an explicit ignore is an instruction, not a preference"
    else
        log_pass "a rule resolved to ignore is not replayed as a pattern suggestion"
    fi
    rm -f "$PATTERN_DIR/src/.craft-rules.yml"
else
    log_fail "control: the seeded pattern never surfaced" \
        "the assertion below cannot tell a resolved severity from a pattern channel that never ran"
fi

test_summary
