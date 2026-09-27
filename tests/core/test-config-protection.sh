#!/usr/bin/env bash
# =============================================================================
# Config Protection Hook Tests
# Tests config-protection.sh blocks edits to quality-gate config files
# and leaves everything else untouched.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE

# The payloads here are the Claude Code shape with the host's own identity
# field (`prompt_id`, see tests/fixtures/hosts/claude-code): the hook reads the
# host off the payload, and `ask` is a decision only that host implements. A
# suite that built anonymous payloads passed on a developer's machine, where
# CLAUDECODE=1 is in the environment, and would have read `deny` on a runner.
run_hook() {
    local file_path="$1"
    local output
    output=$(jq -n --arg fp "$file_path" '{"prompt_id":"p1","tool_name":"Write","tool_input":{"file_path":$fp}}' | bash "$ROOT_DIR/hooks/config-protection.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}
# The same file from a host the hook cannot name: no identity in the payload,
# none in the environment.
run_hook_unknown_host() {
    local file_path="$1"
    local output
    output=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}' | env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u PLUGIN_ROOT -u GROK_SESSION_ID -u GROK_HOOK_EVENT -u GROK_AGENT bash "$ROOT_DIR/hooks/config-protection.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

echo ""
echo "=== Config Protection Hook Tests ==="

for cfg in "phpstan.neon" "phpstan.neon.dist" ".eslintrc.json" "eslint.config.js" ".php-cs-fixer.dist.php" "deptrac.yaml"; do
    result=$(run_hook "/tmp/project/$cfg")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "2" ]]; then
        log_pass "Blocks edits to $cfg (exit 2)"
    else
        log_fail "Should block edits to $cfg" "got exit $exit_code"
    fi
done

for src in "src/Domain/Order.php" "pyproject.toml" "package.json" "README.md"; do
    result=$(run_hook "/tmp/project/$src")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "0" && "${result#*|}" != *permissionDecision* ]]; then
        log_pass "Allows edits to $src (exit 0, no decision)"
    else
        log_fail "Should allow edits to $src" "got exit $exit_code: ${result#*|}"
    fi
done

