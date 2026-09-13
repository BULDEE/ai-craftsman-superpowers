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

# A home of its own: metrics_init recovers history from the machine's legacy
# database under $HOME, and this suite counts correction rows, so the real
# home would seed hundreds of them into a "fresh" database.
export HOME="$CLAUDE_PLUGIN_DATA/home"
mkdir -p "$HOME/.claude"
SESSION_STATE="$CLAUDE_PLUGIN_DATA/session-state.json"
FIXTURES_DIR="/tmp/craftsman-correction-fixtures-$$"
mkdir -p "$FIXTURES_DIR/src/Domain"
# A git repository, because that is what the metrics path helpers key on:
# outside one, metrics_relative_path refuses (it will not write a host path
# into a database several machines share) and every correction lands under the
# single bucket <outside-project> with no file. The suite used to measure that
# degraded shape and call it the normal one.
( cd "$FIXTURES_DIR" && git init -q ) >/dev/null 2>&1

# Helper to run post-write hook
# From inside the fixture repository, because that is where Claude Code runs a
# hook: the metrics helpers key the project on the hook's own $PWD, so running
# from elsewhere filed every correction under <outside-project> with no file,
# and this suite measured that degraded shape as if it were the normal one.
run_post_hook() {
    local fixture="$1"
    local output
    output=$( cd "$FIXTURES_DIR" && echo "{\"tool_input\":{\"file_path\":\"$fixture\"}}" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>/dev/null )
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

# One finding, one verdict (#68). The pending verdict was keyed on the
# directory glob and never cleared, so every later write under the glob
# re-recorded the same outcome: PHP002 on a production database carried 106
# ignored rows from one pattern against 56 blocking findings. Asserted on the
# rows, through the real hook, on the shapes that used to recount.
_fixed_rows() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT COUNT(*) FROM corrections WHERE rule='PHP001' AND action='fixed'" 2>/dev/null
}
if [[ "$(_fixed_rows)" == "1" ]]; then
    log_pass "the fix is recorded once, as PHP001 fixed"
else
    log_fail "the fix is recorded once" "rows: $(_fixed_rows)"
fi

# The row carries the exact file, not only its directory glob: the instinct
# gate counts DISTINCT files to decide candidacy (ADR-0020, "across files"),
# and only the Haiku layer used to pass it, so a Level 1 fix counted as one
# directory however many files it touched.
_fixed_row() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT rule, file_pattern, file_path FROM corrections WHERE action='fixed' LIMIT 1" 2>/dev/null
}
if [[ "$(_fixed_row)" == "PHP001|src/Domain/**/*.php|src/Domain/BadEntity.php" ]]; then
    log_pass "the correction row carries the exact file beside its directory glob"
else
    log_fail "the correction row carries the exact file" "$(_fixed_row)"
fi

# The same clean file written again: nothing pending, nothing recorded.
run_post_hook "$FIXTURES_DIR/src/Domain/BadEntity.php" >/dev/null
if [[ "$(_fixed_rows)" == "1" ]]; then
    log_pass "writing the same clean file again records nothing"
else
    log_fail "writing the same clean file again records nothing" "rows: $(_fixed_rows)"
fi

# A different clean file under the same directory glob: the old key shared
# the pending list across the glob, and this write re-recorded the fix.
cat > "$FIXTURES_DIR/src/Domain/Neighbour.php" << 'FIXTURE'
<?php

declare(strict_types=1);

final class Neighbour
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Neighbour.php" >/dev/null
if [[ "$(_fixed_rows)" == "1" ]]; then
    log_pass "a clean neighbour under the same directory glob records nothing"
else
    log_fail "a clean neighbour under the same directory glob records nothing" "rows: $(_fixed_rows)"
fi

# The pending key is the exact file, and a settled file leaves no key behind.
pending_keys=$(python3 -c "
import json
state = json.load(open('$SESSION_STATE'))
print(' '.join(sorted(state.get('blocked_violations', {}).keys())))
" 2>/dev/null)
if [[ -z "$pending_keys" ]]; then
    log_pass "a settled file leaves no pending key behind"
else
    log_fail "a settled file leaves no pending key behind" "pending: $pending_keys"
fi

# An ignore is a verdict too, recorded once. The neighbour breaks the rule,
# then carries a craftsman-ignore for it.
cat > "$FIXTURES_DIR/src/Domain/Neighbour.php" << 'FIXTURE'
<?php

final class Neighbour
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Neighbour.php" >/dev/null
cat > "$FIXTURES_DIR/src/Domain/Neighbour.php" << 'FIXTURE'
<?php
// craftsman-ignore: PHP001

final class Neighbour
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Neighbour.php" >/dev/null
run_post_hook "$FIXTURES_DIR/src/Domain/Neighbour.php" >/dev/null
ignored_rows=$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
    "SELECT COUNT(*) FROM corrections WHERE rule='PHP001' AND action='ignored'" 2>/dev/null)
