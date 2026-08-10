#!/usr/bin/env bash
# =============================================================================
# gitlab.sh - GitLab CI adapter
#
# Uses GitLab Code Quality JSON report for annotations and GitLab API for PR comments.
# =============================================================================

adapter_detect() {
    [[ -n "${GITLAB_CI:-}" ]]
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

# GitLab requires description, check_name, fingerprint, severity,
# location.path and location.lines.begin, processes nothing else, and states
# that the path must not be prefixed with "./" (the walk emits that prefix
# whenever the scanned path is "."). severity must stay inside
# info|minor|major|critical|blocker, lowercase.
_gl_build_codequality() {
    python3 -c "
import json, sys, hashlib

issues = []
for v in json.load(sys.stdin).get('violations', []):
    path = str(v.get('file', ''))
    path = path[2:] if path.startswith('./') else path
    try:
        line = int(v.get('line', 0))
    except (TypeError, ValueError):
        line = 0
    issues.append({
        'type': 'issue',
        'check_name': v.get('rule', 'unknown'),
        'description': v.get('message', ''),
        'categories': ['Style'],
        'severity': 'critical' if v.get('severity') == 'critical' else 'minor',
        'fingerprint': hashlib.md5(
            (str(v.get('rule', '')) + path + str(line)).encode()).hexdigest(),
        'location': {'path': path, 'lines': {'begin': line if line >= 1 else 1}},
    })
print(json.dumps(issues, indent=2))
" < "$1"
}

adapter_annotate() {
    local report_file="$1"
    local codequality_file="${2:-gl-code-quality-report.json}"

    [[ ! -f "$report_file" ]] && return 0

    # Built into a temporary file and moved into place only on success. The
    # redirect used to truncate the target before python ran, so a parse failure
    # left a zero-byte artifact, which GitLab reads as "no findings", and the
    # success line below was printed either way.
    local staged="${codequality_file}.tmp.$$"
    if ! _gl_build_codequality "$report_file" > "$staged" 2>/dev/null; then
        rm -f "$staged"
        echo "craftsman-ci: could not build the GitLab code quality report from ${report_file}" >&2
        return 1
    fi
    mv -f "$staged" "$codequality_file"

    echo "Code quality report written to: $codequality_file"
}

_GL_PROJECT_ID=""; _GL_MR_IID=""; _GL_API_URL=""; _GL_TOKEN=""

# CI_JOB_TOKEN is deliberately NOT a fallback. GitLab documents the job token as
# having GET access only to the notes API, and PRIVATE-TOKEN is not a job-token
# header at all, so the previous fallback could only ever 401 into /dev/null
# while the shipped template promised it worked. Posting a note needs a project
# access token or a PAT.
_gl_comment_env_ready() {
    _GL_PROJECT_ID="${CI_PROJECT_ID:-}"
    _GL_MR_IID="${CI_MERGE_REQUEST_IID:-}"
    _GL_API_URL="${CI_API_V4_URL:-https://gitlab.com/api/v4}"
    _GL_TOKEN="${GITLAB_TOKEN:-}"

    [[ -n "$_GL_PROJECT_ID" && -n "$_GL_MR_IID" && -n "$_GL_TOKEN" ]]
}

_gl_notes_url() {
    printf '%s/projects/%s/merge_requests/%s/notes' \
        "$_GL_API_URL" "$_GL_PROJECT_ID" "$_GL_MR_IID"
}

_gl_existing_note_id() {
    curl -sf -H "PRIVATE-TOKEN: ${_GL_TOKEN}" "$(_gl_notes_url)" 2>/dev/null \
        | python3 -c "
import json, sys
for n in json.load(sys.stdin):
    if 'Craftsman Quality Gate' in n.get('body', ''):
        print(n['id'])
        break
" 2>/dev/null
}

_gl_deliver_note() {
    local body="$1" note_id="$2"
    local url method

    if [[ -n "$note_id" ]]; then
        url="$(_gl_notes_url)/${note_id}"; method="PUT"
    else
        url="$(_gl_notes_url)"; method="POST"
    fi

    curl -sf -X "$method" \
        -H "PRIVATE-TOKEN: ${_GL_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$(printf '%s' "$body" \
            | python3 -c "import json,sys; print(json.dumps({'body': sys.stdin.read()}))")" \
        "$url" >/dev/null
}

adapter_comment() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    if ! _gl_comment_env_ready; then
        echo "Warning: GITLAB_TOKEN or the MR context is not set, skipping MR comment" >&2
        adapter_format_comment "$report_file"
        return 0
    fi

    local comment_body
    comment_body=$(adapter_format_comment "$report_file")

    if ! _gl_deliver_note "$comment_body" "$(_gl_existing_note_id)"; then
        echo "craftsman-ci: the GitLab MR note was not delivered" >&2
        return 1
    fi
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