# --- The gated party does not reconfigure the gate --------------------------
#
# Measured by the guardrail review: a Write to .craft-rules.yml,
# .craft-config.yml, .craftsman-baseline.json, .claude/settings.json or the
# plugin's own rules-engine.sh passed this hook with exit 0, and
# `strictness: relaxed` in the first two disarmed pre-write and post-write.
# The gate's own configuration is the user's to change, so it is handed to
# the human (permissionDecision: ask, the native prompt; in bypass mode the
# docs say it proceeds, and the hook cannot force a prompt there). Claude
# Code's settings and the plugin's own code have no legitimate writer in a
# project session: denied.
for own in ".craft-rules.yml" "src/Domain/.craft-rules.yml" ".craft-config.yml" ".craftsman-baseline.json"; do
    result=$(run_hook "/tmp/project/$own")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "0" ]] && echo "${result#*|}" | grep -q '"permissionDecision": *"ask"'; then
        log_pass "Hands $own to the human (permissionDecision: ask)"
    else
        log_fail "Should ask before $own is written" "got exit $exit_code: $(echo "${result#*|}" | tr '\n' ' ' | cut -c1-100)"
    fi
done
# A host that does not implement `ask` (Codex documents it as parsed and not
# implemented; an unknown host is treated the same) gets deny for the same
# file: a decision the host ignores would be no decision.
result=$(run_hook_unknown_host "/tmp/project/.craft-rules.yml")
exit_code="${result%%|*}"
if [[ "$exit_code" == "2" ]] && echo "${result#*|}" | grep -q '"permissionDecision": *"deny"'; then
    log_pass "Denies .craft-rules.yml on a host that cannot ask (exit 2, deny)"
else
    log_fail "Should deny .craft-rules.yml on an unknown host" "got exit $exit_code: $(echo "${result#*|}" | tr '\n' ' ' | cut -c1-100)"
fi
for denied in ".claude/settings.json" ".claude/settings.local.json" ".grok/config.toml" ".grok/settings.json" ".grok/hooks/native.json" "$ROOT_DIR/hooks/lib/rules-engine.sh" "$ROOT_DIR/rules/core.yml"; do
    case "$denied" in /*) target="$denied" ;; *) target="/tmp/project/$denied" ;; esac
    result=$(run_hook "$target")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "2" ]]; then
        log_pass "Denies $denied (exit 2)"
    else
        log_fail "Should deny $denied" "got exit $exit_code"
    fi
done
# The block message no longer teaches the model how to switch this hook off.
msg="$(jq -n '{"tool_input":{"file_path":"/tmp/project/phpstan.neon"}}' | bash "$ROOT_DIR/hooks/config-protection.sh" 2>&1 >/dev/null)"
if echo "$msg" | grep -q "CRAFTSMAN_DISABLED_HOOKS"; then
    log_fail "the block message does not name the switch that disarms it" "message still says CRAFTSMAN_DISABLED_HOOKS"
else
    log_pass "the block message does not name the switch that disarms it"
fi

# CR-204 (review of 4.12.0): the path the write REACHES decides, whatever its
# spelling. Relative paths, `//`, `/./`, an inner `..`, a symlinked parent and
# a case change all reached a protected file with exit 0 (F1, F2).
ALIAS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-alias.XXXXXX") || exit 1
ALIAS_DIR=$(cd "$ALIAS_DIR" && pwd -P)
mkdir -p "$ALIAS_DIR/proj/.claude" "$ALIAS_DIR/proj/src"
ln -s "$ALIAS_DIR/proj/.claude" "$ALIAS_DIR/proj/src/cfg"
run_in() {
    local cwd="$1" file_path="$2" mode="${3:-default}"
    (cd "$cwd" && jq -n --arg fp "$file_path" --arg cwd "$cwd" --arg m "$mode" \
        '{"prompt_id":"p1","cwd":$cwd,"permission_mode":$m,"tool_name":"Write","tool_input":{"file_path":$fp}}' \
        | bash "$ROOT_DIR/hooks/config-protection.sh" 2>/dev/null; echo "|$?")
}
ALIAS_MISS=""
for alias in ".claude/settings.json" "$ALIAS_DIR/proj//.claude/settings.json" "$ALIAS_DIR/proj/./.claude/settings.json" \
             ".claude/sub/../settings.json" "src/cfg/settings.json" ".Claude/Settings.json" "PHPStan.neon" \
             "$(printf '%s' "$ROOT_DIR" | tr '[:lower:]' '[:upper:]')/hooks/lib/rules-engine.sh"; do
    out=$(run_in "$ALIAS_DIR/proj" "$alias")
    [[ "${out##*|}" == "2" ]] || ALIAS_MISS+=" [$alias]"
done
if [[ -z "$ALIAS_MISS" ]]; then
    log_pass "relative, doubled, dotted, dot-dot, symlinked-parent and case-changed aliases of protected files are denied"
else
    log_fail "aliases of protected files are denied" "allowed:$ALIAS_MISS"
fi
# F4: `ask` is a decision only where a human is asked. In bypassPermissions
# the host proceeds on `ask`, so the gate's own configuration is denied there.
out=$(run_in "$ALIAS_DIR/proj" ".craft-config.yml" "bypassPermissions")
if [[ "${out##*|}" == "2" && "$out" == *'"deny"'* ]]; then
    log_pass "the gate's own config is denied, not asked, under bypassPermissions"
else
    log_fail "own config under bypassPermissions" "$out"
fi
out=$(run_in "$ALIAS_DIR/proj" ".craft-config.yml" "default")
if [[ "${out##*|}" == "0" && "$out" == *'"ask"'* ]]; then
    log_pass "the gate's own config is still asked in the default permission mode"
else
    log_fail "own config in default mode" "$out"
fi
# F3: the plugin's own data (registries, session state, bindings, bridges) is
# the gate's machinery: a forged registry cache disarmed the config gate.
DATA_MISS=""
for data in "$ALIAS_DIR/home/.claude/plugins/data/craftsman-x/lang-registry-abc.tsv" \
            "$ALIAS_DIR/home/.grok/craftsman/sessions/s1.json" \
            "$ALIAS_DIR/home/.claude/craftsman-set-verified.sh" \
            "$ALIAS_DIR/home/.codex/craftsman/cache/rule-registry-1.tsv"; do
    out=$(run_in "$ALIAS_DIR/proj" "$data")
    [[ "${out##*|}" == "2" ]] || DATA_MISS+=" [$data]"
done
if [[ -z "$DATA_MISS" ]]; then
    log_pass "the plugin's data, caches, session bindings and bridges are denied"
else
    log_fail "plugin data is denied" "allowed:$DATA_MISS"
fi
# F5: a registry that cannot be built is not an empty list of protected
# configs. A copy of the plugin whose registry compiler fails, with no earlier
# cache, let phpstan.neon through with exit 0.
BROKEN="$ALIAS_DIR/broken-plugin"
mkdir -p "$BROKEN"
(cd "$ROOT_DIR" && tar cf - hooks packs rules config .claude-plugin 2>/dev/null) | (cd "$BROKEN" && tar xf -)
printf 'import sys\nsys.exit(1)\n' > "$BROKEN/hooks/lib/lang_registry.py"
out=$(cd "$ALIAS_DIR/proj" && jq -n --arg cwd "$ALIAS_DIR/proj" \
    '{"prompt_id":"p1","cwd":$cwd,"tool_name":"Write","tool_input":{"file_path":"phpstan.neon"}}' \
    | CLAUDE_PLUGIN_ROOT="$BROKEN" CLAUDE_PLUGIN_DATA="$ALIAS_DIR/fresh-data" HOME="$ALIAS_DIR/home" \
      bash "$BROKEN/hooks/config-protection.sh" 2>/dev/null; echo "|$?")
if [[ "${out##*|}" == "2" && "$out" == *"registry"* ]]; then
    log_pass "a registry that cannot be built refuses the write instead of judging it against no list"
else
    log_fail "registry failure fails closed" "$out"
fi
rm -rf "$ALIAS_DIR"

# CRAFTSMAN_DISABLED_HOOKS opt-out still works for this hook
export CRAFTSMAN_DISABLED_HOOKS="config-protection"
result=$(run_hook "/tmp/project/phpstan.neon")
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "CRAFTSMAN_DISABLED_HOOKS=config-protection allows the edit"
else
    log_fail "Disabled-hooks opt-out should allow the edit" "got exit $exit_code"
fi
unset CRAFTSMAN_DISABLED_HOOKS

test_summary
