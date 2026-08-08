#!/usr/bin/env bash
# =============================================================================
# Doctrine export tests: rules engine stays the source of truth, output is
# regenerable, and rule overrides are reflected in every harness file.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

CLI="$ROOT_DIR/ci/craftsman-ci.sh"
WORK="/tmp/craftsman-export-test-$$"
mkdir -p "$WORK"
PREV_PWD="$PWD"
cd "$WORK"

echo "=== Export targets ==="

bash "$CLI" export --target all >/dev/null 2>&1

for file in "AGENTS.md" ".cursor/rules/craftsman.mdc" ".github/copilot-instructions.md"; do
    if [[ -f "$file" ]]; then
        log_pass "generated $file"
    else
        log_fail "export target" "$file missing"
    fi
done

if head -3 AGENTS.md | grep -q "Do not edit"; then
    log_pass "AGENTS.md marked as generated"
else
    log_fail "generated marker" "missing do-not-edit header"
fi

if head -5 .cursor/rules/craftsman.mdc | grep -q "alwaysApply: true"; then
    log_pass "cursor rule carries alwaysApply frontmatter"
else
    log_fail "cursor frontmatter" "missing alwaysApply"
fi

echo ""
echo "=== Content derives from the rules engine ==="

for rule in PHP001 LAYER001 LAYER004 DB003; do
    if grep -q "\*\*${rule}\*\*" AGENTS.md; then
        log_pass "AGENTS.md documents ${rule}"
    else
        log_fail "rule coverage" "${rule} missing from AGENTS.md"
    fi
done

# An ignored rule must disappear from the generated doctrine
cat > .craft-config.yml <<'YAML'
v: 4
strictness: strict
rules:
  PHP002: ignore
  DB001: warn
YAML

bash "$CLI" export --target agents-md >/dev/null 2>&1

if ! grep -q "\*\*PHP002\*\*" AGENTS.md; then
    log_pass "rule set to ignore is omitted from the doctrine"
else
    log_fail "ignore handling" "PHP002 still present after ignore override"
fi

if grep -q "\*\*DB001\*\* (warn)" AGENTS.md; then
    log_pass "severity override (warn) is reflected in the doctrine"
else
    log_fail "severity override" "DB001 not rendered as warn: $(grep DB001 AGENTS.md || echo missing)"
fi

echo ""
echo "=== The doctrine describes every rule the engine can emit ==="

# Four hardcoded lists used to cover 15 of the 38 rules the validators emit, and
# three of those 15 named the wrong rule: PHP003 was documented as "private
# constructor plus factory" while it enforces "no public setter", PHP004 as "no
# setters" while it enforces "no new DateTime()", TS002 as "readonly by default"
# while it enforces "no default export". A teammate on Codex reads this file and
# is blocked by a rule it never mentioned, or by one it described as something
# else. That is the drift the plugin exists to prevent, in the very artefact
# meant to carry the doctrine outward.
#
# Analyser passthrough codes (PHPSTAN*, ESLINT*, DEPTRAC*) are outside this
# contract: their text is the external tool's, not doctrine.
source "$ROOT_DIR/ci/doctrine-export.sh"
rm -f .craft-config.yml
bash "$CLI" export --target agents-md >/dev/null 2>&1

# -I and --exclude-dir: hooks/lib modules now import each other, so Python
# writes __pycache__ there in normal use. grep reports "Binary file ... matches"
# for a .pyc, that line lands in the rule list, and every downstream assertion
# then compares a filename against the doctrine. The guard was reporting drift
# that did not exist.
ENFORCED=$(grep -rhoIE --exclude-dir=__pycache__ \
    '\b(PHP|TS|LAYER|DB|PY|SH|SEC|GOD|LOC|NEST|PARAM|CTRL|RATCHET|WARN-[A-Z]+)[0-9]{3}\b' \
    "$ROOT_DIR/hooks" "$ROOT_DIR/packs" 2>/dev/null | sort -u)

UNDOCUMENTED=""
UNRENDERED=""
for rule in $ENFORCED; do
    # A rule with no entry falls through to the default branch, which echoes
    # the id straight back.
    [[ "$(_doctrine_rule_text "$rule")" == "$rule" ]] && UNDOCUMENTED="${UNDOCUMENTED} ${rule}"
    grep -q "\*\*${rule}\*\*" AGENTS.md 2>/dev/null || UNRENDERED="${UNRENDERED} ${rule}"
done

if [[ -z "$UNDOCUMENTED" ]]; then
    log_pass "all $(echo "$ENFORCED" | wc -w | tr -d ' ') enforced rules have doctrine text"
else
    log_fail "doctrine drift" "enforced but undocumented:${UNDOCUMENTED}"
fi

if [[ -z "$UNRENDERED" ]]; then
    log_pass "every enforced rule reaches the rendered file"
else
    log_fail "doctrine not rendered" "documented but absent from output:${UNRENDERED}"
fi

# A context file past 20000 characters is truncated by Hermes, 70% head and 20%
# tail, so an overflowing doctrine loses its middle without saying so.
DOCTRINE_SIZE=$(wc -c < AGENTS.md | tr -d ' ')
if [[ "$DOCTRINE_SIZE" -lt 20000 ]]; then
    log_pass "rendered doctrine is ${DOCTRINE_SIZE} chars, inside the 20000 context-file limit"
else
    log_fail "doctrine too large" "${DOCTRINE_SIZE} chars, harnesses truncate past 20000"
fi

echo ""
echo "=== Regeneration is stable ==="

cp AGENTS.md first-run.md
bash "$CLI" export --target agents-md >/dev/null 2>&1
if diff -q first-run.md AGENTS.md >/dev/null 2>&1; then
    log_pass "re-export produces identical output (no churn in git)"
else
    log_fail "stability" "output differs between runs"
fi

EXIT_CODE=0
bash "$CLI" export --target nonsense >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    log_pass "unknown target exits non-zero"
else
    log_fail "unknown target" "should fail"
fi

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
