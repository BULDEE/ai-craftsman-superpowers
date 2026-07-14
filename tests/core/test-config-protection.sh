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

run_hook() {
    local file_path="$1"
    local output
    output=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}' | bash "$ROOT_DIR/hooks/config-protection.sh" 2>/dev/null)
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

for src in "src/Domain/Order.php" ".craft-config.yml" "pyproject.toml" "package.json" "README.md"; do
    result=$(run_hook "/tmp/project/$src")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "0" ]]; then
        log_pass "Allows edits to $src (exit 0)"
    else
        log_fail "Should allow edits to $src" "got exit $exit_code"
    fi
done

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
