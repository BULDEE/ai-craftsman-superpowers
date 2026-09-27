#!/usr/bin/env bash
# =============================================================================
# Go Pack: Go Static Analysis (Level 2) - errcheck today, room for more
#
# The file is not named after errcheck on purpose: `supersedes:` names the tool
# that outranks a Level 1 rule, and lang_registry.py refuses an entry whose tool
# shares its name with the pack's own adapter (a tool may not outrank its own
# verdicts). The adapter is the pack's Level 2 entry point; errcheck is one
# analyser behind it.
# Graceful degradation: prints nothing when the tool is not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/go/static-analysis/go-analysis.sh"
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
# `errcheck=GO004,GO006`, so when errcheck runs it owns those codes and the
# regex defers; when it is absent, times out, crashes, or is configured to skip
# a package, precedence_flush re-emits the Level 1 finding with full severity
# resolution. No verdict is not a clean verdict, which is why the coverage is
# declared only on a run that actually produced one, and declared as a record
# in the result (sa_declare_covered) rather than into the caller's shell state,
# which this function never reaches.
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
    local binary output status=0
    binary="$(_pack_sa_go_bin)" || return 0
    [[ -f "$file" ]] || return 0

    # It is asked for one package rather than ./... because this runs per
    # file on a write, and a repository-wide pass is a CI concern, not a
    # keystroke concern. Under the central budget like every other analyser:
    # called directly, no CRAFTSMAN_SA_BUDGET_* could stop it.
    output=$(sa_timeout "$SA_BUDGET_FILE_SECONDS" "$binary" "$(dirname "$file")" 2>/dev/null) || status=$?

    # errcheck exits 0 when every error is checked and 1 when it found one:
    # both are verdicts. 2 is its fatal exit (a package that does not load)
    # and 124 is the budget; neither says anything about GO004 or GO006, so
    # the regex keeps them, and the missing verdict is reported, not swallowed.
    if [[ $status -gt 1 ]]; then
        sa_declare_incomplete "errcheck" "$status"
        return 0
    fi

    # Declared here rather than left to the orchestrator: errcheck answers for
    # GO004 and GO006 whether or not it found anything, and a clean run is a
    # verdict.
    sa_declare_covered "GO004" "GO006"
    printf '%s\n' "$output" | _pack_sa_go_findings "$file"
}

# errcheck reports `path:line:col\ttext`, one line per finding; only the lines
# about the written file become findings.
_pack_sa_go_findings() {
    local file="$1" line path lineno message
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        path="${line%%:*}"
        [[ "$(basename "$path")" == "$(basename "$file")" ]] || continue
        lineno="$(printf '%s' "$line" | cut -d: -f2)"
        message="$(printf '%s' "$line" | cut -f2-)"
        [[ -z "$message" ]] && message="unchecked error"
        printf 'ERRCHECK001:%s:%s\n' "$lineno" "$message"
    done
}
