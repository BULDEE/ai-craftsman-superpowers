#!/usr/bin/env bash
# =============================================================================
# bitbucket.sh — Bitbucket Pipelines CI adapter
#
# Uses Bitbucket Reports API for annotations and PR comments API for commenting.
# =============================================================================

adapter_detect() {
    [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]
}

adapter_run() {
    local report_file="${1:-craftsman-report.json}"
    local extra_args=("${@:2}")

    bash "${CI_DIR}/craftsman-ci.sh" --format json "${extra_args[@]}" > "$report_file" 2>&1 || true
    echo "$report_file"
}

adapter_annotate() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    local workspace="${BITBUCKET_WORKSPACE:-}"
    local repo_slug="${BITBUCKET_REPO_SLUG:-}"
    local commit="${BITBUCKET_COMMIT:-}"
    local token="${BITBUCKET_TOKEN:-}"
    local api_url="https://api.bitbucket.org/2.0"

    if [[ -z "$workspace" || -z "$repo_slug" || -z "$commit" || -z "$token" ]]; then
        echo "Warning: Bitbucket API vars not set, skipping report annotations" >&2
        return 0
    fi

    local report_id="craftsman-quality-gate"

    local violations warnings files_scanned result
    violations=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['violations'])" < "$report_file" 2>/dev/null || echo "0")
    warnings=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['warnings'])" < "$report_file" 2>/dev/null || echo "0")
    files_scanned=$(python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" < "$report_file" 2>/dev/null || echo "0")

    if [[ "$violations" -gt 0 ]]; then
        result="FAILED"
    else
        result="PASSED"
    fi

    curl -sf \
        -X PUT \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data "{
            \"title\": \"Craftsman Quality Gate\",
            \"details\": \"Scanned ${files_scanned} files: ${violations} violations, ${warnings} warnings\",
            \"report_type\": \"BUG\",
            \"result\": \"${result}\",
            \"data\": [
                {\"title\": \"Files scanned\", \"type\": \"NUMBER\", \"value\": ${files_scanned}},
                {\"title\": \"Violations\", \"type\": \"NUMBER\", \"value\": ${violations}},
                {\"title\": \"Warnings\", \"type\": \"NUMBER\", \"value\": ${warnings}}
            ]
        }" \
        "${api_url}/repositories/${workspace}/${repo_slug}/commit/${commit}/reports/${report_id}" \
        >/dev/null 2>&1

    python3 -c "
import json, sys
report = json.load(sys.stdin)
annotations = []
for i, v in enumerate(report.get('violations', [])):
    sev = 'CRITICAL' if v.get('severity') == 'critical' else 'MEDIUM'
    annotations.append({
        'external_id': f'craftsman-{i}',
        'annotation_type': 'BUG',
        'severity': sev,
        'path': v.get('file', ''),
        'line': v.get('line', 1),
        'summary': f\"[{v.get('rule', '')}] {v.get('message', '')}\"
    })
print(json.dumps(annotations))
" < "$report_file" 2>/dev/null | python3 -c "
import json, sys
annotations = json.load(sys.stdin)
for ann in annotations:
    print(json.dumps(ann))
" 2>/dev/null | while IFS= read -r annotation; do
        curl -sf \
            -X PUT \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data "$annotation" \
            "${api_url}/repositories/${workspace}/${repo_slug}/commit/${commit}/reports/${report_id}/annotations/$(echo "$annotation" | python3 -c "import json,sys; print(json.load(sys.stdin)['external_id'])" 2>/dev/null)" \
            >/dev/null 2>&1
    done
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