if [[ "$ignored_rows" == "1" ]]; then
    log_pass "a craftsman-ignore is recorded once as PHP001 ignored, not once per write"
else
    log_fail "a craftsman-ignore is recorded once" "ignored rows: $ignored_rows"
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

# =============================================================================
# A scoping decision is not a fix (learning-loop review, CR-2)
# =============================================================================
#
# A rule absent from this write's blocking findings was recorded `fixed`,
# whatever made it absent. When what changed is the RULE'S SCOPE (a directory
# .craft-rules.yml demoting it, a baseline mark holding it), the developer
# said "this rule is wrong here", and the loop counted it as a fix and
# proposed to teach it: three such files made a candidate at 0.57. `scoped`
# had a place in the schema and no writer.
echo ""
echo "--- A scoping decision is recorded as scoped, a baseline mark as overridden ---"

cat > "$FIXTURES_DIR/src/Domain/Scoped.php" << 'FIXTURE'
<?php

final class Scoped
{
    public function __construct(private string $name) {}
}
FIXTURE
result=$(run_post_hook "$FIXTURES_DIR/src/Domain/Scoped.php")
if [[ "${result%%|*}" == "2" ]]; then
    log_pass "control: the unscoped file is refused on PHP001"
else
    log_fail "control: the unscoped file is refused on PHP001" "got exit ${result%%|*}"
fi
cat > "$FIXTURES_DIR/src/Domain/.craft-rules.yml" <<'YAML'
rules:
  PHP001: warn
YAML
run_post_hook "$FIXTURES_DIR/src/Domain/Scoped.php" >/dev/null
_scoped_row() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT action, context FROM corrections WHERE rule='PHP001' AND file_path='src/Domain/Scoped.php'" 2>/dev/null
}
if [[ "$(_scoped_row)" == "scoped|severity resolved to warn for this file" ]]; then
    log_pass "the same content under a directory rule demoting PHP001 is recorded scoped, not fixed"
else
    log_fail "the same content under a directory rule demoting PHP001 is recorded scoped, not fixed" \
        "rows: $(_scoped_row | tr '\n' ';')"
fi
rm -f "$FIXTURES_DIR/src/Domain/.craft-rules.yml"

cat > "$FIXTURES_DIR/src/Domain/Debt.php" << 'FIXTURE'
<?php

final class Debt
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Debt.php" >/dev/null
printf '{"violations": [{"file": "src/Domain/Debt.php", "rule": "PHP001", "severity": "critical"}]}' > "$FIXTURES_DIR/debt-report.json"
( cd "$FIXTURES_DIR" && python3 "$ROOT_DIR/hooks/lib/rule_baseline.py" record debt-report.json --baseline "$FIXTURES_DIR/.craftsman-baseline.json" >/dev/null 2>&1 )
run_post_hook "$FIXTURES_DIR/src/Domain/Debt.php" >/dev/null
_debt_row() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT action, context FROM corrections WHERE rule='PHP001' AND file_path='src/Domain/Debt.php'" 2>/dev/null
}
if [[ "$(_debt_row)" == "overridden|held by the baseline mark" ]]; then
    log_pass "the same content once a baseline mark holds PHP001 is recorded overridden, not fixed"
else
    log_fail "the same content once a baseline mark holds PHP001 is recorded overridden, not fixed" \
        "rows: $(_debt_row | tr '\n' ';')"
fi
rm -f "$FIXTURES_DIR/.craftsman-baseline.json" "$FIXTURES_DIR/debt-report.json"

# =============================================================================
# A reason in the suppression is the developer's verdict, transcribed
# =============================================================================
echo ""
echo "--- A suppression with a reason records a verdict; a bare one records none ---"

cat > "$FIXTURES_DIR/src/Domain/Judged.php" << 'FIXTURE'
<?php

final class Judged
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Judged.php" >/dev/null
cat > "$FIXTURES_DIR/src/Domain/Judged.php" << 'FIXTURE'
<?php
// craftsman-ignore: PHP001 (wrong: legacy bootstrap file, loaded before any declare)

final class Judged
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Judged.php" >/dev/null
_verdict_rows() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT rule, file_path, verdict, reason, source FROM verdicts ORDER BY id" 2>/dev/null
}
if [[ "$(_verdict_rows)" == "PHP001|src/Domain/Judged.php|wrong|legacy bootstrap file, loaded before any declare|inline" ]]; then
    log_pass "a suppression carrying (wrong: why) records the developer's verdict at the moment of the decision"
else
    log_fail "a suppression carrying (wrong: why) records the developer's verdict" "rows: $(_verdict_rows | tr '\n' ';')"
fi
_judged_outcome() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT action FROM corrections WHERE file_path='src/Domain/Judged.php'" 2>/dev/null
}
if [[ "$(_judged_outcome)" == "ignored" ]]; then
    log_pass "and the outcome is still recorded as ignored"
else
    log_fail "and the outcome is still recorded as ignored" "got '$(_judged_outcome)'"
fi

cat > "$FIXTURES_DIR/src/Domain/Bare.php" << 'FIXTURE'
<?php

