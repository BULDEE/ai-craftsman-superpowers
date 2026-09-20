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
#
# Measured on every captured event of each host (tests/fixtures/hosts):
# `model` is Codex's mark and `prompt_id` is Claude Code's. Codex sends
# `model` and never `prompt_id`; Claude Code sends `prompt_id` on its tool
# events and `model` on none of them. Both halves are needed, because
# neither alone holds: a Codex session run through its app server sends a
# REAL transcript path (fixture codex/0.154.0-app-server) where a project
# hook of the same version sent null, so the string-transcript clause called
# it claude-code and it wrote Claude Code's bridge (measured 2026-09-20);
# and a host may grow a `model` field between two releases, which a
# `model`-first rule would read as a change of host.
#
# An adapter that translated the payload names the host itself
# (adapters/copilot/translate.py). Grok 1.0.30 (captured) sends every key in
# both cases plus `workspaceRoot` and a lowercase `hookEventName`; it also
# carries a `timestamp`, so it was read as Copilot until it was captured
# (audit of 2026-09-15). A raw Copilot envelope carries a `timestamp` with
# neither of those, which neither Claude Code nor Codex sends.
_host_from_payload() {
    printf '%s' "$1" | jq -r '
        if (.craftsman_host // "") != "" then .craftsman_host
        elif has("workspaceRoot") and has("hookEventName") then "grok"
        elif has("timestamp") and (has("toolName") or has("tool_name") or has("sessionId")) then "copilot"
        elif .tool_name == "apply_patch" then "codex"
        elif has("model") and (has("prompt_id") | not) then "codex"
        elif has("prompt_id") or (.transcript_path | type) == "string" then "claude-code"
        elif has("transcript_path") and .transcript_path == null then "codex"
        else "" end' 2>/dev/null
}

# What the process was told, when the payload said nothing. Grok exports
# GROK_SESSION_ID and GROK_HOOK_EVENT to every hook (its hooks guide) and, as
# a Claude-compatible host, may inherit CLAUDECODE from a parent shell: its
# own name is read first.
# A skill has no payload: it runs in the host's shell tool and reads what
# that shell was given. Codex names its own session there (CODEX_SESSION_ID
# and CODEX_THREAD_ID, both equal to the payload's session_id, captured
# 2026-09-15) and it is read BEFORE Claude Code's variables, because a Codex
# session started from a Claude Code Bash tool inherits that parent's
# CLAUDECODE and CLAUDE_CODE_SESSION_ID while carrying its own CODEX ones.
# Without this, `craftsman-healthcheck` in a Codex session reported "unknown
# host" about Codex (measured 2026-09-20).
_host_from_environment() {
    [[ -n "${GROK_SESSION_ID:-}" || -n "${GROK_HOOK_EVENT:-}" ]] && { echo grok; return 0; }
    [[ -n "${CODEX_SESSION_ID:-}" || -n "${CODEX_THREAD_ID:-}" ]] && { echo codex; return 0; }
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
