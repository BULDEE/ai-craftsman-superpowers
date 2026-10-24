#!/usr/bin/env bash
# =============================================================================
# The cockpit (ADR-0031): a function-hook module that shows what the core knows
# and carries a person's gestures back to it. It never holds a verdict.
#
# Since 4.14.0 it ships in the craftsman plugin itself, declared by a second
# hooks file that only Claude Code's manifest names. The repository rules need
# no engine and always run: `hooks/hooks.json`, which Codex, Grok and Hermes
# read, holds no module; the Claude Code file holds modules and nothing else;
# no other host's manifest names it; the module opens no database and
# registers no tool or agent type (either would let the model reach a decision
# ADR-0020 reserves for a person); and what is left under mods/ as a plugin of
# its own is listed in the marketplace and loads no module. Each check runs
# once on a fixture built to break it, so a check that cannot fail is caught
# here and not in review.
#
# The engine half (`claude plugin validate`, `claude plugin test`) runs when a
# `claude` binary is on PATH and says so when it is not: events and methods
# can change between builds, and a red module test is how a breaking one shows.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Prints one line per broken rule of a plugin root; nothing when it holds them.
plugin_problems() {
    local root="$1" modules
    modules=$(jq -r '.hooks // empty | strings' "$root/.claude-plugin/plugin.json" 2>/dev/null)
    [[ "$(jq -r 'has("modules")' "$root/hooks/hooks.json" 2>/dev/null)" == "false" ]] \
        || echo "hooks/hooks.json holds a module, and every host reads that file"
    [[ -n "$modules" ]] || { echo "the Claude Code manifest names no hooks file for the module"; return; }
    [[ "$(jq -c 'keys' "$root/$modules" 2>/dev/null)" == '["modules"]' ]] \
        || echo "$modules holds more than modules (command hooks belong in hooks/hooks.json)"
    grep -l -F "${modules#./}" "$root"/.codex-plugin/plugin.json "$root"/.grok-plugin/plugin.json 2>/dev/null \
        | sed 's/^/another host names the module file: /'
    module_source_problems "$root/mods/cockpit"
}

module_source_problems() {
    grep -rnEi --include='*.ts' --include='*.tsx' --exclude='*.test.ts' \
        'metrics\.db|sqlite|\b(select|delete)\b[^;]*\bfrom\b|\binsert into\b|\bupdate\b[^;]*\bset\b' \
        "$1" 2>/dev/null | sed 's/^/SQL or database access: /'
    grep -rnE --include='*.ts' --include='*.tsx' '\$\.(tool|agent)\.register' "$1" 2>/dev/null \
        | sed 's/^/registers a tool or agent type the model could call: /'
}

# A plugin left under mods/ (the 4.13 cockpit, now a migration stub).
stub_problems() {
    local mod="$1" marketplace="$2" name
    name=$(jq -r '.name // empty' "$mod/.claude-plugin/plugin.json" 2>/dev/null)
    jq -e --arg name "$name" --arg source "./mods/$(basename "$mod")" \
        '.plugins | any(.name == $name and .source == $source)' "$marketplace" >/dev/null 2>&1 \
        || echo "not listed in the marketplace as ${name:-?} from ./mods/$(basename "$mod")"
    [[ ! -e "$mod/hooks" ]] || echo "loads hooks of its own: it would register a second /instincts"
}

echo "=== Repository rules (ADR-0031) ==="
problems=$(plugin_problems "$ROOT_DIR")
if [[ -z "$problems" ]]; then
    log_pass "the craftsman plugin carries the cockpit module the way only Claude Code reads it"
else
    log_fail "the craftsman plugin carries the cockpit module the way only Claude Code reads it" "$problems"
