#!/usr/bin/env bash
# =============================================================================
# Config Protection Hook for Claude Code
# Blocks Write/Edit to linter/formatter/architecture config files so an agent
# can't silently weaken quality gates instead of fixing the flagged code.
#
# TRIGGERS: PreToolUse for Write and Edit tools
# EXIT CODES: 0 = allow, 2 = block with reason
# =============================================================================
set -uo pipefail

trap 'echo "WARNING: config-protection.sh failed at line $LINENO" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "config-protection" "always" || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

BASENAME="$(basename "$FILE_PATH")"

# Single-purpose linter/formatter/architecture config files only.
# Multi-purpose files (pyproject.toml, package.json, .craft-config.yml) are
# intentionally excluded - .craft-config.yml is the user-facing rule override
# mechanism by design (see Rules Engine), and the others hold too much
# unrelated project metadata to block wholesale.
is_protected_config() {
    case "$BASENAME" in
        phpstan.neon|phpstan.neon.dist|phpstan.dist.neon) return 0 ;;
        .eslintrc|.eslintrc.js|.eslintrc.cjs|.eslintrc.json|.eslintrc.yml|.eslintrc.yaml) return 0 ;;
        eslint.config.js|eslint.config.mjs|eslint.config.cjs|eslint.config.ts) return 0 ;;
        .php-cs-fixer.php|.php-cs-fixer.dist.php) return 0 ;;
        deptrac.yaml|deptrac.yml) return 0 ;;
        .dependency-cruiser.js|.dependency-cruiser.cjs|dependency-cruiser.config.js) return 0 ;;
        *) return 1 ;;
    esac
}

is_protected_config || exit 0

echo "🚫 BLOCKED by AI Craftsman - config-protection: ${BASENAME} is a quality-gate config file." >&2
echo "Fix the flagged code instead of relaxing the rule, or use // craftsman-ignore: <RULE_ID> for a justified exception." >&2
echo "If this config change is genuinely intended, ask the user to make it directly, or set CRAFTSMAN_DISABLED_HOOKS=config-protection for this session." >&2

jq -n --arg file "$BASENAME" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("BLOCKED: " + $file + " is a quality-gate config file. Fix the underlying code instead of weakening the rule. Use // craftsman-ignore: <RULE_ID> for a justified single-file exception, or ask the user to change this config directly.")
    }
}'
exit 2