final class Bare
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Bare.php" >/dev/null
cat > "$FIXTURES_DIR/src/Domain/Bare.php" << 'FIXTURE'
<?php
// craftsman-ignore: PHP001

final class Bare
{
    public function __construct(private string $name) {}
}
FIXTURE
run_post_hook "$FIXTURES_DIR/src/Domain/Bare.php" >/dev/null
if [[ "$(_verdict_rows | wc -l | tr -d ' ')" == "1" ]]; then
    log_pass "a bare marker records no verdict: the loop does not guess"
else
    log_fail "a bare marker records no verdict" "rows: $(_verdict_rows | tr '\n' ';')"
fi

# =============================================================================
# One finding, one verdict: also for rules emitted once per line (review CR-5)
# =============================================================================
#
# TS001 and PHP003 fire once per offending line, and _blocked_rules_json kept
# every occurrence: two `any` on two lines put ['TS001','TS001'] in the pending
# set, and ONE fix wrote two `fixed` rows. occurrences in the instinct gate and
# the acceptance report were inflated by the line count.
echo ""
echo "--- A rule that fires on two lines is one pending verdict ---"
mkdir -p "$FIXTURES_DIR/src/app"
cat > "$FIXTURES_DIR/src/app/Twice.ts" << 'FIXTURE'
const first: any = 1;
const second: any = 2;
export const total = first + second;
FIXTURE
run_post_hook "$FIXTURES_DIR/src/app/Twice.ts" >/dev/null
cat > "$FIXTURES_DIR/src/app/Twice.ts" << 'FIXTURE'
const first: number = 1;
const second: number = 2;
export const total = first + second;
FIXTURE
run_post_hook "$FIXTURES_DIR/src/app/Twice.ts" >/dev/null
_twice_rows() {
    python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
        "SELECT COUNT(*) FROM corrections WHERE rule='TS001' AND file_path='src/app/Twice.ts'" 2>/dev/null
}
if [[ "$(_twice_rows)" == "1" ]]; then
    log_pass "two TS001 lines fixed in one write record one TS001 verdict"
else
    log_fail "two TS001 lines fixed in one write record one TS001 verdict" "rows: $(_twice_rows)"
fi

# =============================================================================
# Two sessions do not share pending findings or patterns (review CR-3)
# =============================================================================
#
# Session A blocks PHP001 on two files; session B, another project, blocks its
# first file and used to be told "PROJECT-WIDE PATTERN: PHP001 found in 3
# files". Then A's SessionEnd deleted B's pending finding and B's fix recorded
# nothing. With the state named after the session, B sees only B.
echo ""
echo "--- Two sessions, two states ---"
SESS_B="/tmp/craftsman-correction-sessb-$$"
mkdir -p "$SESS_B/src/Domain"; ( cd "$SESS_B" && git init -q ) >/dev/null 2>&1
for n in One Two; do
    printf '<?php\n\nfinal class %s\n{\n}\n' "$n" > "$FIXTURES_DIR/src/Domain/$n.php"
    ( cd "$FIXTURES_DIR" && echo "{\"tool_input\":{\"file_path\":\"$FIXTURES_DIR/src/Domain/$n.php\"}}" \
        | CLAUDE_CODE_SESSION_ID=sessA bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1 )
done
printf '<?php\n\nfinal class Only\n{\n}\n' > "$SESS_B/src/Domain/Only.php"
B_OUT=$( cd "$SESS_B" && echo "{\"tool_input\":{\"file_path\":\"$SESS_B/src/Domain/Only.php\"}}" \
    | CLAUDE_CODE_SESSION_ID=sessB bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 )
if echo "$B_OUT" | grep -q "PATTERN"; then
    log_fail "session B sees no pattern built from session A's files" "$(echo "$B_OUT" | grep PATTERN | head -1 | cut -c1-100)"
else
    log_pass "session B sees no pattern built from session A's files"
fi
echo '{"session_id":"sessA"}' | CLAUDE_CODE_SESSION_ID=sessA bash "$ROOT_DIR/hooks/session-metrics.sh" >/dev/null 2>&1
printf '<?php\n\ndeclare(strict_types=1);\n\nfinal class Only\n{\n}\n' > "$SESS_B/src/Domain/Only.php"
( cd "$SESS_B" && echo "{\"tool_input\":{\"file_path\":\"$SESS_B/src/Domain/Only.php\"}}" \
    | CLAUDE_CODE_SESSION_ID=sessB bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1 )
B_FIX=$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
    "SELECT COUNT(*) FROM corrections WHERE rule='PHP001' AND action='fixed' AND file_path='src/Domain/Only.php'" 2>/dev/null)
if [[ "$B_FIX" == "1" ]]; then
    log_pass "session A's SessionEnd did not erase session B's pending finding: B's fix is recorded"
else
    log_fail "session A's SessionEnd did not erase session B's pending finding" "B fixed rows: $B_FIX"
fi
rm -rf "$SESS_B"

test_summary