fi
for manifest in "$ROOT_DIR"/mods/*/.claude-plugin/plugin.json; do
    [[ -f "$manifest" ]] || continue
    mod=$(dirname "$(dirname "$manifest")")
    problems=$(stub_problems "$mod" "$ROOT_DIR/.claude-plugin/marketplace.json")
    if [[ -z "$problems" ]]; then
        log_pass "$(basename "$mod") is a listed plugin that loads no module"
    else
        log_fail "$(basename "$mod") is a listed plugin that loads no module" "$problems"
    fi
done

echo ""
echo "=== Each rule can fail ==="
FIXTURES=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mods-test.XXXXXX")
trap 'rm -rf "$FIXTURES"' EXIT

make_plugin() {
    local root="$FIXTURES/$1"
    mkdir -p "$root/.claude-plugin" "$root/.codex-plugin" "$root/hooks" "$root/mods/cockpit"
    echo '{"name": "bad", "hooks": "./hooks/claude-code.json"}' > "$root/.claude-plugin/plugin.json"
    echo '{"name": "bad", "hooks": "./hooks/hooks.json"}' > "$root/.codex-plugin/plugin.json"
    echo '{"hooks": {"Stop": []}}' > "$root/hooks/hooks.json"
    echo '{"modules": ["../mods/cockpit/register.tsx"]}' > "$root/hooks/claude-code.json"
    echo 'export const register = () => {}' > "$root/mods/cockpit/register.tsx"
    printf '%s' "$root"
}

expect_problem() {
    local label="$1" problems="$2" pattern="$3"
    if grep -q "$pattern" <<<"$problems"; then
        log_pass "$label"
    else
        log_fail "$label" "expected '$pattern', got: ${problems:-nothing}"
    fi
}

clean=$(make_plugin clean)
if [[ -z "$(plugin_problems "$clean")" ]]; then
    log_pass "a plugin that holds every rule raises nothing"
else
    log_fail "a plugin that holds every rule raises nothing" "$(plugin_problems "$clean")"
fi

shared=$(make_plugin shared)
echo '{"modules": ["../mods/cockpit/register.tsx"], "hooks": {}}' > "$shared/hooks/hooks.json"
expect_problem "a module in the hooks file every host reads is refused" "$(plugin_problems "$shared")" "every host reads"

unnamed=$(make_plugin unnamed)
echo '{"name": "bad"}' > "$unnamed/.claude-plugin/plugin.json"
expect_problem "a module file the manifest does not name is refused" "$(plugin_problems "$unnamed")" "names no hooks file"

mixed=$(make_plugin mixed)
echo '{"modules": ["../mods/cockpit/register.tsx"], "hooks": {"Stop": []}}' > "$mixed/hooks/claude-code.json"
expect_problem "command hooks in the module file are refused" "$(plugin_problems "$mixed")" "more than modules"

leaked=$(make_plugin leaked)
echo '{"name": "bad", "hooks": "./hooks/claude-code.json"}' > "$leaked/.codex-plugin/plugin.json"
expect_problem "another host's manifest naming the module file is refused" "$(plugin_problems "$leaked")" "another host"

sql=$(make_plugin sql)
echo 'const q = "SELECT rule FROM instincts"' >> "$sql/mods/cockpit/register.tsx"
expect_problem "a module that queries the database itself is refused" "$(plugin_problems "$sql")" "SQL or database"

tool=$(make_plugin tool)
echo 'on("session.start", async ($, e, next) => { await $.tool.register({ name: "approve" }); return next(e) })' >> "$tool/mods/cockpit/register.tsx"
expect_problem "a module that registers a tool is refused" "$(plugin_problems "$tool")" "registers a tool"

stub="$FIXTURES/stub/mods/old"
mkdir -p "$stub/.claude-plugin" "$stub/hooks"
echo '{"name": "old"}' > "$stub/.claude-plugin/plugin.json"
echo '{"plugins": [{"name": "old", "source": "./mods/old"}]}' > "$FIXTURES/stub/marketplace.json"
expect_problem "a stub that still loads hooks is refused" "$(stub_problems "$stub" "$FIXTURES/stub/marketplace.json")" "second /instincts"
echo '{"plugins": []}' > "$FIXTURES/stub/marketplace.json"
expect_problem "a stub the marketplace does not list is refused" "$(stub_problems "$stub" "$FIXTURES/stub/marketplace.json")" "not listed"

echo ""
echo "=== Engine checks (claude plugin validate / test) ==="
if ! command -v claude >/dev/null 2>&1; then
    log_pass "skipped: no claude binary on PATH, the repository rules above still ran"
    test_summary
fi
out=$(cd "$ROOT_DIR" && claude plugin validate . 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then
    log_pass "craftsman: claude plugin validate loads the module"
else
    log_fail "craftsman: claude plugin validate" "$(tail -5 <<<"$out")"
fi
out=$(cd "$ROOT_DIR" && claude plugin test . 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then
    log_pass "craftsman: claude plugin test ($(grep -oE '[0-9]+ pass' <<<"$out"))"
else
    log_fail "craftsman: claude plugin test" "$(tail -15 <<<"$out")"
fi

test_summary
