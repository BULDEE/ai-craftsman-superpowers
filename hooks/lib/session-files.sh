#!/usr/bin/env bash
# =============================================================================
# The files a session owns, named after the session.
#
# One flat session-state.json for the whole machine meant one session's
# SessionEnd deleted another's pending findings, a project's cross-file
# patterns surfaced in a second project ("PHP001 found in 3 files" with one
# file local), and `verified` set by any project satisfied pre-push-verify in
# every other (learning-loop review, CR-3). Claude Code sets
# CLAUDE_CODE_SESSION_ID in hook subprocesses AND in Bash tool subprocesses,
# matching the `session_id` field of the hook input, so hooks and skills
# resolve the same per-session file without a bridge. With no id (the suites,
# an older Claude Code) the historical shared path is used, unchanged.
#
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
_session_files_id() {
    local id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
    printf '%s' "$id" | tr -cd 'A-Za-z0-9_-' | cut -c1-64
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
