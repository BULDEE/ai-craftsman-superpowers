#!/usr/bin/env bash
# =============================================================================
# Symfony Pack: PHPStan + Deptrac Static Analysis (Level 2 & 3)
# Graceful degradation: returns empty string if tools not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/symfony/static-analysis/phpstan.sh"
#   errors=$(pack_sa_php "/path/to/file.php")
#
# Returns "CODE:LINE:MESSAGE", one per line. The code is what the rules engine
# resolves severity for, so it is the only thing a project's `.craft-config.yml`
# can reach. Emitting a blanket tool code where a craftsman rule describes the
# same defect is therefore not a cosmetic choice: it puts the finding out of
# configuration's reach entirely.
# =============================================================================

# ---------------------------------------------------------------------------
# Internal: map PHPStan error to craftsman violation code
# Format: "PHPSTAN<level>" - e.g. PHPSTAN001 for undefined var, PHPSTAN002 etc.
# PHPStan raw format: "path/to/file.php:42:message"
# ---------------------------------------------------------------------------
_pack_sa_phpstan_map_error() {
    local line="$1"
    local rule="PHPSTAN001"
    # Heuristics: assign specific codes based on common error patterns
    if echo "$line" | grep -qi "undefined variable\|Undefined variable"; then
        rule="PHPSTAN002"
    elif echo "$line" | grep -qi "call to undefined\|Call to undefined"; then
        rule="PHPSTAN003"
    elif echo "$line" | grep -qi "Cannot access\|cannot access"; then
        rule="PHPSTAN004"
    elif echo "$line" | grep -qi "does not exist\|not found"; then
        rule="PHPSTAN005"
    fi
    echo "$rule"
}

_pack_sa_phpstan_binary() {
    if [[ -f "vendor/bin/phpstan" ]]; then
        printf 'vendor/bin/phpstan'
        return 0
    fi
    command -v phpstan >/dev/null 2>&1 && printf 'phpstan'
    return 0
}

# Without an explicit --configuration, PHPStan auto-discovers phpstan.neon from
# the working directory, and its bootstrapFiles key require()s arbitrary PHP
# before analysis. A trusted phpstan binary is not enough: pin the config so a
# repository cannot supply one. Without a pinned config it does not run at all:
# the fallback that ran it bare when mktemp failed handed the repository's
# phpstan.neon back its bootstrapFiles.
#
# The status is returned, not flattened with `|| true`: a fatal error and a
# stopped run printed nothing, and nothing read exactly like a clean file
# (CR-212).
_pack_sa_phpstan_run() {
    local phpstan="$1" file="$2" safe_conf status=0
    safe_conf=$(mktemp -t craftsman-phpstan.XXXXXX) || return 1
    printf 'parameters:\n    level: max\n' > "$safe_conf"
    sa_timeout "$SA_BUDGET_FILE_SECONDS" $phpstan analyse "$file" --configuration="$safe_conf" --no-progress --error-format=raw 2>/dev/null || status=$?
    rm -f "$safe_conf"
    return "$status"
}

# PHPStan exits 0 with no error and 1 with errors, which the raw format prints
# one per line. A fatal error exits 255 with nothing on stdout, and an exit 1
# that printed nothing is no verdict either.
_pack_sa_phpstan_answered() {
    [[ "$1" == "0" ]] && return 0
    [[ "$1" == "1" && -n "$2" ]]
}

_pack_sa_phpstan() {
    local file="$1" phpstan output status=0
    phpstan=$(_pack_sa_phpstan_binary)
    [[ -z "$phpstan" ]] && return 0

    output=$(_pack_sa_phpstan_run "$phpstan" "$file") || status=$?
    if ! _pack_sa_phpstan_answered "$status" "$output"; then
        sa_declare_incomplete "phpstan" "$status"
        return 0
    fi
    _pack_sa_phpstan_findings "$output"
}

