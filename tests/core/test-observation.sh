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
# Match the marker filename, not a hand-written label. Entry markers now come
# from the packs, so the label is composed from the declaring language and the
# marker itself; asserting the exact prose would pin a presentation detail and
# would have to change again with the next pack.
if echo "$MAP" | grep -q "composer.json"; then
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

echo ""
echo "=== Situational Signals ==="

SIGNALS=$(python3 "$CONVENTIONS" signals "$FIXTURE" 2>&1)
if echo "$SIGNALS" | jq -e '.existing_project == false and .has_tests == true' >/dev/null 2>&1; then
    log_pass "signals: young repo with tests reads as greenfield"
else
    log_fail "signals" "$SIGNALS"
fi

NOGIT="/tmp/craftsman-signals-$$"
mkdir -p "$NOGIT/src"
git -C "$NOGIT" init -q 2>/dev/null
for index in $(seq 1 25); do
    git -C "$NOGIT" -c user.email=t@t -c user.name=t commit -qm "c$index" --allow-empty 2>/dev/null
done
SIGNALS=$(python3 "$CONVENTIONS" signals "$NOGIT" 2>&1)
if echo "$SIGNALS" | jq -e '.existing_project == true and .legacy_signal == true' >/dev/null 2>&1; then
    log_pass "signals: 25 commits, no tests, no CI reads as legacy"
else
    log_fail "legacy signal" "$SIGNALS"
fi

if echo "$SIGNALS" | jq -e '.commit_count == 25 and .has_tests == false and .has_ci == false' >/dev/null 2>&1; then
    log_pass "signals: reports commit_count, has_tests and has_ci"
else
    log_fail "signal keys" "$SIGNALS"
fi

mkdir -p "$NOGIT/.github/workflows" "$NOGIT/tests"
SIGNALS=$(python3 "$CONVENTIONS" signals "$NOGIT" 2>&1)
if echo "$SIGNALS" | jq -e '.has_ci == true and .has_tests == true and .legacy_signal == false' >/dev/null 2>&1; then
    log_pass "signals: tests plus CI clears the legacy signal"
else
    log_fail "legacy signal cleared" "$SIGNALS"
fi
rm -rf "$NOGIT"

rm -rf "$FIXTURE"

test_summary
