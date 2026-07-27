#!/usr/bin/env bash
# =============================================================================
# Static Analysis Dispatcher (Level 2 & 3)
# Delegates to pack-specific static analysis tools via pack-loader.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/static-analysis.sh"
#   errors=$(sa_analyze_file "/path/to/file.php")
# =============================================================================

# `timeout` is GNU coreutils. It is not on a stock macOS, and every analyser
# call below went through it: the command failed with 127, the `|| true`
# swallowed it, and Level 2 and Level 3 silently produced nothing on those
# machines while the plugin reported a clean gate. The fallback is a plain
# background job with a watchdog so the budget still holds with no coreutils
# installed.
sa_timeout() {
    local seconds="$1"; shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
        return $?
    fi

    # <&0 matters: bash redirects a background job's stdin from /dev/null unless
    # it is explicitly redirected, and every hook in this repository is fed its
    # payload on stdin. Without it the command reads nothing and returns as if
    # there were no input.
    "$@" <&0 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $waited -ge $seconds ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid"
}

sa_analyze_file() {
    local file="$1"
    # External tools read a leading dash as a flag, and the path charset allows
    # one. Anchoring a relative path with ./ makes it unambiguously a path, so a
    # file named "-c" or "--config" cannot become an option.
    [[ "$file" == /* || "$file" == ./* ]] || file="./$file"

    # Running the project's analysers means running the project's code (its
    # binaries under vendor/bin or node_modules/.bin, and the config files they
    # auto-discover). Refuse unless the machine owner allowed it globally.
    if declare -F config_trust_project_tools >/dev/null 2>&1; then
        config_trust_project_tools || return
    else
        return
    fi
    local ext="${file##*.}"
    local lang=""
    case "$ext" in
        php) lang="php" ;;
        ts|tsx) lang="typescript" ;;
        *) return ;;
    esac

    local result
    result=$(pack_run_static_analysis "$file" "$lang" 2>/dev/null)
    [[ -n "$result" ]] && echo "$result"
}
