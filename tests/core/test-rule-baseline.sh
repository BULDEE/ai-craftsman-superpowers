#!/usr/bin/env bash
# =============================================================================
# Inherited debt reports; new debt blocks.
#
# The structural ratchet already answered "is this file worse than it was" for
# complexity and size. This is the same question for rules, and it is the half
# whose absence made the plugin unusable on a codebase with history: measured
# on a real Symfony application, 98% of files have no `declare(strict_types=1)`
# and 88% are not `final`, so under the default `strict` the first edit to
# nearly every file was refused for code the user did not write.
#
# Both directions are asserted, and the second is the one that matters. A
# baseline that stops blocking everything is easy; a baseline that stops
# blocking everything AND still refuses a newly added violation is the feature.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-rule-baseline.XXXXXX")"
PREV_PWD="$PWD"
cleanup() { cd "$PREV_PWD" || true; rm -rf "$WORK"; }
trap cleanup EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"

echo "=== Rule baseline ==="

REPO="$WORK/repo"
mkdir -p "$REPO/src/Domain"

# The shape a three-year-old codebase actually has: no strict_types, not final.
write_legacy() {
    cat > "$REPO/src/Domain/Legacy.php" <<'PHP'
<?php
namespace App\Domain;
class Legacy {
    public function total($amount) { return $amount * 2; }
}
PHP
}

hook_on() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
        "$REPO/src/Domain/Legacy.php" "$REPO" \
        | ( cd "$REPO" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 )
}

write_legacy
( cd "$REPO" && git init -q && git add -A ) >/dev/null 2>&1

# --- Before the mark: the gate refuses what the user did not write ------------

before="$(hook_on)"
if echo "$before" | grep -q "BLOCKED"; then
    log_pass "without a baseline, inherited debt blocks (the problem being fixed)"
else
    log_fail "without a baseline, inherited debt blocks" "expected a block, got: $(echo "$before" | head -2)"
fi

# --- Taking the mark ----------------------------------------------------------

baseline_out="$( cd "$REPO" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src 2>&1 )"

if [[ -f "$REPO/.craftsman-baseline.json" ]]; then
    log_pass "craftsman-ci baseline writes the baseline file"
else
    log_fail "craftsman-ci baseline writes the baseline file" "$baseline_out"
fi

# The rule counts and the structural metrics are one row. `ratchet.py init`
# rewrites each row from its own measurement, so folding the counts in BEFORE
# it silently loses them: the first version of this feature printed both
# success lines and produced a baseline with no rules in it at all.
recorded="$(python3 -c "
import json, sys
for line in open(sys.argv[1]):
    line = line.strip().rstrip(',')
    if not line.startswith('{'):
        continue
    row = json.loads(line)
    if row.get('path', '').endswith('Legacy.php'):
        print('%s|%s' % (sorted((row.get('rules') or {}).items()), 'complexity' in row))
" "$REPO/.craftsman-baseline.json" 2>/dev/null)"

assert_contains "the baseline records the rules the file carried" \
    "$recorded" "PHP001"
assert_contains "it records every occurrence, not just the first rule" \
    "$recorded" "PHP002"
assert_contains "the structural metrics survive the fold" "$recorded" "True"

# --- After the mark: the same file reports, and does not block ----------------

after="$(hook_on)"
if echo "$after" | grep -q "BLOCKED"; then
    log_fail "inherited debt no longer blocks" "still blocked: $(echo "$after" | head -2)"
else
    log_pass "inherited debt no longer blocks"
fi

# Reported, not silenced. A gate that hides the debt lies about the state of
# the file; one that blocks on it cannot be used. Neither is the answer.
assert_contains "the finding is still reported" "$after" "PHP001"
assert_contains "and says why it is not blocking" "$after" "already present at the baseline"

