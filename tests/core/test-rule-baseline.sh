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

# --- The baseline must not become a way around the ratchet ---------------------
#
# `ratchet.py init` refuses to re-photograph a file without an explicit
# --reason, which is what makes ADR-0025 a one-way ratchet. This subcommand
# supplies the canonical reason itself, so pointed at a single file it turned
# that into a two-way door AND recorded a reason that is false the second time.
RATCHET_GUARD="$WORK/guard"
mkdir -p "$RATCHET_GUARD/src"
printf '<?php\nclass A { public function x() { return 1; } }\n' > "$RATCHET_GUARD/src/A.php"
( cd "$RATCHET_GUARD" && git init -q && git add -A ) >/dev/null 2>&1

guard_out="$( cd "$RATCHET_GUARD" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src/A.php 2>&1 )"
guard_code=0
( cd "$RATCHET_GUARD" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src/A.php >/dev/null 2>&1 ) || guard_code=$?

if [[ "$guard_code" -ne 0 ]]; then
    log_pass "baseline refuses a single file, so the ratchet guard still stands"
else
    log_fail "baseline refuses a single file" "it accepted one and re-photographed it"
fi

assert_contains "and it says how to re-mark one file on purpose" \
    "$guard_out" "ratchet.py init"

# A directory is the unit of a baseline, and that still works.
dir_code=0
( cd "$RATCHET_GUARD" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src >/dev/null 2>&1 ) || dir_code=$?
if [[ "$dir_code" -eq 0 ]]; then
    log_pass "a directory is still accepted"
else
    log_fail "a directory is still accepted" "exit $dir_code"
fi

# --- The two front-ends agree, which is the whole point of one engine ----------
#
# The first version of this feature lived in post-write-check.sh alone. The
# hook then reported without blocking while `craftsman-ci` refused the same
# file: a change that passes at the keyboard and fails in the pipeline, which
# is exactly the drift the parity tests exist to prevent. The decision moved
# into rules-engine.sh so both front-ends inherit it, and this asserts they do.
PARITY="$WORK/parity"
mkdir -p "$PARITY/src"
cat > "$PARITY/src/Legacy.php" <<'PHP'
<?php
namespace App;
class Legacy {
    public function total($amount) { return $amount * 2; }
}
PHP
( cd "$PARITY" && git init -q && git add -A ) >/dev/null 2>&1
( cd "$PARITY" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src >/dev/null 2>&1 )

parity_hook="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$PARITY/src/Legacy.php" "$PARITY" \
    | ( cd "$PARITY" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 ))"
parity_ci="$( cd "$PARITY" && bash "$ROOT_DIR/ci/craftsman-ci.sh" src 2>&1 )"

hook_blocks=no; echo "$parity_hook" | grep -q "BLOCKED" && hook_blocks=yes
ci_blocks=no; echo "$parity_ci" | grep -qE "^x [1-9]" && ci_blocks=yes

if [[ "$hook_blocks" == "$ci_blocks" ]]; then
    log_pass "the hook and the pipeline agree on a baselined file (both: blocks=$hook_blocks)"
else
    log_fail "the hook and the pipeline agree on a baselined file" \
        "hook blocks=$hook_blocks, ci blocks=$ci_blocks"
fi

assert_contains "and the pipeline says why it is not blocking, like the hook" \
    "$parity_ci" "already present at the baseline"

# --- Four ways the mark was read for the wrong file, or not at all -------------
#
# Every one of these ended the same way: recorded debt reported as new, a red
# build on code the user did not write, and nothing in the output saying the
# baseline had been missed. Each is asserted here because each was silent.
REACH="$WORK/reach"
mkdir -p "$REACH/bin" "$REACH/src/sub"
cat > "$REACH/src/Legacy.php" <<'PHP'
<?php
namespace App;
class Legacy {
    public function total($amount) { return $amount * 2; }
}
PHP
cp "$REACH/src/Legacy.php" "$REACH/src/sub/Deep.php"
( cd "$REACH" && git init -q && git add -A ) >/dev/null 2>&1
ln -sf "$ROOT_DIR/ci/craftsman-ci.sh" "$REACH/bin/craftsman-ci"

