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

[[ "${_CRAFTSMAN_SESSION_FILES_LOADED:-}" == 1 ]] && return 0
_CRAFTSMAN_SESSION_FILES_LOADED=1

SESSION_FILES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SESSION_FILES_LIB_DIR}/host.sh"

_session_files_dir() {
    if [[ "${_CRAFTSMAN_SESSION_DATA_DIR+x}" == x ]]; then
        printf '%s' "$_CRAFTSMAN_SESSION_DATA_DIR"
        return 0
    fi
    python3 "${SESSION_FILES_LIB_DIR}/runtime_paths.py" data 2>/dev/null || true
}

# The id, cleaned to what a filename may carry: a hook input is untrusted data
# and this string becomes part of a path.
# The environment fallback names the INNERMOST host's session: CODEX_SESSION_ID
# (set in a Codex Bash tool, measured equal to the hook payload's session_id on
# 0.154.0) before CLAUDE_CODE_SESSION_ID, which a Codex session started from a
# Claude Code Bash tool inherits from its parent (challenge review, F5).
_session_files_id() {
    local id="${1:-${CRAFTSMAN_SESSION_ID:-${GROK_SESSION_ID:-${CODEX_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_CODE_SESSION_ID:-}}}}}}"
    printf '%s' "$id" | tr -cd 'A-Za-z0-9_-' | cut -c1-64
}

session_files_bind() {
    CRAFTSMAN_SESSION_HOST=$(host_detect "${1:-}")
    export CRAFTSMAN_SESSION_HOST
    {
        IFS= read -r -d '' CRAFTSMAN_SESSION_ID || true
        IFS= read -r -d '' _CRAFTSMAN_SESSION_DATA_DIR || true
        IFS= read -r -d '' _CRAFTSMAN_CACHE_DIR || true
    } < <(printf '%s' "${1:-}" | python3 "${SESSION_FILES_LIB_DIR}/runtime_paths.py" context 2>/dev/null)
    export CRAFTSMAN_SESSION_ID
    return 0
}

session_files_register() {
    local directory
    directory=$(_session_files_dir)
    [[ -n "$directory" ]] || return 0
    python3 "${SESSION_FILES_LIB_DIR}/runtime_paths.py" bind \
        "${CRAFTSMAN_SESSION_HOST:-unknown}" "$(_session_files_id)" \
        "$(dirname "$(dirname "$SESSION_FILES_LIB_DIR")")" "$directory" 2>/dev/null || true
}

session_cache_dir() {
    if [[ -n "${_CRAFTSMAN_CACHE_DIR:-}" ]]; then
        printf '%s' "$_CRAFTSMAN_CACHE_DIR"
        return 0
    fi
    python3 "${SESSION_FILES_LIB_DIR}/runtime_paths.py" cache 2>/dev/null || true
}

session_file() {
    local name="$1" id directory
    directory=$(_session_files_dir)
    [[ -n "$directory" ]] || return 0
    id=$(_session_files_id "${2:-}")
    if [[ -z "$id" ]]; then
        printf '%s/%s' "$directory" "$name"
        return 0
    fi
    case "$name" in
        session-state.json) printf '%s/session-state-%s.json' "$directory" "$id" ;;
        *)                  printf '%s/%s-%s' "$directory" "$name" "$id" ;;
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
