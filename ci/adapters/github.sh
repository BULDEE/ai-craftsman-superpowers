#!/usr/bin/env bash
# =============================================================================
# github.sh — GitHub Actions CI adapter
#
# Uses GitHub Actions workflow commands for annotations and gh CLI for PR comments.
# =============================================================================

adapter_detect() {
    [[ -n "${GITHUB_ACTIONS:-}" ]]
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

    python3 -c "
import json, sys
report = json.load(sys.stdin)
for v in report.get('violations', []):
    sev = v.get('severity', 'warning')
    f = v.get('file', '')
    line = v.get('line', 1)
    rule = v.get('rule', '')
    msg = v.get('message', '')
    cmd = 'error' if sev == 'critical' else 'warning'
    print(f'::{cmd} file={f},line={line}::[{rule}] {msg}')
" < "$report_file" 2>/dev/null
}

adapter_comment() {
    local report_file="$1"
    local pr_number="${GITHUB_PR_NUMBER:-}"

    [[ ! -f "$report_file" ]] && return 0

    if [[ -z "$pr_number" ]]; then
        if [[ -n "${GITHUB_REF:-}" && "${GITHUB_REF:-}" == refs/pull/*/merge ]]; then
            pr_number=$(echo "$GITHUB_REF" | sed 's|refs/pull/||;s|/merge||')
        fi
    fi

    [[ -z "$pr_number" ]] && return 0

    local comment_body
    comment_body=$(adapter_format_comment "$report_file")

    if ! command -v gh &>/dev/null; then
        echo "Warning: gh CLI not available, skipping PR comment" >&2
        echo "$comment_body"
        return 0
    fi

    local repo="${GITHUB_REPOSITORY:-}"
    [[ -z "$repo" ]] && return 0

    local existing_id
    existing_id=$(gh api "repos/${repo}/issues/${pr_number}/comments" \
        --jq '.[] | select(.body | contains("Craftsman Quality Gate")) | .id' \
        2>/dev/null | head -1)

    if [[ -n "$existing_id" ]]; then
        gh api "repos/${repo}/issues/comments/${existing_id}" \
            --method PATCH \
            --field body="$comment_body" \
            >/dev/null 2>&1
    else
        gh api "repos/${repo}/issues/${pr_number}/comments" \
            --method POST \
            --field body="$comment_body" \
            >/dev/null 2>&1
    fi
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
