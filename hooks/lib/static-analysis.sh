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

# Every analyser was capped at 2 seconds, which is below the cold start of all
# of them: phpstan, deptrac, eslint and an `npx` that has to resolve a package
# first. Each one therefore hit the cap, the `|| true` around it flattened the
# 124 into success, and Levels 2 and 3 reported clean on every file they were
# supposed to inspect. These are cold-start realistic, and they bound the worst
# case only: a warm analyser answers well inside a second.
SA_BUDGET_FILE_SECONDS="${CRAFTSMAN_SA_BUDGET_FILE:-15}"
SA_BUDGET_PROJECT_SECONDS="${CRAFTSMAN_SA_BUDGET_PROJECT:-30}"

# The pack adapters call sa_timeout; portable_timeout is what it is.
#
# A stopped analyser is not a clean file, and no caller can tell the two apart
# once `|| true` has flattened the status. Announce it so silence is never read
# as a pass.
sa_timeout() {
    local budget="$1" status
    portable_timeout "$@"
    status=$?
    if [[ $status -eq 124 ]]; then
        echo "craftsman: static analysis stopped after ${budget}s, this file was not fully analysed" >&2
    fi
    return $status
}

# An adapter's result reaches the front-end on stdout and nowhere else. The
# adapter runs inside at least one command substitution, the front-end's own
# `$(sa_analyze_file ...)`, so anything it does to shell state dies with that
# subshell: errcheck and clippy declared their coverage straight into
# precedence.sh from there, the declaration never reached the shell that
# flushes, and a clean run left the regex finding standing while a run with a
# finding produced it twice (CR-172). A record on stdout survives every level
# of substitution between the adapter and the front-end, which applies it.
#
# The prefix cannot open a finding: every finding line starts with the rule
# code the adapter wrote, and no rule code starts with `@`.
SA_COVERED_RECORD="@covered "

# sa_declare_covered <rule>... - the run that just ended gave a verdict on these
# rules, clean or not. Called only after a run that produced one: no verdict is
# not a clean verdict, and an undeclared rule is left to Level 1.
sa_declare_covered() {
    local rule
    for rule in "$@"; do
        printf '%s%s\n' "$SA_COVERED_RECORD" "$rule"
    done
}

# Running the project's analysers means running the project's code (its
# binaries under vendor/bin or node_modules/.bin, and the config files they
# auto-discover). Refuse unless the machine owner allowed it globally.
_sa_tools_trusted() {
    declare -F config_trust_project_tools >/dev/null 2>&1 || return 1
    config_trust_project_tools
}

# The language comes from the loaded packs, not from a list here. Falling back
# to no analysis when the registry is absent keeps this library usable
# standalone, and silence is the honest answer when nothing claims the file.
_sa_language_of() {
    type lang_for_file >/dev/null 2>&1 || return 0
    # A caller that sourced this library without initialising the registry would
    # otherwise get silence, which reads as "nothing to analyse" rather than as
    # "the analyser never ran". Building it is idempotent and disk-cached.
    if [[ -z "${_LANG_REGISTRY_FILE:-}" ]] && type pack_loader_init >/dev/null 2>&1; then
        pack_loader_init 2>/dev/null || true
    fi
    lang_for_file "$1"
}

sa_analyze_file() {
    local file="$1"
    # External tools read a leading dash as a flag, and the path charset allows
    # one. Anchoring a relative path with ./ makes it unambiguously a path, so a
    # file named "-c" or "--config" cannot become an option.
    [[ "$file" == /* || "$file" == ./* ]] || file="./$file"

    _sa_tools_trusted || return

    local lang
    lang=$(_sa_language_of "$file")
    [[ -z "$lang" ]] && return

    local result
    result=$(pack_run_static_analysis "$file" "$lang" 2>/dev/null)
    [[ -n "$result" ]] && echo "$result"
}
