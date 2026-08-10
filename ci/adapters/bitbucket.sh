#!/usr/bin/env bash
# =============================================================================
# bitbucket.sh - Bitbucket Pipelines CI adapter
#
# Uses Bitbucket Reports API for annotations and PR comments API for commenting.
# =============================================================================

adapter_detect() {
    [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]
}

adapter_run() {
    local report_file="${1:-craftsman-report.json}"
    local extra_args=("${@:2}")

    # Streams kept apart. Folding stderr into the report meant any writer to
    # it corrupted the JSON, and the answer had been to silence every
    # diagnostic in the pipeline rather than to separate the two. Diagnostics
    # go to the build log, where a human reads them, and the report stays
    # parseable.
    bash "${CI_DIR}/craftsman-ci.sh" --format json "${extra_args[@]}" \
        > "$report_file" 2> "${report_file}.log" || true
    [[ -s "${report_file}.log" ]] && cat "${report_file}.log" >&2
    echo "$report_file"
}

_BB_API_URL=""
_BB_CURL_AUTH=()
_BB_REPORT_ID="craftsman-quality-gate"
_BB_VIOLATIONS=0; _BB_WARNINGS=0; _BB_FILES=0; _BB_RESULT=""; _BB_DETAILS=""

# Inside Pipelines the documented path needs no credentials at all: a proxy on
# localhost:29418 adds a valid Auth header to a plain http request against
# api.bitbucket.org. Requiring BITBUCKET_TOKEN meant that a user following the
# shipped template, which described it as an app password (Basic auth) while
# this sent Bearer, got no Code Insights and a single line on stderr.
_bb_transport() {
    if [[ -n "${BITBUCKET_TOKEN:-}" ]]; then
        _BB_API_URL="https://api.bitbucket.org/2.0"
        _BB_CURL_AUTH=(-H "Authorization: Bearer ${BITBUCKET_TOKEN}")
    elif [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]; then
        _BB_API_URL="http://api.bitbucket.org/2.0"
        _BB_CURL_AUTH=(--proxy "http://localhost:29418")
    else
        return 1
    fi

    [[ -n "${BITBUCKET_WORKSPACE:-}" && -n "${BITBUCKET_REPO_SLUG:-}" \
       && -n "${BITBUCKET_COMMIT:-}" ]]
}

_bb_report_url() {
    printf '%s/repositories/%s/%s/commit/%s/reports/%s' \
        "$_BB_API_URL" "$BITBUCKET_WORKSPACE" "$BITBUCKET_REPO_SLUG" \
        "$BITBUCKET_COMMIT" "$_BB_REPORT_ID"
}

# A delivery failure used to be indistinguishable from success: every call was
# `>/dev/null 2>&1` with its status dropped. Code Insights is the whole verdict
# surface on this platform, so an undelivered report is the deptrac failure
# again, one layer out.
_bb_put() {
    curl -sf -X PUT "${_BB_CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        --data "$2" "$1" >/dev/null
}

# An unreadable report is not a clean one. These three defaulted to 0 on a parse
# failure and the gate then published a green PASSED against the commit.
_bb_read_counts() {
    local report_file="$1"
    _BB_DETAILS=""
    _BB_VIOLATIONS=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" < "$report_file" 2>/dev/null) || _BB_VIOLATIONS=""
    _BB_WARNINGS=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['warnings'])" < "$report_file" 2>/dev/null) || _BB_WARNINGS=""
    _BB_FILES=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" < "$report_file" 2>/dev/null) || _BB_FILES=""

    if [[ ! "$_BB_VIOLATIONS" =~ ^[0-9]+$ || ! "$_BB_FILES" =~ ^[0-9]+$ ]]; then
        echo "Bitbucket adapter: ${report_file} is unreadable, reporting FAILED rather than a green gate" >&2
        # Zero in the NUMBER fields, and the truth in the free-form details
        # line. A negative sentinel read well to a human but the Reports API is
        # not documented to accept one, and a rejected report is a FAILED
        # verdict that never reaches the commit: worse than the green gate this
        # branch exists to prevent.
        _BB_VIOLATIONS=0 ; _BB_WARNINGS=0 ; _BB_FILES=0
        _BB_DETAILS="Craftsman gate FAILED: the report could not be read, so no file is known to have passed."
        _BB_RESULT="FAILED"
    elif [[ "$_BB_VIOLATIONS" -gt 0 || "$_BB_FILES" -eq 0 ]]; then
        _BB_RESULT="FAILED"
    else
        _BB_RESULT="PASSED"
    fi

    [[ -n "$_BB_DETAILS" ]] || _BB_DETAILS="Scanned ${_BB_FILES} files: ${_BB_VIOLATIONS} violations, ${_BB_WARNINGS} warnings"
}

