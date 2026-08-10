#!/usr/bin/env bash
# =============================================================================
# React Pack: ESLint + Dependency-Cruiser Static Analysis (Level 2 & 3)
# Graceful degradation: returns empty string if tools not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/react/static-analysis/eslint.sh"
#   errors=$(pack_sa_typescript "/path/to/file.ts")
#
# Returns "CODE:LINE:MESSAGE", one per line. The code is what the rules engine
# resolves severity for, so it is the only thing a project's `.craft-config.yml`
# can reach.
#
# Both tools are asked for machine-readable output and never for their prose
# reporter. The prose is written for a human watching a terminal: it is
# reworded between minors, removed between majors, and it announces success in
# the same stream as the failures. Both defects this file has had came from
# reading it - see _pack_sa_eslint_run and _pack_sa_depcruise_run.
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: map an ESLint rule id to a craftsman violation code
# ---------------------------------------------------------------------------
_pack_sa_eslint_code_for_rule() {
    case "$1" in
        "@typescript-eslint/no-explicit-any"|"no-explicit-any") echo "ESLINT001" ;;
        "@typescript-eslint/no-unsafe-"*|"no-unsafe-assignment") echo "ESLINT002" ;;
        "import/no-cycle"|"import/no-restricted-paths") echo "ESLINT003" ;;
        "no-unused-vars"|"@typescript-eslint/no-unused-vars") echo "ESLINT004" ;;
        *) echo "ESLINT001" ;;
    esac
}

# ---------------------------------------------------------------------------
# pack_sa_typescript: Combined ESLint + Dependency-Cruiser analysis
# Returns: "CODE:LINE:MESSAGE" per line
#
# Each analyser prints its own findings, newline-terminated. Concatenating two
# command substitutions instead would glue the last ESLint finding onto the
# first dependency-cruiser one, because $() strips the trailing newline.
# ---------------------------------------------------------------------------
pack_sa_typescript() {
    local file="$1"
    _pack_sa_eslint_run "$file"
    _pack_sa_depcruise_run "$file"
}

# ===========================================================================
# ESLint (Level 2)
# ===========================================================================

_pack_sa_eslint_binary() {
    if [[ -f "node_modules/.bin/eslint" ]]; then
        printf 'node_modules/.bin/eslint'
        return 0
    fi
    if command -v npx >/dev/null 2>&1 && [[ -f "node_modules/eslint/package.json" ]]; then
        printf 'npx eslint'
    fi
    return 0
}

