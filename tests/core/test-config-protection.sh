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
    output=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}' | env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u PLUGIN_ROOT bash "$ROOT_DIR/hooks/config-protection.sh" 2>/dev/null)
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
for denied in ".claude/settings.json" ".claude/settings.local.json" "$ROOT_DIR/hooks/lib/rules-engine.sh" "$ROOT_DIR/rules/core.yml"; do
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
