#!/usr/bin/env bash
# =============================================================================
# gitlab.sh — GitLab CI adapter
#
# Uses GitLab Code Quality JSON report for annotations and GitLab API for PR comments.
# =============================================================================

adapter_detect() {
    [[ -n "${GITLAB_CI:-}" ]]
}

adapter_run() {
    local report_file="${1:-craftsman-report.json}"
    local extra_args=("${@:2}")

    bash "${CI_DIR}/craftsman-ci.sh" --format json "${extra_args[@]}" > "$report_file" 2>&1 || true
    echo "$report_file"
}

adapter_annotate() {
    local report_file="$1"
    local codequality_file="${2:-gl-code-quality-report.json}"

    [[ ! -f "$report_file" ]] && return 0

    python3 -c "
import json, sys, hashlib
report = json.load(sys.stdin)
issues = []
for v in report.get('violations', []):
    sev = v.get('severity', 'warning')
    if sev == 'critical':
        gl_severity = 'critical'
    else:
        gl_severity = 'minor'

    fingerprint = hashlib.md5(
        (v.get('rule','') + v.get('file','') + str(v.get('line',0))).encode()
    ).hexdigest()

    issues.append({
        'type': 'issue',
        'check_name': v.get('rule', 'unknown'),
        'description': v.get('message', ''),
        'categories': ['Style'],
        'severity': gl_severity,
        'fingerprint': fingerprint,
        'location': {
            'path': v.get('file', ''),
            'lines': {
                'begin': v.get('line', 1)
            }
        }
    })
print(json.dumps(issues, indent=2))
" < "$report_file" > "$codequality_file" 2>/dev/null

    echo "Code quality report written to: $codequality_file"
}

adapter_comment() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    local project_id="${CI_PROJECT_ID:-}"
    local mr_iid="${CI_MERGE_REQUEST_IID:-}"
    local api_url="${CI_API_V4_URL:-https://gitlab.com/api/v4}"
    local token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"

    if [[ -z "$project_id" || -z "$mr_iid" || -z "$token" ]]; then
        echo "Warning: GitLab API vars not set, skipping MR comment" >&2
        adapter_format_comment "$report_file"
        return 0
    fi

    local comment_body
    comment_body=$(adapter_format_comment "$report_file")

    local existing_note_id
    existing_note_id=$(curl -sf \
        -H "PRIVATE-TOKEN: ${token}" \
        "${api_url}/projects/${project_id}/merge_requests/${mr_iid}/notes" \
        2>/dev/null | python3 -c "
import json, sys
notes = json.load(sys.stdin)
for n in notes:
    if 'Craftsman Quality Gate' in n.get('body', ''):
        print(n['id'])
        break
" 2>/dev/null)

    if [[ -n "$existing_note_id" ]]; then
        curl -sf \
            -X PUT \
            -H "PRIVATE-TOKEN: ${token}" \
            -H "Content-Type: application/json" \
            --data "$(python3 -c "import json; print(json.dumps({'body': '''${comment_body}'''}))" 2>/dev/null)" \
            "${api_url}/projects/${project_id}/merge_requests/${mr_iid}/notes/${existing_note_id}" \
            >/dev/null 2>&1
    else
        curl -sf \
            -X POST \
            -H "PRIVATE-TOKEN: ${token}" \
            -H "Content-Type: application/json" \
            --data "$(python3 -c "import json; print(json.dumps({'body': '''${comment_body}'''}))" 2>/dev/null)" \
            "${api_url}/projects/${project_id}/merge_requests/${mr_iid}/notes" \
            >/dev/null 2>&1
    fi
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
