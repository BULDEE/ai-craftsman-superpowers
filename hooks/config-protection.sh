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
# Which files are a quality gate's own config is the packs' knowledge: the pack
# that ships the analyser is the one that knows what configures it. The literal
# list this replaces protected PHP and TypeScript only, so a pack could ship a
# blocking Level 2 gate and leave its config freely relaxable.
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
pack_loader_init

is_protected_config() {
    lang_all_capability protected_configs 2>/dev/null | grep -qxF "$BASENAME"
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
