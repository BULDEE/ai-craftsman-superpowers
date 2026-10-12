#!/usr/bin/env bash
# =============================================================================
# Companion mods (ADR-0031): a mod shows what the core knows and carries a
# person's gestures back to it. It never holds a verdict.
#
# The repository rules need no engine and always run: each mod is listed in
# the marketplace under its own folder, its hooks.json holds modules only, its
# source opens no database and registers no tool or agent type (either would
# let the model reach a decision ADR-0020 reserves for a person), and the
# craftsman plugin's own hooks.json, which Codex, Grok and Hermes read, holds
# no module. Each check runs once on a fixture built to break it, so a check
# that cannot fail is caught here and not in review.
#
# The engine half (`claude plugin validate`, `claude plugin test`) runs when a
# `claude` binary is on PATH and says so when it is not: the function-hook API
# is early access, and a red mod test is how a breaking release shows up.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"

# Prints one line per broken rule; nothing when the mod holds them all.
mod_problems() {
    local mod="$1" marketplace="$2" name relative
    name=$(jq -r '.name // empty' "$mod/.claude-plugin/plugin.json" 2>/dev/null)
    relative="./mods/$(basename "$mod")"
    [[ -n "$name" ]] || { echo "no name in .claude-plugin/plugin.json"; return; }
    jq -e --arg name "$name" --arg source "$relative" \
        '.plugins | any(.name == $name and .source == $source)' "$marketplace" >/dev/null 2>&1 \
        || echo "not listed in the marketplace as $name from $relative"
    # One version, the marketplace entry's, which bump-version.sh already
    # carries: a second copy in the manifest drifts the first release it misses.
    [[ "$(jq -r 'has("version")' "$mod/.claude-plugin/plugin.json" 2>/dev/null)" == "false" ]] \
        || echo "plugin.json carries a version: the marketplace entry is the one place it lives"
    [[ "$(jq -c 'keys' "$mod/hooks/hooks.json" 2>/dev/null)" == '["modules"]' ]] \
        || echo "hooks/hooks.json holds more than modules (command hooks belong to the craftsman plugin)"
    grep -rnEi --include='*.ts' --include='*.tsx' \
        'metrics\.db|sqlite|\b(select|delete)\b[^;]*\bfrom\b|\binsert into\b|\bupdate\b[^;]*\bset\b' \
        "$mod/hooks" "$mod/types" 2>/dev/null | sed 's/^/SQL or database access: /'
    grep -rnE --include='*.ts' --include='*.tsx' '\$\.(tool|agent)\.register' "$mod/hooks" 2>/dev/null \
        | sed 's/^/registers a tool or agent type the model could call: /'
}

echo "=== Repository rules (ADR-0031) ==="

if [[ "$(jq -r 'has("modules")' "$ROOT_DIR/hooks/hooks.json")" == "false" ]]; then
    log_pass "the craftsman plugin's hooks.json holds no function-hook module"
else
    log_fail "the craftsman plugin's hooks.json holds no function-hook module" "other hosts read it"
fi

MODS=()
for manifest in "$ROOT_DIR"/mods/*/.claude-plugin/plugin.json; do
    [[ -f "$manifest" ]] && MODS+=("$(dirname "$(dirname "$manifest")")")
done
if [[ ${#MODS[@]} -gt 0 ]]; then
    log_pass "${#MODS[@]} mod(s) found under mods/"
else
    log_fail "mods found under mods/" "none"
fi

for mod in "${MODS[@]}"; do
    problems=$(mod_problems "$mod" "$MARKETPLACE")
    if [[ -z "$problems" ]]; then
        log_pass "$(basename "$mod") holds the companion rules"
    else
        log_fail "$(basename "$mod") holds the companion rules" "$problems"
    fi
done

echo ""
echo "=== Each rule can fail ==="
FIXTURES=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mods-test.XXXXXX")
trap 'rm -rf "$FIXTURES"' EXIT

make_mod() {
    local dir="$FIXTURES/$1/mods/bad"
    mkdir -p "$dir/.claude-plugin" "$dir/hooks" "$dir/types"
    echo '{"name": "bad"}' > "$dir/.claude-plugin/plugin.json"
    echo '{"modules": ["./register.ts"]}' > "$dir/hooks/hooks.json"
    echo 'export const register = () => {}' > "$dir/hooks/register.ts"
    echo '{"plugins": [{"name": "bad", "source": "./mods/bad"}]}' > "$FIXTURES/$1/marketplace.json"
    printf '%s' "$dir"
}

expect_problem() {
    local label="$1" case_dir="$2" pattern="$3" problems
    problems=$(mod_problems "$case_dir" "$(dirname "$(dirname "$case_dir")")/marketplace.json")
    if grep -q "$pattern" <<<"$problems"; then
        log_pass "$label"
    else
        log_fail "$label" "expected '$pattern', got: ${problems:-nothing}"
    fi
}

clean=$(make_mod clean)
if [[ -z "$(mod_problems "$clean" "$FIXTURES/clean/marketplace.json")" ]]; then
    log_pass "a mod that holds every rule raises nothing"
else
    log_fail "a mod that holds every rule raises nothing" "$(mod_problems "$clean" "$FIXTURES/clean/marketplace.json")"
fi

unlisted=$(make_mod unlisted)
echo '{"plugins": [{"name": "bad", "source": "./"}]}' > "$FIXTURES/unlisted/marketplace.json"
expect_problem "a mod the marketplace lists from the wrong folder is refused" "$unlisted" "not listed"

versioned=$(make_mod versioned)
echo '{"name": "bad", "version": "1.0.0"}' > "$versioned/.claude-plugin/plugin.json"
expect_problem "a mod whose manifest carries its own version is refused" "$versioned" "carries a version"

mixed=$(make_mod mixed)
echo '{"modules": ["./register.ts"], "hooks": {"Stop": []}}' > "$mixed/hooks/hooks.json"
expect_problem "a mod carrying command hooks is refused" "$mixed" "more than modules"

sql=$(make_mod sql)
echo 'const q = "SELECT rule FROM instincts"' >> "$sql/hooks/register.ts"
expect_problem "a mod that queries the database itself is refused" "$sql" "SQL or database"

tool=$(make_mod tool)
echo 'on("session.start", async ($, e, next) => { await $.tool.register({ name: "approve" }); return next(e) })' >> "$tool/hooks/register.ts"
expect_problem "a mod that registers a tool is refused" "$tool" "registers a tool"

echo ""
echo "=== Engine checks (claude plugin validate / test) ==="
if ! command -v claude >/dev/null 2>&1; then
    log_pass "skipped: no claude binary on PATH, the repository rules above still ran"
else
    for mod in "${MODS[@]}"; do
        out=$(claude plugin validate "$mod" 2>&1); rc=$?
        if [[ $rc -eq 0 ]]; then
            log_pass "$(basename "$mod"): claude plugin validate"
        else
            log_fail "$(basename "$mod"): claude plugin validate" "$(tail -5 <<<"$out")"
        fi
        if compgen -G "$mod/tests/*.test.ts*" >/dev/null; then
            out=$(cd "$mod" && claude plugin test . 2>&1); rc=$?
            if [[ $rc -eq 0 ]]; then
                log_pass "$(basename "$mod"): claude plugin test ($(grep -oE '[0-9]+ pass' <<<"$out"))"
            else
                log_fail "$(basename "$mod"): claude plugin test" "$(tail -15 <<<"$out")"
            fi
        else
            log_fail "$(basename "$mod"): ships tests" "no tests/*.test.ts"
        fi
    done
fi

test_summary
