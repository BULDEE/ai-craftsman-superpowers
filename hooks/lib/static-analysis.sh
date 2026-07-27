#!/usr/bin/env bash
# =============================================================================
# Static Analysis Dispatcher (Level 2 & 3)
# Delegates to pack-specific static analysis tools via pack-loader.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/static-analysis.sh"
#   errors=$(sa_analyze_file "/path/to/file.php")
# =============================================================================

# One implementation, sourced rather than copied: three copies of a timeout
# fallback is three chances for them to drift apart.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-timeout.sh"

# The pack adapters call sa_timeout; portable_timeout is what it is.
sa_timeout() {
    portable_timeout "$@"
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