# 1. Reached through a symlink. `bin/craftsman-ci -> ../ci/craftsman-ci.sh` is
#    the ordinary way to put this on a PATH, and the unresolved dirname sent the
#    helper lookups to bin/, where nothing lives: the command printed its two
#    success lines and wrote no baseline at all.
( cd "$REACH" && bash bin/craftsman-ci baseline src >/dev/null 2>&1 )
if [[ -s "$REACH/.craftsman-baseline.json" ]]; then
    log_pass "invoked through a symlink, the baseline is still written"
else
    log_fail "invoked through a symlink, the baseline is still written" \
        "no .craftsman-baseline.json after baseline through bin/craftsman-ci"
fi

# 2. Overlapping roots. `craftsman-ci src src/sub` is an ordinary thing to type.
#    The occurrence counter had no caller resetting it, so the second pass over
#    a file read its own recorded debt as one occurrence too many and failed the
#    build. The file was also counted twice in "in N file(s)".
overlap="$( cd "$REACH" && bash bin/craftsman-ci src src/sub 2>&1 )"
if echo "$overlap" | grep -qE "^x [1-9]"; then
    log_fail "overlapping scan roots do not turn recorded debt into a violation" \
        "$(echo "$overlap" | grep -E '^x ')"
else
    log_pass "overlapping scan roots do not turn recorded debt into a violation"
fi
assert_contains "and the same file is not counted twice" "$overlap" "in 2 file(s)"

# 3. Run from a subdirectory. The anchor was the working directory, so a
#    pipeline doing `cd packages/api && craftsman-ci src` looked for the mark
#    beside itself, found none, and reported every recorded violation as new.
sub_out="$( cd "$REACH/src" && bash "$REACH/bin/craftsman-ci" Legacy.php 2>&1 )"
if echo "$sub_out" | grep -qE "^x [1-9]"; then
    log_fail "the mark is found from a subdirectory" \
        "$(echo "$sub_out" | grep -E '^x ')"
else
    log_pass "the mark is found from a subdirectory"
fi

# The anchor is what makes that work, so pin it in both directions: forcing the
# old behaviour must bring the failure back, or this test proves nothing.
old_anchor="$( cd "$REACH/src" && CRAFTSMAN_PROJECT_ROOT="$REACH/src" \
    bash "$REACH/bin/craftsman-ci" Legacy.php 2>&1 )"
if echo "$old_anchor" | grep -qE "^x [1-9]"; then
    log_pass "and anchoring on the working directory brings the failure back"
else
    log_fail "and anchoring on the working directory brings the failure back" \
        "the guardrail was never seen red: $(echo "$old_anchor" | tail -1)"
fi

# 4. An explicit promotion outranks the mark. Writing a rule id down by name in
#    .craft-rules.yml is a decision about this repository; staying advisory
#    because the file was marked is a setting silently ignored.
printf 'rules:\n  PHP001: block\n' > "$REACH/.craft-rules.yml"
promoted="$( cd "$REACH" && bash bin/craftsman-ci src 2>&1 )"
if echo "$promoted" | grep -qE "^x [1-9]"; then
    log_pass "an explicit promotion still blocks a recorded violation"
else
    log_fail "an explicit promotion still blocks a recorded violation" \
        "$(echo "$promoted" | tail -1)"
fi
rm -f "$REACH/.craft-rules.yml"

promoted_off="$( cd "$REACH" && bash bin/craftsman-ci src 2>&1 )"
if echo "$promoted_off" | grep -qE "^x [1-9]"; then
    log_fail "and without it the same file is pardoned again" \
        "$(echo "$promoted_off" | tail -1)"
else
    log_pass "and without it the same file is pardoned again"
fi

# --- The limit an adversarial review found, asserted rather than hidden --------
#
# The comparison is blind to content: a marked file replaced wholesale by a
# different class violating the same rules comes back as pre-existing debt.
# Hashing the file would catch it and would also turn every legitimate edit
# into a re-mark, which is the behaviour this feature exists to remove. So the
# limit stands, and it is written down in rule-baseline.sh and asserted here,
# because a reader who assumes otherwise will trust the gate for something it
# does not do.
REWRITE="$WORK/rewrite"
mkdir -p "$REWRITE/src"
printf '<?php\nnamespace App;\nclass One { public function a($v) { return $v; } }\n' > "$REWRITE/src/File.php"
( cd "$REWRITE" && git init -q && git add -A ) >/dev/null 2>&1
( cd "$REWRITE" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src >/dev/null 2>&1 )

printf '<?php\nnamespace App;\nclass Different { public function b($v) { return $v * 3; } }\n' > "$REWRITE/src/File.php"
rewrite_out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$REWRITE/src/File.php" "$REWRITE" \
    | ( cd "$REWRITE" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 ))"