_pack_sa_phpstan_findings() {
    local output="$1" line lineno msg code errors=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # PHPStan raw format: "path/file.php:LINE MESSAGE"
        lineno=$(echo "$line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        msg=$(echo "$line" | sed -E 's/^[^:]+:[0-9]+//')
        code=$(_pack_sa_phpstan_map_error "$line")
        errors="${errors}${code}:${lineno:-0}:${msg}"$'\n'
    done <<< "$output"
    printf '%s' "$errors"
}

# ===========================================================================
# Deptrac (Level 3)
# ===========================================================================

_pack_sa_deptrac_binary() {
    if [[ -f "vendor/bin/deptrac" ]]; then
        printf 'vendor/bin/deptrac'
        return 0
    fi
    command -v deptrac >/dev/null 2>&1 && printf 'deptrac'
    return 0
}

# `github-actions` rather than `compact`. `compact` is not a deptrac formatter
# and never has been: 1.0.2, 2.0.4 and 4.7.1 all answer "Output formatter
# compact not found" and exit 1, so this adapter had never produced a single
# deptrac verdict on any release.
#
# Of the formatters that do exist, this is the only one putting a whole finding
# on one line with the file, the line and BOTH layer names. console splits a
# finding over two lines, table keeps the source layer in a column header, json
# and codeclimate need a parser and still bury the layers in free text, and xml
# has the layers as real fields but refuses to write to stdout. Checked by
# running the three majors, not read from docs whose console sample is stale.
#
# Only `::error file=` is read. Skipped and uncovered findings come out as
# `::warning`, and only when --report-skipped or --report-uncovered is passed,
# which this never does; anchoring on the level excludes them by construction
# rather than by hoping their wording stays different.
_pack_sa_deptrac_run() {
    local deptrac="$1"
    sa_timeout "$SA_BUDGET_PROJECT_SECONDS" $deptrac analyse \
        --no-progress --no-ansi --formatter=github-actions 2>/dev/null
}

# deptrac exits 0 on a clean analysis and 1 when it reports a violation, but 1
# as well when it fails before analysing (a missing depfile, an unknown
# formatter, an exception). Only the finding lines tell those apart, so an
# exit 1 without one `::error file=` line is no verdict (CR-212).
#
# A clean run declares no coverage. Exit 0 with nothing printed is also what a
# depfile that does not cover the boundary produces, and an analyser configured
# to ignore a rule leaves the regex reporting.
_pack_sa_deptrac_answered() {
    [[ "$1" == "0" ]] && return 0
    [[ "$1" == "1" ]] || return 1
    printf '%s\n' "$2" | grep -q '^::error file='
}

# The physical path of a file. deptrac reports absolute, symlink-resolved paths,
# so on macOS a project under /tmp comes back as /private/tmp and a plain string
# compare misses every violation.
_pack_sa_deptrac_realpath() {
    local dir
    dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s' "$dir" "$(basename "$1")"
}

# Both layer names out of a deptrac message, as "<depender>|<dependent>".
#
# Empty when the message is not a layer violation. That is the safe answer and
# the reason this is a separate step: an "uncovered dependency" line, or a
# message template a future deptrac changes, lands on DEPTRAC001 rather than on
# a rule that does not describe it.
_pack_sa_deptrac_layers() {
    printf '%s' "$1" \
        | sed -nE 's/.* must not depend on [^ ]+ \(([^()]+) on ([^()]+)\).*/\1|\2/p'
}

# The layer pair deptrac reports names the same boundaries the craftsman layer
# rules name, so the pair IS the mapping.
#
# A pair none of the four describes keeps DEPTRAC001. Filing it under the
# nearest layer rule would put a wrong label on a real defect, and a wrong label
# is worse than a generic one: it sends the developer to the wrong knowledge
# page and hands the wrong `.craft-rules.yml` key the power to silence it.
#
# LAYER004 is the persistence boundary, "persistence lives behind a repository
# interface", so a Domain layer depending on the ORM or on a layer the project
# named for storage is that boundary broken, and it routes to
# knowledge/persistence/repository-pattern.md, which is the fix. Those names
# only, and from Domain only: any other layer name is DEPTRAC001, not a guess.
_pack_sa_deptrac_map_layers() {
    case "$(printf '%s>%s' "$1" "$2" | tr '[:upper:]' '[:lower:]')" in
        "domain>infrastructure")    printf 'LAYER001' ;;
        "domain>presentation")      printf 'LAYER002' ;;
        "application>presentation") printf 'LAYER003' ;;
        "domain>doctrine"|"domain>persistence"|"domain>database") printf 'LAYER004' ;;
        "domain>orm"|"domain>storage") printf 'LAYER004' ;;
        *) printf 'DEPTRAC001' ;;
    esac
}

