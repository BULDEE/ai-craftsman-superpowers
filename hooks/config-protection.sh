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
source "${SCRIPT_DIR}/lib/host.sh"
HOST=$(host_detect "$INPUT")

# The files this call touches. A Write/Edit names one in `tool_input.file_path`;
# a Codex apply_patch names any number inside `tool_input.command`, and reading
# `file_path` alone let a patch to phpstan.neon or to .craft-rules.yml land
# with exit 0 (audit CR-117, C1). One reader for every shape: the mirror
# helper's --list, which is also what post-write reads.
FILE_PATHS=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
if [[ -z "$FILE_PATHS" ]]; then
    LISTING=$(printf '%s' "$INPUT" | python3 "${SCRIPT_DIR}/lib/write_mirror.py" --list 2>/dev/null); LISTING_RC=$?
    # A listing that crashed named nothing, and nothing is not a pass
    # (ADR-0029; review F3).
    [[ "$LISTING_RC" -ne 0 ]] && LISTING="UNREADABLE	the listing helper exited ${LISTING_RC}"
    if [[ "$LISTING" == UNREADABLE* ]]; then
        echo "🚫 BLOCKED by AI Craftsman - config-protection: the patch could not be read (${LISTING#UNREADABLE	}). A write the gate cannot read is not let through; rewrite the patch." >&2
        jq -n --arg why "${LISTING#UNREADABLE	}" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: ("the patch could not be read by the quality gate (" + $why + "); rewrite it")}}'
        exit 2
    fi
    # add/update/move/delete <TAB> path [<TAB> new path]: every path named,
    # source and destination alike (moving a config out of the way relaxes
    # the gate as surely as editing it).
    FILE_PATHS=$(printf '%s' "$LISTING" | awk -F'\t' 'NF>=2 {print $2} NF>=3 {print $3}')
fi
[[ -z "$FILE_PATHS" ]] && exit 0

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
#          "ask" proceeds and a hook cannot force a prompt there. On a host
#          that does not implement `ask` (Codex parses it and proceeds), the
#          same file is denied: a decision the host ignores is no decision.
#   deny   Claude Code's settings (`env`, `disableAllHooks`, and every hook
#          switch this plugin reads live there) and the installed plugin's
#          own files: no project session has a legitimate reason to write
#          either, and a hook is a script re-read on every call.
_gate_own_config() {
    case "$(basename "$1")" in
        .craft-rules.yml|.craft-config.yml|.craftsman-baseline.json) return 0 ;;
    esac
    return 1
}
# Every host's own hook wiring is the gate's machinery: Claude Code's
# settings, Codex's project hooks and config (`[features] hooks = false` lives
# there), Copilot's `.github/hooks/*.json` and `.copilot/hooks/`, and the
# installed plugin. A patch to `.codex/hooks.json` passed here with exit 0
# (independent verification, 2026-09-15).
_gate_own_machinery() {
    case "$1" in
        */.claude/settings.json|*/.claude/settings.local.json) return 0 ;;
        */.codex/hooks.json|*/.codex/config.toml) return 0 ;;
        */.github/hooks/*.json|*/.copilot/hooks/*|*/.github/copilot/settings.json|*/.github/copilot/settings.local.json) return 0 ;;
    esac
    [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && "$1" == "${CLAUDE_PLUGIN_ROOT%/}/"* ]]
}
_deny() {
    echo "🚫 BLOCKED by AI Craftsman - config-protection: $2" >&2
    jq -n --arg reason "$3" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 2
}
ASK_FILE=""
while IFS= read -r FILE_PATH; do
    [[ -z "$FILE_PATH" ]] && continue
    if _gate_own_machinery "$FILE_PATH"; then
        _deny "$FILE_PATH" "${FILE_PATH} is the gate's own machinery (a host's hook wiring or the installed plugin). Ask the user to change it." \
            "${FILE_PATH} is the quality gate's own machinery (a host's hook wiring or the installed plugin). A session does not rewrite the gate it runs under; ask the user to change it."
    fi
    if _gate_own_config "$FILE_PATH"; then
        host_supports_ask "$HOST" || _deny "$FILE_PATH" "$(basename "$FILE_PATH") configures the quality gate itself and this host cannot hand the write to the user. Ask the user to edit it directly." \
            "$(basename "$FILE_PATH") configures the quality gate itself (rule scope, strictness, or the debt baseline), and this host does not implement the ask decision, so the write is refused. Scoping a rule is the user's decision: ask them to edit the file directly."
        ASK_FILE="$(basename "$FILE_PATH")"
    fi
done <<< "$FILE_PATHS"
if [[ -n "$ASK_FILE" ]]; then
    jq -n --arg file "$ASK_FILE" '{
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
    lang_all_capability protected_configs 2>/dev/null | grep -qxF "$(basename "$1")"
}

PROTECTED=""
while IFS= read -r FILE_PATH; do
    [[ -n "$FILE_PATH" ]] && is_protected_config "$FILE_PATH" && PROTECTED="$(basename "$FILE_PATH")" && break
done <<< "$FILE_PATHS"
[[ -z "$PROTECTED" ]] && exit 0
BASENAME="$PROTECTED"

echo "🚫 BLOCKED by AI Craftsman - config-protection: ${BASENAME} is a quality-gate config file." >&2
echo "Fix the flagged code instead of relaxing the rule, or use // craftsman-ignore: <RULE_ID> for a justified exception." >&2
echo "If this config change is genuinely intended, ask the user to make it directly." >&2

jq -n --arg file "$BASENAME" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ($file + " is a quality-gate config file. Fix the underlying code instead of weakening the rule. Use // craftsman-ignore: <RULE_ID> for a justified single-file exception, or ask the user to change this config directly."),
        additionalContext: ("BLOCKED: " + $file + " is a quality-gate config file. Fix the underlying code instead of weakening the rule. Use // craftsman-ignore: <RULE_ID> for a justified single-file exception, or ask the user to change this config directly.")
    }
}'
exit 2
