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
#   host_detect "$INPUT"          -> claude-code | codex | grok | copilot | unknown
#   host_supports_ask "$HOST"     -> 0 when PreToolUse `ask` is honoured
#
# `ask` is a Claude Code decision, and a Grok one (its hooks guide: allow,
# deny, ask, defer, read from `hookSpecificOutput.permissionDecision` first).
# Codex documents it as parsed and not implemented (the tool proceeds after an
# error), and Copilot's cloud surface denies it, so a gate that emits it there
# has decided nothing: the caller downgrades to deny.
# =============================================================================

# The payload's own marks, in the order a stronger mark beats a weaker one.
_host_from_payload() {
    # Measured on every captured event of each host (tests/fixtures/hosts):
    # Codex carries `model` on every event but SessionEnd and a null
    # `transcript_path` on all of them; Claude Code carries `prompt_id` on
    # every event but SessionStart and a string `transcript_path` on all.
    # Claude Code's marks are read BEFORE `model`, which is a field any host
    # may add between two releases: read first, it renamed a 2.1.278 session
    # codex, and the banner then said its own events were not loaded
    # (2026-09-20). What Codex alone carries is its tool and a NULL
    # transcript path.
    # An adapter that translated the payload names the host itself
    # (adapters/copilot/translate.py). Grok 1.0.30 (captured) sends every key
    # in both cases plus `workspaceRoot` and a lowercase `hookEventName`
    # (pre_tool_use); it also carries a `timestamp`, so it was read as Copilot
    # until it was captured (audit of 2026-09-15). A raw Copilot envelope
    # carries a `timestamp` with neither of those, which neither Claude Code
    # nor Codex sends.
    printf '%s' "$1" | jq -r '
        if (.craftsman_host // "") != "" then .craftsman_host
        elif has("workspaceRoot") and has("hookEventName") then "grok"
        elif has("timestamp") and (has("toolName") or has("tool_name") or has("sessionId")) then "copilot"
        elif .tool_name == "apply_patch" then "codex"
        elif has("prompt_id") or (.transcript_path | type) == "string" then "claude-code"
        elif has("model") or (has("transcript_path") and .transcript_path == null) then "codex"
        else "" end' 2>/dev/null
}

# What the process was told, when the payload said nothing. Grok exports
# GROK_SESSION_ID and GROK_HOOK_EVENT to every hook (its hooks guide) and, as
# a Claude-compatible host, may inherit CLAUDECODE from a parent shell: its
# own name is read first.
_host_from_environment() {
    [[ -n "${GROK_SESSION_ID:-}" || -n "${GROK_HOOK_EVENT:-}" ]] && { echo grok; return 0; }
    [[ "${CLAUDECODE:-}" == "1" || -n "${CLAUDE_CODE_SESSION_ID:-}" ]] && { echo claude-code; return 0; }
    [[ -n "${PLUGIN_ROOT:-}" && -z "${CLAUDE_PROJECT_DIR:-}" ]] && { echo codex; return 0; }
    echo unknown
}

host_detect() {
    local input="${1:-}" mark=""
    [[ -n "$input" ]] && mark=$(_host_from_payload "$input")
    [[ -n "$mark" ]] && { echo "$mark"; return 0; }
    _host_from_environment
}

host_supports_ask() {
    [[ "${1:-}" == "claude-code" || "${1:-}" == "grok" ]]
}