if echo "$rewrite_out" | grep -q "BLOCKED"; then
    log_fail "a wholesale rewrite is not distinguished from the original" \
        "it blocked, so the comparison is content-aware after all and this note is stale"
else
    log_pass "a wholesale rewrite is not distinguished from the original (documented limit)"
fi

baseline_lib_text="$(cat "$ROOT_DIR/hooks/lib/rule-baseline.sh")"
assert_contains "and the limit is written where the next reader will look" \
    "$baseline_lib_text" "blind to content"

# --- What a baseline may never hold back ---------------------------------------
#
# The premise of the mechanism is that inherited debt is paid down on your own
# schedule. A hardcoded secret is not that: it is a live credential, the only
# correct response is to rotate it now, and recording one at the mark would
# have the plugin wave it through on every later edit to that file. Measured
# before the exemption existed: SEC001 was demoted exactly like PHP001.
mkdir -p "$REPO/src/Sec"
# Assembled here rather than written out, so this repository never carries a
# provider-shaped literal. GitHub push protection reads the fixture, not its
# intent, and refused the branch that first shipped this test.
SEC_PREFIX="sk"; SEC_ENV="live"
SEC_FIXTURE_KEY="${SEC_PREFIX}_${SEC_ENV}_4eC39HqLyjWDarjtT1zdp7dc"
cat > "$REPO/src/Sec/Keys.php" <<PHP
<?php
declare(strict_types=1);
final class Keys {
    private const KEY = "${SEC_FIXTURE_KEY}";
    public function query(string \$id): string { return "SELECT id FROM u WHERE id = " . \$id; }
}
PHP
( cd "$REPO" && git add -A ) >/dev/null 2>&1
( cd "$REPO" && bash "$ROOT_DIR/ci/craftsman-ci.sh" baseline src >/dev/null 2>&1 )

sec_out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$REPO/src/Sec/Keys.php" "$REPO" \
    | ( cd "$REPO" && bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1 ))"

if echo "$sec_out" | grep -q "BLOCKED"; then
    log_pass "a recorded secret still blocks: security is not debt"
else
    log_fail "a recorded secret still blocks: security is not debt" \
        "SEC001 was held back by the baseline: $(echo "$sec_out" | head -2)"
fi

assert_contains "and it is SEC001 that blocks, not something else" "$sec_out" "SEC001"

# The exemption is a list, and a list is the kind of thing that goes stale.
baseline_lib="$(cat "$ROOT_DIR/hooks/lib/rule-baseline.sh")"
if printf '%s' "$baseline_lib" | grep -qF 'SEC*|RATCHET001'; then
    log_pass "the exemption covers every SEC rule, not one of them"
else
    log_fail "the exemption covers every SEC rule, not one of them" \
        "the case arm no longer matches the SEC prefix"
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

# The mapping is enforced by a function, not by a model reading a table. That
# distinction is the finding: a decision that opens or closes the front door of
# the gate cannot depend on prose being obeyed.
DEFAULTS="$WORK/defaults"
mkdir -p "$DEFAULTS"
( cd "$DEFAULTS" && git init -q && git commit -q --allow-empty -m one ) >/dev/null 2>&1
fresh_default="$( cd "$DEFAULTS" && bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_default_strictness" )"
if [[ "$fresh_default" == "strict" ]]; then
    log_pass "a new project still defaults to strict"
else
    log_fail "a new project still defaults to strict" "got '$fresh_default'"
fi

( cd "$DEFAULTS" && for i in $(seq 2 21); do git commit -q --allow-empty -m "c$i"; done ) >/dev/null 2>&1
aged_default="$( cd "$DEFAULTS" && bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_default_strictness" )"
if [[ "$aged_default" == "moderate" ]]; then
    log_pass "a project with history defaults to moderate"
else
    log_fail "a project with history defaults to moderate" "got '$aged_default'"
fi

# An explicit setting always wins: the default is a default, not a ceiling.
printf 'strictness: strict\n' > "$DEFAULTS/.craft-config.yml"
explicit="$( cd "$DEFAULTS" && bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_strictness" )"
if [[ "$explicit" == "strict" ]]; then
    log_pass "an explicit strictness still wins over the default"
else
    log_fail "an explicit strictness still wins over the default" "got '$explicit'"
fi

test_summary
