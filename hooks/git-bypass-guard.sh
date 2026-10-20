#!/usr/bin/env bash
# =============================================================================
# Git Bypass Guard for Claude Code (CR-258)
# Refuses a git command that switches the project's own hooks off:
# `--no-verify`, `git commit -n`, `-c core.hooksPath=...`, `git config
# core.hooksPath <dir>`, HUSKY=0, SKIP=..., LEFTHOOK=0, and a `git stash` run
# in the same command as a commit. hooks/lib/git_bypass.py names them.
#
# A rule the model reads is advice: anthropics/claude-code #40117 shows six
# consecutive commits with --no-verify and git stash against CLAUDE.md rules
# forbidding it. The `if` filter in hooks.json is best effort (the hooks
# reference says so): a git call it cannot see, `env git ...` or `sh -c`,
# never reaches this script.
#
# TRIGGERS: PreToolUse for Bash, `if: "Bash(git *)"`
# EXIT CODES: 0 always; a refusal is a JSON permissionDecision "deny"
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "git-bypass-guard" "always" || exit 0

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT" 2>/dev/null)
[[ "$COMMAND" == *git* || "$COMMAND" == *HUSKY* || "$COMMAND" == *SKIP* || "$COMMAND" == *LEFTHOOK* ]] || exit 0

FOUND=$(printf '%s' "$COMMAND" | python3 "${SCRIPT_DIR}/lib/git_bypass.py")
[[ -z "$FOUND" ]] && exit 0

REASON="Craftsman refused this command: $(printf '%s' "$FOUND" | paste -sd ';' - | sed 's/;/; /g'). It switches off the project's git hooks, which are its quality gate. Fix what the hooks report and commit without the bypass. Skipping them is the user's call: they can run the command themselves, or disable this guard with hooks.disabled: git-bypass-guard."
echo "$REASON" >&2
jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
    }
}'
exit 0
