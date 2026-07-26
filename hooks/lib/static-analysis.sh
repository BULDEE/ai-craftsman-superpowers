#!/usr/bin/env bash
# =============================================================================
# Static Analysis Dispatcher (Level 2 & 3)
# Delegates to pack-specific static analysis tools via pack-loader.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/static-analysis.sh"
#   errors=$(sa_analyze_file "/path/to/file.php")
# =============================================================================

sa_analyze_file() {
    local file="$1"
    # External tools read a leading dash as a flag, and the path charset allows
    # one. Anchoring a relative path with ./ makes it unambiguously a path, so a
    # file named "-c" or "--config" cannot become an option.
    [[ "$file" == /* || "$file" == ./* ]] || file="./$file"
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