_pack_sa_deptrac_rule() {
    local layers
    layers=$(_pack_sa_deptrac_layers "$1")
    if [[ -z "$layers" ]]; then
        printf 'DEPTRAC001'
        return 0
    fi
    _pack_sa_deptrac_map_layers "${layers%%|*}" "${layers##*|}"
}

# One `::error file=<path>,line=<n>::<message>` line, or nothing when it does
# not concern the file under analysis.
_pack_sa_deptrac_line() {
    local line="$1" target="$2" base="$3" reported rest lineno msg
    case "$line" in "::error file="*) ;; *) return 0 ;; esac

    reported="${line#::error file=}"
    reported="${reported%%,line=*}"
    # Cheap filter first: the path test below costs two forks, and a project
    # sweep reports every file, not the one being edited.
    [[ "$reported" == *"/$base" ]] || return 0
    [[ "$(_pack_sa_deptrac_realpath "$reported")" == "$target" ]] || return 0

    rest="${line#*,line=}"
    lineno="${rest%%::*}"
    msg="${rest#*::}"
    printf '%s:%s:%s\n' "$(_pack_sa_deptrac_rule "$msg")" "${lineno:-0}" "$msg"
}

_pack_sa_deptrac() {
    local file="$1" deptrac output status=0
    deptrac=$(_pack_sa_deptrac_binary)
    [[ -z "$deptrac" ]] && return 0

    output=$(_pack_sa_deptrac_run "$deptrac") || status=$?
    if ! _pack_sa_deptrac_answered "$status" "$output"; then
        sa_declare_incomplete "deptrac" "$status"
        return 0
    fi
    _pack_sa_deptrac_findings "$file" "$output"
}

_pack_sa_deptrac_findings() {
    local file="$1" output="$2" line entry target base errors=""
    target=$(_pack_sa_deptrac_realpath "$file") || return 0
    base=$(basename "$file")
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        entry=$(_pack_sa_deptrac_line "$line" "$target" "$base")
        [[ -z "$entry" ]] && continue
        # The newline is re-added here because `$(...)` strips it. Appending the
        # substitution directly ran every finding of a project sweep together on
        # one line, where only the first one still had a parsable code.
        errors="${errors}${entry}"$'\n'
    done <<< "$output"
    printf '%s' "$errors"
}

# ---------------------------------------------------------------------------
# pack_sa_php: Combined PHPStan + Deptrac analysis
# Returns: "CODE:LINE:MESSAGE" per line
#
# Assembled with printf rather than `echo -e`: a PHP message carries fully
# qualified class names, and `echo -e` reads the `\n` of `App\namespace\Thing`
# as a newline, which splits one finding into two malformed ones.
# ---------------------------------------------------------------------------
pack_sa_php() {
    local file="$1" from_phpstan from_deptrac errors=""
    from_phpstan=$(_pack_sa_phpstan "$file")
    from_deptrac=$(_pack_sa_deptrac "$file")
    [[ -n "$from_phpstan" ]] && errors="${from_phpstan}"$'\n'
    [[ -n "$from_deptrac" ]] && errors="${errors}${from_deptrac}"$'\n'
    [[ -n "$errors" ]] && printf '%s' "$errors"
    return 0
}
