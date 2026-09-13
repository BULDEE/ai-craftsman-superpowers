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

# A gate that cannot run is not a clean verdict (ADR-0029): refused, with the
# line and the retry advice. Malformed input names no file and is let through
# by the tolerant read below, not by this trap.
trap 'echo "The craftsman config gate could not run (config-protection.sh, line $LINENO). Retry the write once; if it repeats, the gate needs attention, not the write." >&2; exit 2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "config-protection" "always" || exit 0

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || false
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[[ -z "$FILE_PATH" ]] && exit 0

BASENAME="$(basename "$FILE_PATH")"

# The gated party does not reconfigure the gate. Measured by the guardrail
# review: a Write to .craft-rules.yml, .craft-config.yml,
# .craftsman-baseline.json, .claude/settings.json or this plugin's own
# rules-engine.sh passed here with exit 0, and `strictness: relaxed` in the
# first two disarmed pre-write and post-write in the same session. Two
# answers, because two kinds of file:
#   ask    the gate's own configuration. Scoping a rule is the user's
#          decision by design (the block message offers it), so the write is
#          handed to the human through the native permission prompt rather
#          than refused. The docs are plain about the limit: in bypass mode
#          "ask" proceeds and a hook cannot force a prompt there.
#   deny   Claude Code's settings (`env`, `disableAllHooks`, and every hook
#          switch this plugin reads live there) and the installed plugin's
#          own files: no project session has a legitimate reason to write
#          either, and a hook is a script re-read on every call.
_gate_own_config() {
    case "$BASENAME" in
        .craft-rules.yml|.craft-config.yml|.craftsman-baseline.json) return 0 ;;
    esac
    return 1
}
_gate_own_machinery() {
    case "$FILE_PATH" in
        */.claude/settings.json|*/.claude/settings.local.json) return 0 ;;
    esac
    [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && "$FILE_PATH" == "${CLAUDE_PLUGIN_ROOT%/}/"* ]]
}
if _gate_own_machinery; then
    echo "🚫 BLOCKED by AI Craftsman - config-protection: ${FILE_PATH} is the gate's own machinery (Claude Code settings or the installed plugin). Ask the user to change it." >&2
    jq -n --arg file "$FILE_PATH" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ($file + " is the quality gate'"'"'s own machinery (Claude Code settings or the installed plugin). A session does not rewrite the gate it runs under; ask the user to change it.")
        }
    }'
    exit 2
fi
if _gate_own_config; then
    jq -n --arg file "$BASENAME" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: ($file + " configures the quality gate itself (rule scope, strictness, or the debt baseline). Scoping a rule is the user'"'"'s decision: approve it here, or edit the file yourself.")
        }
    }'
    exit 0
fi

# Single-purpose linter/formatter/architecture config files only.
# Multi-purpose files (pyproject.toml, package.json) are intentionally
# excluded: they hold too much unrelated project metadata to block wholesale.
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
echo "If this config change is genuinely intended, ask the user to make it directly." >&2

jq -n --arg file "$BASENAME" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("BLOCKED: " + $file + " is a quality-gate config file. Fix the underlying code instead of weakening the rule. Use // craftsman-ignore: <RULE_ID> for a justified single-file exception, or ask the user to change this config directly.")
    }
}'
exit 2
