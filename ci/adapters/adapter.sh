#!/usr/bin/env bash
# =============================================================================
# adapter.sh — Base contract, auto-detection, and unified comment formatter
#
# Provides:
#   adapter_auto_detect()     — detect CI provider from env vars
#   adapter_load()            — source the appropriate provider adapter
#   adapter_format_comment()  — generate markdown from JSON report
#
# All provider adapters implement the same contract:
#   adapter_detect()    — return 0 if running in this CI
#   adapter_run()       — run craftsman-ci.sh, produce report JSON
#   adapter_annotate()  — emit provider-specific annotations
#   adapter_comment()   — post/update PR comment via provider API
#   adapter_exit()      — compute exit code from report
# =============================================================================
set -uo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(dirname "$ADAPTER_DIR")"

# =============================================================================
# Auto-detection: identify CI provider from environment variables
# =============================================================================
adapter_auto_detect() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "github"
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        echo "gitlab"
    elif [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]; then
        echo "bitbucket"
    else
        echo "generic"
    fi
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
adapter_format_comment() {
    local report_file="$1"

    if [[ ! -f "$report_file" ]]; then
        echo "Error: report file not found: $report_file" >&2
        return 1
    fi

    local version timestamp strictness stack
    local files_scanned violations warnings

    version=$(python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" < "$report_file" 2>/dev/null || echo "unknown")
    timestamp=$(python3 -c "import json,sys; print(json.load(sys.stdin)['timestamp'])" < "$report_file" 2>/dev/null || echo "unknown")
    strictness=$(python3 -c "import json,sys; print(json.load(sys.stdin)['config']['strictness'])" < "$report_file" 2>/dev/null || echo "strict")
    stack=$(python3 -c "import json,sys; print(json.load(sys.stdin)['config']['stack'])" < "$report_file" 2>/dev/null || echo "fullstack")
    files_scanned=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" < "$report_file" 2>/dev/null || echo "0")
    violations=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" < "$report_file" 2>/dev/null || echo "0")
    warnings=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['warnings'])" < "$report_file" 2>/dev/null || echo "0")

    local status
    if [[ "$violations" -gt 0 ]]; then
        status="Failed"
    elif [[ "$warnings" -gt 0 ]]; then
        status="Passed with warnings"
    else
        status="Passed"
    fi

    cat <<EOF
## Craftsman Quality Gate -- ${status}

| Metric | Value |
|--------|-------|
| Files scanned | ${files_scanned} |
| Violations | ${violations} |
| Warnings | ${warnings} |
| Rules config | ${strictness} / ${stack} |

EOF

    local issue_count
    issue_count=$(python3 -c "import json,sys; print(len(json.load(sys.stdin)['violations']))" < "$report_file" 2>/dev/null || echo "0")

    if [[ "$issue_count" -gt 0 ]]; then
        echo "### Issues"
        echo ""
        echo "| Rule | File | Line | Message | Severity |"
        echo "|------|------|------|---------|----------|"

        python3 -c "
import json, sys
report = json.load(sys.stdin)
for v in report['violations']:
    rule = v.get('rule', '')
    f = v.get('file', '')
    line = v.get('line', 0)
    msg = v.get('message', '')
    sev = v.get('severity', '')
    print(f'| \`{rule}\` | \`{f}\` | {line} | {msg} | {sev} |')
" < "$report_file" 2>/dev/null
        echo ""
    fi

    echo "---"
    echo "*craftsman v${version} -- [docs](https://github.com/BULDEE/ai-craftsman-superpowers)*"
}

# =============================================================================
# Exit code helper: shared logic for all adapters
# =============================================================================
adapter_compute_exit() {
    local report_file="$1"

    local violations warnings
    violations=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" < "$report_file" 2>/dev/null || echo "0")
    warnings=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['warnings'])" < "$report_file" 2>/dev/null || echo "0")

    if [[ "$violations" -gt 0 ]]; then
        return 2
    elif [[ "$warnings" -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}