adapter_annotate() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    if ! _bb_transport; then
        echo "Warning: no Bitbucket credentials and no pipeline proxy, skipping report annotations" >&2
        return 0
    fi

    _bb_read_counts "$report_file"

    if ! _bb_put_summary; then
        echo "craftsman-ci: the Bitbucket report was not delivered, the commit carries no verdict" >&2
        return 1
    fi
    _bb_put_annotations "$report_file"
}

_bb_put_summary() {
    _bb_put "$(_bb_report_url)" "{
            \"title\": \"Craftsman Quality Gate\",
            \"details\": \"${_BB_DETAILS}\",
            \"report_type\": \"BUG\",
            \"result\": \"${_BB_RESULT}\",
            \"data\": [
                {\"title\": \"Files scanned\", \"type\": \"NUMBER\", \"value\": ${_BB_FILES}},
                {\"title\": \"Violations\", \"type\": \"NUMBER\", \"value\": ${_BB_VIOLATIONS}},
                {\"title\": \"Warnings\", \"type\": \"NUMBER\", \"value\": ${_BB_WARNINGS}}
            ]
        }"
}

# line 0 is deliberately preserved: Bitbucket Cloud documents it as the
# file-level default ("it will appear at the top of the file specified by the
# path field"), which is the right rendering for a finding with no known line.
_bb_annotation_payloads() {
    python3 -c "
import json, sys

for index, v in enumerate(json.load(sys.stdin).get('violations', [])):
    path = str(v.get('file', ''))
    path = path[2:] if path.startswith('./') else path
    try:
        line = int(v.get('line', 0))
    except (TypeError, ValueError):
        line = 0
    print(json.dumps({
        'external_id': 'craftsman-%d' % index,
        'annotation_type': 'BUG',
        'severity': 'CRITICAL' if v.get('severity') == 'critical' else 'MEDIUM',
        'path': path,
        'line': max(line, 0),
        'summary': '[%s] %s' % (v.get('rule', ''), v.get('message', '')),
    }))
" < "$1" 2>/dev/null
}

_bb_put_annotations() {
    local annotation external_id undelivered=0

    while IFS= read -r annotation; do
        [[ -z "$annotation" ]] && continue
        external_id=$(printf '%s' "$annotation" \
            | python3 -c "import json,sys; print(json.load(sys.stdin)['external_id'])" 2>/dev/null)
        [[ -z "$external_id" ]] && continue
        _bb_put "$(_bb_report_url)/annotations/${external_id}" "$annotation" \
            || undelivered=$((undelivered + 1))
    done < <(_bb_annotation_payloads "$1")

    if [[ "$undelivered" -gt 0 ]]; then
        echo "craftsman-ci: ${undelivered} Bitbucket annotation(s) were not delivered" >&2
        return 1
    fi
}

adapter_comment() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    local workspace="${BITBUCKET_WORKSPACE:-}"
    local repo_slug="${BITBUCKET_REPO_SLUG:-}"
    local pr_id="${BITBUCKET_PR_ID:-}"
    local token="${BITBUCKET_TOKEN:-}"
    local api_url="https://api.bitbucket.org/2.0"

    if [[ -z "$workspace" || -z "$repo_slug" || -z "$pr_id" || -z "$token" ]]; then
        echo "Warning: Bitbucket PR vars not set, skipping PR comment" >&2
        adapter_format_comment "$report_file"
        return 0
    fi

    local comment_body
    comment_body=$(adapter_format_comment "$report_file")

    local existing_comment_id
    existing_comment_id=$(curl -sf \
        -H "Authorization: Bearer ${token}" \
        "${api_url}/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/comments" \
        2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('values', []):
    content = c.get('content', {}).get('raw', '')
    if 'Craftsman Quality Gate' in content:
        print(c['id'])
        break
" 2>/dev/null)

    if [[ -n "$existing_comment_id" ]]; then
        curl -sf \
            -X PUT \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data "$(python3 -c "import json,sys; print(json.dumps({'content':{'raw':sys.stdin.read()}}))" <<< "$comment_body")" \
            "${api_url}/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/comments/${existing_comment_id}" \
            >/dev/null 2>&1
    else
        curl -sf \
            -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data "$(python3 -c "import json,sys; print(json.dumps({'content':{'raw':sys.stdin.read()}}))" <<< "$comment_body")" \
            "${api_url}/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/comments" \
            >/dev/null 2>&1
    fi
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
