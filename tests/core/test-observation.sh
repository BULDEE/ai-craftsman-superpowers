#!/usr/bin/env bash
# =============================================================================
# Setup-by-observation tests (ADR-0022): conventions generator + codemap
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

CONVENTIONS="$ROOT_DIR/hooks/lib/conventions.py"
CODEMAP="$ROOT_DIR/hooks/lib/codemap.py"
FIXTURE="/tmp/craftsman-observation-test-$$"

mkdir -p "$FIXTURE/src/Domain" "$FIXTURE/src/Infrastructure" "$FIXTURE/tests"
echo '<?php' > "$FIXTURE/src/Domain/User.php"
echo '<?php' > "$FIXTURE/src/Infrastructure/Repo.php"
echo 'test' > "$FIXTURE/tests/UserTest.php"
echo '{}' > "$FIXTURE/composer.json"

git -C "$FIXTURE" init -q 2>/dev/null
git -C "$FIXTURE" add -A 2>/dev/null
git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -qm "feat(user): add user entity" 2>/dev/null
git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -qm "fix(repo): handle nulls" --allow-empty 2>/dev/null
git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -qm "feat: another one" --allow-empty 2>/dev/null

echo "=== Conventions Generator ==="

ANALYZE=$(python3 "$CONVENTIONS" analyze "$FIXTURE" 2>&1)
if echo "$ANALYZE" | grep -q "Conventional Commits (100%"; then
    log_pass "detects conventional commit style from history"
else
    log_fail "commit style detection" "$ANALYZE"
fi

if echo "$ANALYZE" | grep -q "Clean Architecture layers"; then
    log_pass "detects Clean Architecture layout under src/"
else
    log_fail "layout detection" "missing layers line"
fi

if echo "$ANALYZE" | grep -q 'Separate `tests/` tree'; then
    log_pass "detects separate tests/ tree"
else
    log_fail "tests detection" "$ANALYZE"
fi

python3 "$CONVENTIONS" generate "$FIXTURE" "$FIXTURE/.claude/skills" >/dev/null 2>&1
GEN="$FIXTURE/.claude/skills/project-conventions/SKILL.md"
if [[ -f "$GEN" ]] && grep -q "user-invocable: false" "$GEN" && grep -q "Generated on" "$GEN"; then
    log_pass "generate writes project-conventions skill with provenance"
else
    log_fail "conventions generation" "missing or malformed $GEN"
fi

echo ""
echo "=== Codemap Generator ==="

MAP=$(python3 "$CODEMAP" "$FIXTURE" 2>&1)
if echo "$MAP" | grep -q "PHP (composer)"; then
    log_pass "codemap detects composer entry point"
else
    log_fail "codemap entry points" "$MAP"
fi

if echo "$MAP" | grep -q "php(3)"; then
    log_pass "codemap counts php files by language"
else
    log_fail "codemap language counts" "$MAP"
fi

if echo "$MAP" | grep -q "Test roots: tests/"; then
    log_pass "codemap reports test roots"
else
    log_fail "codemap test roots" "$MAP"
fi

if echo "$MAP" | grep -q "src/Domain/"; then
    log_pass "codemap lists top directories at depth 2"
else
    log_fail "codemap directories" "$MAP"
fi

rm -rf "$FIXTURE"

test_summary
