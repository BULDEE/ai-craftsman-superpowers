#!/usr/bin/env bash
# =============================================================================
# portable_timeout <seconds> <command...>
#
# `timeout` is GNU coreutils and is not installed on a stock macOS. Every
# analyser call in this plugin went through it, so on such a machine the call
# failed with 127, the `|| true` around it swallowed the failure, and Level 2
# and Level 3 static analysis silently produced nothing while the gate reported
# clean. This is the one implementation; hooks, packs and the test harness all
# source it rather than keeping a copy each.
#
# Returns the command's own exit status, or 124 when the budget runs out, which
# is what `timeout` itself returns.
# =============================================================================

[[ -n "${_PORTABLE_TIMEOUT_LOADED:-}" ]] && return 0
_PORTABLE_TIMEOUT_LOADED=1

# The fallback polls, and the poll interval is a direct cost: a fixed one
# second added roughly 160 seconds to the macOS CI job, which bills at ten
# times the Linux rate. Almost every call finishes in milliseconds, so the
# interval starts at 50ms and backs off for the rare long one. That keeps the
# common case near-free without spinning on a command that legitimately runs
# for a minute.
_PT_STEP_FAST_CS=5      # 50ms while the command is likely to finish
_PT_STEP_MED_CS=25      # 250ms after the first second
_PT_STEP_SLOW_CS=100    # 1s after ten seconds

portable_timeout() {
    local seconds="$1"; shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
        return $?
    fi

    # <&0 matters: bash redirects a background job's stdin from /dev/null
    # unless it is explicitly redirected, and every hook here is fed its
    # payload on stdin. Without it the command reads nothing and returns as if
    # there were no input.
    "$@" <&0 &
    _pt_watch "$!" "$(( seconds * 100 ))"
}

# Wait on a pid, killing it once the budget in centiseconds is spent.
_pt_watch() {
    local pid="$1" budget_cs="$2"
    local waited_cs=0 step_cs=$_PT_STEP_FAST_CS

    while kill -0 "$pid" 2>/dev/null; do
        if [[ $waited_cs -ge $budget_cs ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        _pt_sleep "$step_cs"
        waited_cs=$(( waited_cs + step_cs ))
        step_cs=$(_pt_next_step "$waited_cs")
    done

    wait "$pid"
}

_pt_next_step() {
    local waited_cs="$1"
    if [[ $waited_cs -ge 1000 ]]; then
        printf '%s' "$_PT_STEP_SLOW_CS"
    elif [[ $waited_cs -ge 100 ]]; then
        printf '%s' "$_PT_STEP_MED_CS"
    else
        printf '%s' "$_PT_STEP_FAST_CS"
    fi
}

# Sleep for a duration given in centiseconds. Both BSD and GNU sleep accept a
# fraction; POSIX only guarantees whole seconds, so anything under a second
# falls back to the integer form if the fractional call is rejected.
_pt_sleep() {
    local cs="$1"
    if [[ $cs -ge 100 ]]; then
        sleep $(( cs / 100 ))
        return 0
    fi
    sleep "0.$(printf '%02d' "$cs")" 2>/dev/null || sleep 1
}
