#!/usr/bin/env bash
# =============================================================================
# Go Pack: errcheck Static Analysis (Level 2)
# Graceful degradation: prints nothing when the tool is not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/go/static-analysis/errcheck.sh"
#   findings=$(pack_sa_go "/path/to/file.go")
#
# Returns "CODE:LINE:MESSAGE", one per line. The code is what the rules engine
# resolves severity for, so it is the only thing a project's `.craft-config.yml`
# can reach.
#
# Why this exists: GO006 at Level 1 is a list of standard-library calls that are
# known to return an error. That list can only ever be a list. errcheck resolves
# types, so it sees the ignored error on a call into the project's own code,
# which is where the interesting ones are. pack.yml declares
# `bin/errcheck=GO004,GO006`, so when errcheck produces a verdict it owns those
# codes and the regex defers; when it is absent, times out, or is configured to
# skip a package, precedence_flush re-emits the Level 1 finding with full
# severity resolution. No verdict is not a clean verdict.
# =============================================================================

_pack_sa_go_bin() {
    if command -v errcheck >/dev/null 2>&1; then
        printf 'errcheck'
        return 0
    fi
    if [[ -x "${PWD}/bin/errcheck" ]]; then
        printf '%s' "${PWD}/bin/errcheck"
        return 0
    fi
    return 1
}

pack_sa_go() {
    local file="$1"
    local binary
    binary="$(_pack_sa_go_bin)" || return 0
    [[ -f "$file" ]] || return 0

    local package_dir
    package_dir="$(dirname "$file")"

    # errcheck reports `path:line:col\ttext`. It is asked for one package rather
    # than ./... because this runs per file on a write, and a repository-wide
    # pass is a CI concern, not a keystroke concern.
    local line path lineno message
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        path="${line%%:*}"
        [[ "$(basename "$path")" == "$(basename "$file")" ]] || continue
        lineno="$(printf '%s' "$line" | cut -d: -f2)"
        message="$(printf '%s' "$line" | cut -f2-)"
        [[ -z "$message" ]] && message="unchecked error"
        printf 'GO006:%s:%s\n' "$lineno" "$message"
    done < <("$binary" "$package_dir" 2>/dev/null)
}
