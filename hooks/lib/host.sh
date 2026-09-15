#!/usr/bin/env bash
# =============================================================================
# Which host is running this hook, from what the host actually sends.
#
# The payload first, the environment second, "unknown" last. Measured on the
# captures under tests/fixtures/hosts: Codex sends `tool_name: apply_patch`
# for every write, `turn_id` and `model` on every event and no `prompt_id`;
# Claude Code sends `prompt_id` and exports CLAUDECODE=1 to the hook process.
# A Codex hook launched from inside a Claude Code Bash tool inherits none of
# the CLAUDE_* variables (its shell policy scrubs them), so the environment
# alone would still be right, but the payload is what the host signed.
#
#   host_detect "$INPUT"          -> claude-code | codex | unknown
#   host_supports_ask "$HOST"     -> 0 when PreToolUse `ask` is honoured
#
# `ask` is a Claude Code decision. Codex documents it as parsed and not
# implemented (the tool proceeds after an error), so a gate that emits it
# there has decided nothing: the caller downgrades to deny.
# =============================================================================

host_detect() {
    local input="${1:-}" tool prompt_id turn_id
    if [[ -n "$input" ]]; then
        tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
        [[ "$tool" == "apply_patch" ]] && { echo codex; return 0; }
        prompt_id=$(printf '%s' "$input" | jq -r '.prompt_id // empty' 2>/dev/null)
        [[ -n "$prompt_id" ]] && { echo claude-code; return 0; }
        turn_id=$(printf '%s' "$input" | jq -r 'if has("turn_id") and has("model") then "y" else "" end' 2>/dev/null)
        [[ "$turn_id" == "y" ]] && { echo codex; return 0; }
    fi
    [[ "${CLAUDECODE:-}" == "1" || -n "${CLAUDE_CODE_SESSION_ID:-}" ]] && { echo claude-code; return 0; }
    [[ -n "${PLUGIN_ROOT:-}" && -z "${CLAUDE_PROJECT_DIR:-}" ]] && { echo codex; return 0; }
    echo unknown
}

host_supports_ask() {
    [[ "${1:-}" == "claude-code" ]]
}