# Severity 2 is ESLint's error. A severity 1 message is the project's own
# warning, and a fatal parse error also arrives here with a null ruleId, which
# the code mapping turns into ESLINT001 rather than dropping: a file ESLint
# cannot parse is a finding, not a clean file.
_pack_sa_eslint_findings() {
    printf '%s' "$1" | jq -r '
        .[]? | .messages[]?
        | select(.severity == 2)
        | [(.ruleId // ""), (.line // 0), (.message | gsub("[\r\n]+"; " "))]
        | @tsv
    ' 2>/dev/null
}

# Deliberately NOT pinned to a safe config, unlike phpstan next door.
# phpstan is pinned because its bootstrapFiles key runs PHP while the
# config is merely being read, before any analysis is asked for. An eslint
# flat config is executable JavaScript by design, and running the
# project's rules IS what level 2 is for here: pinning a neutral config
# would leave eslint enforcing nothing. The consent gate is
# config_trust_project_tools, machine-owner only and off by default, and
# the plugin's own TS rules run at level 1 regardless.
#
# --format=json, and never `compact`. ESLint 9.0.0 removed compact from core
# (it survives as the eslint-formatter-compact package), so on every ESLint 9
# install the adapter asked for a formatter that no longer exists, the refusal
# went to stderr where `2>/dev/null` ate it, `|| true` flattened exit 2 into
# success, and Level 2 reported clean on every TypeScript file it was supposed
# to inspect. `json` is a core formatter in 8 and in 9, under eslintrc and
# under flat config alike, which is why it is the one asked for here.
#
# Verified against the real binaries, both config systems, since the config
# default changed in 9.0.0 and the formatter did not:
#
#   8.57.1  eslintrc            json ok      compact ok  (why this shipped)
#   8.57.1  flat config         json ok
#   9.39.5  flat config         json ok      compact refused
#   9.39.5  eslintrc + ESLINT_USE_FLAT_CONFIG=false
#                               json ok      compact refused
#   9.39.5  eslintrc, no env    no config found: ESLint 9 does not search for
#                               eslintrc, so nothing runs. Not the adapter's
#                               doing and not something it can repair; eslintrc
#                               support goes away entirely in ESLint 10.
#
# ESLint 9 also prints an ESLintRCWarning on stderr in the compat case. It does
# not reach stdout, so the json stays parseable - which a prose reporter could
# not have promised.
_pack_sa_eslint_run() {
    local file="$1" eslint output errors="" rule lineno msg code
    command -v jq >/dev/null 2>&1 || return 0
    eslint=$(_pack_sa_eslint_binary)
    [[ -n "$eslint" ]] || return 0

    output=$(sa_timeout "$SA_BUDGET_FILE_SECONDS" $eslint "$file" --format=json 2>/dev/null) || true
    [[ -n "$output" ]] || return 0

    while IFS=$'\t' read -r rule lineno msg; do
        [[ -n "$msg" ]] || continue
        code=$(_pack_sa_eslint_code_for_rule "$rule")
        errors="${errors}${code}:${lineno:-0}:${msg}"$'\n'
    done <<< "$(_pack_sa_eslint_findings "$output")"
    printf '%s' "$errors"
}

# ===========================================================================
# dependency-cruiser (Level 3)
# ===========================================================================

_pack_sa_depcruise_binary() {
    if [[ -f "node_modules/.bin/depcruise" ]]; then
        printf 'node_modules/.bin/depcruise'
        return 0
    fi
    if command -v npx >/dev/null 2>&1 && [[ -f "node_modules/dependency-cruiser/package.json" ]]; then
        printf 'npx depcruise'
    fi
    return 0
}

# A cruise reports violations between modules, not inside one, so there is no
# line to report and 0 is the honest answer. The module pair travels in the
# message instead: a cruise started from one file walks its whole import graph,
# so the violation shown may sit one hop away, and a finding that did not name
# its own modules would send the developer to the wrong file.
_pack_sa_depcruise_findings() {
    printf '%s' "$1" | jq -r '
        .summary.violations[]?
        | select(.rule.severity != "ignore")
        | [(.rule.name // "dependency-cruiser"), (.from // "?"), (.to // "?")]
        | @tsv
    ' 2>/dev/null
}

# --output-type json, and never `err`. The `err` reporter is prose: on a clean
# cruise it prints "no dependency violations found" to stdout, which the line
# loop this replaces turned into a blocking ESLINT003 - the gate refused a
# clean file and told the developer its dependencies were fine while doing it.
# A real violation fared no better, arriving as four fragments plus a summary
# line. Verified against dependency-cruiser 17.4.3, whose behaviour on a clean
# cruise is not what doc/cli.md still describes ("print nothing"), which is why
# the machine-readable reporter is the only one this adapter will read.
_pack_sa_depcruise_run() {
    local file="$1" depcruise output errors="" rule from to
    command -v jq >/dev/null 2>&1 || return 0
    depcruise=$(_pack_sa_depcruise_binary)
    [[ -n "$depcruise" ]] || return 0

    output=$(sa_timeout "$SA_BUDGET_PROJECT_SECONDS" $depcruise "$file" --output-type json 2>/dev/null) || true
    [[ -n "$output" ]] || return 0

    while IFS=$'\t' read -r rule from to; do
        [[ -n "$rule" ]] || continue
        errors="${errors}ESLINT003:0:${rule}: ${from} -> ${to}"$'\n'
    done <<< "$(_pack_sa_depcruise_findings "$output")"
    printf '%s' "$errors"
}