# --- The direction that makes it a feature ------------------------------------
#
# The comparison is ordinal: the Nth occurrence of a rule in a file is
# pre-existing when the mark recorded at least N. That gives a real guarantee
# for every rule the validators report per line or per function, which is most
# of them.
#
# It gives a WEAKER one for a rule that fires once per file whatever the file
# contains. PHP002 is one: a file with ten classes and none of them final
# produces exactly one PHP002, so adding an eleventh cannot raise the count and
# cannot be distinguished from the ten that were already there. That limit is
# asserted here rather than hidden, because a reader who assumes otherwise will
# trust the gate for something it does not do.
cat > "$REPO/src/Domain/Legacy.php" <<'PHP'
<?php
namespace App\Domain;
class Legacy {
    public function total($amount) { return $amount * 2; }
}
class Added {
    public function extra($value) { return $value; }
}
PHP

added="$(hook_on)"
if echo "$added" | grep -q "BLOCKED"; then
    log_fail "a file-level rule cannot see a second occurrence" \
        "PHP002 blocked, so the count is per occurrence after all and this note is stale"
else
    log_pass "a file-level rule stays reported, not blocked, when a class is added"
fi

# A rule that DOES count per occurrence keeps the full guarantee. PY004 fires
# once per bare except, so a second one is a second count and blocks.
mkdir -p "$REPO/src/py"
cat > "$REPO/src/py/legacy.py" <<'PY_SRC'
def one():
    try:
        pass
    except:
        pass
PY_SRC
( cd "$REPO" && git add -A ) >/dev/null 2>&1
( cd "$REPO" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src >/dev/null 2>&1 )

py_hook() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
        "$REPO/src/py/legacy.py" "$REPO" \
        | ( cd "$REPO" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 )
}

py_before="$(py_hook)"
if echo "$py_before" | grep -q "BLOCKED"; then
    log_fail "the recorded bare except no longer blocks" "$(echo "$py_before" | head -2)"
else
    log_pass "the recorded bare except no longer blocks"
fi

cat > "$REPO/src/py/legacy.py" <<'PY_SRC'
def one():
    try:
        pass
    except:
        pass


def two():
    try:
        pass
    except:
        pass
PY_SRC
py_after="$(py_hook)"
if echo "$py_after" | grep -q "BLOCKED"; then
    log_pass "a SECOND bare except in the same file still blocks"
else
    log_fail "a SECOND bare except in the same file still blocks" \
        "the ordinal comparison let it through: $(echo "$py_after" | head -3)"
fi

# --- And a file nobody photographed is unaffected ------------------------------

mkdir -p "$REPO/src/Domain/New"
cat > "$REPO/src/Domain/New/Fresh.php" <<'PHP'
<?php
namespace App\Domain\New;
class Fresh {
    public function run($value) { return $value; }
}
PHP
fresh="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$REPO/src/Domain/New/Fresh.php" "$REPO" \
    | ( cd "$REPO" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 ))"
if echo "$fresh" | grep -q "BLOCKED"; then
    log_pass "a file with no recorded mark still blocks"
else
    log_fail "a file with no recorded mark still blocks" \
        "an unphotographed file was let through: $(echo "$fresh" | head -2)"
fi

# --- The lookup itself ---------------------------------------------------------

lookup="$( cd "$REPO" && python3 "$ROOT_DIR/hooks/lib/rule_baseline.py" get \
    "src/Domain/Legacy.php" PHP002 2>/dev/null )"
if [[ "$lookup" == "1" ]]; then
    log_pass "rule_baseline get returns the recorded count"
else
    log_fail "rule_baseline get returns the recorded count" "got '$lookup', expected 1"
fi

unknown="$( cd "$REPO" && python3 "$ROOT_DIR/hooks/lib/rule_baseline.py" get \
    "src/Domain/Legacy.php" NOSUCH001 2>/dev/null )"
if [[ "$unknown" == "0" ]]; then
    log_pass "an unrecorded rule reads as zero, so it blocks"
else
    log_fail "an unrecorded rule reads as zero" "got '$unknown'"
fi

# --- The setup default that made this necessary --------------------------------
#
# The mapping sent "It is going to production" to `strict`, and a codebase with
# three years of history is in production, so the truthful answer selected the
# setting that refuses most of the repository.
setup_text="$(cat "$ROOT_DIR/skills/setup/SKILL.md")"
assert_contains "an existing project caps strictness at moderate" \
    "$setup_text" "Going to production, on an EXISTING one"
assert_contains "and the reason is written down, with the measurement" \
    "$setup_text" "98%"

test_summary
