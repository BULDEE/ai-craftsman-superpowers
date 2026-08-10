#!/usr/bin/env bash
# =============================================================================
# adapter.sh - Base contract, auto-detection, and unified comment formatter
#
# Provides:
#   adapter_auto_detect()     - detect CI provider from env vars
#   adapter_load()            - source the appropriate provider adapter
#   adapter_format_comment()  - generate markdown from JSON report
#
# All provider adapters implement the same contract:
#   adapter_detect()    - return 0 if running in this CI
#   adapter_run()       - run craftsman-ci.sh, produce report JSON
#   adapter_annotate()  - emit provider-specific annotations
#   adapter_comment()   - post/update PR comment via provider API
#   adapter_exit()      - compute exit code from report
# =============================================================================
set -uo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(dirname "$ADAPTER_DIR")"

# =============================================================================
# Auto-detection: identify CI provider from environment variables
# =============================================================================
# Ask each provider, in priority order, rather than reimplementing its
# predicate here. adapter_detect is part of the published contract and had no
# consumer at all: the env-var chain lived in this function, so a provider could
# have its detection corrected and nothing would change. A contract member
# nobody calls is a contract member that drifts unnoticed.
#
# Each provider is sourced in a subshell: the four define the same five function
# names, and sourcing them into this shell would leave the last one loaded.
ADAPTER_PROVIDER_PRIORITY=(github gitlab bitbucket)

adapter_auto_detect() {
    local provider
    for provider in "${ADAPTER_PROVIDER_PRIORITY[@]}"; do
        [[ -f "${ADAPTER_DIR}/${provider}.sh" ]] || continue
        if ( source "${ADAPTER_DIR}/${provider}.sh" && adapter_detect ) 2>/dev/null; then
            echo "$provider"
            return 0
        fi
    done
    echo "generic"
}

# =============================================================================
# Loader: source the appropriate adapter, fall back to generic
# =============================================================================
adapter_load() {
    local provider="${1:-}"
    [[ -z "$provider" ]] && provider=$(adapter_auto_detect)

    if [[ -f "${ADAPTER_DIR}/${provider}.sh" ]]; then
        source "${ADAPTER_DIR}/${provider}.sh"
    else
        source "${ADAPTER_DIR}/generic.sh"
        provider="generic"
    fi

    echo "$provider"
}

# =============================================================================
# Unified comment formatter: JSON report -> Markdown
# =============================================================================
# One parse, not seven. Every field used to spawn its own python3 with its own
# `|| default`, so an unreadable report rendered a comment full of defaults that
# reads exactly like a clean run.
_adapter_comment_fields() {
    python3 -c "
import json, sys
d = json.load(sys.stdin)
c = d.get('config', {})
s = d.get('summary', {})
print(d.get('version', 'unknown'))
print(c.get('strictness', 'strict'))
print(c.get('stack', 'fullstack'))
print(s.get('files_scanned', 0))
print(s.get('violations', 0))
print(s.get('warnings', 0))
print(len(d.get('violations', [])))
" < "$1" 2>/dev/null || printf 'unknown\nstrict\nfullstack\n0\n0\n0\n0\n'
}

ADAPTER_C_VERSION=""; ADAPTER_C_STRICTNESS=""; ADAPTER_C_STACK=""
ADAPTER_C_FILES=0; ADAPTER_C_VIOLATIONS=0; ADAPTER_C_WARNINGS=0; ADAPTER_C_ISSUES=0

_adapter_comment_read() {
    {
        read -r ADAPTER_C_VERSION
        read -r ADAPTER_C_STRICTNESS
        read -r ADAPTER_C_STACK
        read -r ADAPTER_C_FILES
        read -r ADAPTER_C_VIOLATIONS
        read -r ADAPTER_C_WARNINGS
        read -r ADAPTER_C_ISSUES
    } < <(_adapter_comment_fields "$1")
}

_adapter_comment_header() {
    local status="Passed"
    [[ "$ADAPTER_C_WARNINGS" -gt 0 ]] && status="Passed with warnings"
    [[ "$ADAPTER_C_VIOLATIONS" -gt 0 ]] && status="Failed"

    cat <<EOF
## Craftsman Quality Gate -- ${status}

| Metric | Value |
|--------|-------|
| Files scanned | ${ADAPTER_C_FILES} |
| Violations | ${ADAPTER_C_VIOLATIONS} |
| Warnings | ${ADAPTER_C_WARNINGS} |
| Rules config | ${ADAPTER_C_STRICTNESS} / ${ADAPTER_C_STACK} |

EOF
}

_adapter_comment_issue_table() {
    echo "### Issues"
    echo ""
    echo "| Rule | File | Line | Message | Severity |"
    echo "|------|------|------|---------|----------|"
    python3 -c "
import json, sys
for v in json.load(sys.stdin).get('violations', []):
    print('| \`%s\` | \`%s\` | %s | %s | %s |' % (
        v.get('rule', ''), v.get('file', ''), v.get('line', 0),
        v.get('message', ''), v.get('severity', '')))
" < "$1" 2>/dev/null
    echo ""
}

adapter_format_comment() {
    local report_file="$1"

    if [[ ! -f "$report_file" ]]; then
        echo "Error: report file not found: $report_file" >&2
        return 1
    fi

    _adapter_comment_read "$report_file"
    _adapter_comment_header
    [[ "$ADAPTER_C_ISSUES" -gt 0 ]] && _adapter_comment_issue_table "$report_file"

    echo "---"
    echo "*craftsman v${ADAPTER_C_VERSION} -- [docs](https://github.com/BULDEE/ai-craftsman-superpowers)*"
    return 0
}

# =============================================================================
# Exit code helper: shared logic for all adapters
# =============================================================================
# All three counts in one parse, so an unreadable report is distinguishable from
# a clean one. Defaulting a parse failure to zero was a fail-open: the adapters
# merge the scanner's stderr into this file, so anything that writes a warning,
# including a malformed rule in the audited repository's own .craft-config.yml,
# produced "0 violations" and a green gate.
_adapter_summary_counts() {
    python3 -c "
import json, sys
d = json.load(sys.stdin)['summary']
print(int(d['violations']), int(d['warnings']), int(d['files_scanned']))
" < "$1" 2>/dev/null
}

# files_scanned is read as well as the two counts because a gate that opened no
# file has not passed, it has not run. craftsman-ci.sh already refuses that run
# with exit 2, but every adapter_run ends in `|| true` and the verdict was
# recomputed here from the violation count alone, which cannot tell "clean" from
# "never ran": the guard held in direct mode and was discarded in the only mode
# the shipped templates use.
adapter_compute_exit() {
    local report_file="$1"

    local summary
    if ! summary=$(_adapter_summary_counts "$report_file"); then
        echo "craftsman-ci: report is not valid JSON, failing closed: $report_file" >&2
        echo "craftsman-ci: first line was: $(head -1 "$report_file" 2>/dev/null)" >&2
        return 2
    fi

    local violations warnings files_scanned
    read -r violations warnings files_scanned <<< "$summary"

    if [[ "$files_scanned" -eq 0 ]]; then
        echo "craftsman-ci: no file was scanned, so this is not a pass: $report_file" >&2
        return 2
    fi

    [[ "$violations" -gt 0 ]] && return 2
    [[ "$warnings" -gt 0 ]] && return 1
    return 0
}
