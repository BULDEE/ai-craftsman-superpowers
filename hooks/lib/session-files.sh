#!/usr/bin/env bash
# =============================================================================
# The files a session owns, named after the session.
#
# One flat session-state.json for the whole machine meant one session's
# SessionEnd deleted another's pending findings, a project's cross-file
# patterns surfaced in a second project ("PHP001 found in 3 files" with one
# file local), and `verified` set by any project satisfied pre-push-verify in
# every other (learning-loop review, CR-3).
#
# The id is the `session_id` of the hook payload, bound once per hook with
# session_files_bind. The environment is the fallback, not the source: a hook
# process inherits its parent's environment whole, and a Codex session
# started from a Claude Code Bash tool carries that Claude session's
# CLAUDE_CODE_SESSION_ID (tests/fixtures/hosts/codex/.../hook-env), so naming
# the files after the variable filed Codex's writes under the Claude session
# (audit CR-117, C3). Skills running in the Bash tool have no payload and keep
# the variable, which Claude Code sets there to the same value. With no id at
# all (the suites, an older host) the historical shared path is used.
#
#   session_files_bind <payload json>  bind this hook to the payload's
#                                      session_id (exported as
#                                      CRAFTSMAN_SESSION_ID for the helpers)
#   session_file <name> [session_id]   the per-session file for <name>
#                                      (session-state.json, session-start-ts,
#                                      session-writes, session-violations)
#   session_files_sweep [max_age_days] drop files of sessions that ended
#                                      without a SessionEnd (a crash, a kill)
# =============================================================================

_session_files_dir() {
    printf '%s' "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
}

# The id, cleaned to what a filename may carry: a hook input is untrusted data
# and this string becomes part of a path.
# The environment fallback names the INNERMOST host's session: CODEX_SESSION_ID
# (set in a Codex Bash tool, measured equal to the hook payload's session_id on
# 0.154.0) before CLAUDE_CODE_SESSION_ID, which a Codex session started from a
# Claude Code Bash tool inherits from its parent (challenge review, F5).
_session_files_id() {
    local id="${1:-${CRAFTSMAN_SESSION_ID:-${CODEX_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}}}"
    printf '%s' "$id" | tr -cd 'A-Za-z0-9_-' | cut -c1-64
}

session_files_bind() {
    local id
    id=$(printf '%s' "${1:-}" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
    [[ -n "$id" ]] && export CRAFTSMAN_SESSION_ID="$id"
    return 0
}

session_file() {
    local name="$1" id
    id=$(_session_files_id "${2:-}")
    if [[ -z "$id" ]]; then
        printf '%s/%s' "$(_session_files_dir)" "$name"
        return 0
    fi
    case "$name" in
        session-state.json) printf '%s/session-state-%s.json' "$(_session_files_dir)" "$id" ;;
        *)                  printf '%s/%s-%s' "$(_session_files_dir)" "$name" "$id" ;;
    esac
}

session_files_sweep() {
    local days="${1:-7}" dir
    dir=$(_session_files_dir)
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 1 -type f \
        \( -name 'session-state-*.json' -o -name 'session-start-ts-*' \
           -o -name 'session-writes-*' -o -name 'session-violations-*' \) \
        -mtime +"$days" -delete 2>/dev/null || true
}
