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
