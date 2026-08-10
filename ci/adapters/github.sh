#!/usr/bin/env bash
# =============================================================================
# github.sh - GitHub Actions CI adapter
#
# Uses GitHub Actions workflow commands for annotations and gh CLI for PR comments.
# =============================================================================

adapter_detect() {
    [[ -n "${GITHUB_ACTIONS:-}" ]]
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

# The escaping contract is real but documented nowhere: the workflow-commands
# page never mentions it, and it lives only in actions/toolkit
# (packages/core/src/command.ts). A message escapes % \r \n; a PROPERTY value
# escapes those plus : and , which are exactly the two characters framing
# `key=value,key=value::`. Emitting a path or a custom-rule message containing
# either silently corrupts or truncates the annotation.
#
# `line` is documented as "Line number, starting at 1" and defaults to 1 when
# absent, and the Checks API behind these annotations states line numbers start
# at 1. add_violation records line 0 for a file-level finding, so the property
# is omitted rather than asserting a line outside the documented range.
_gh_emit_annotations() {
    python3 -c "
import json, sys

def esc_data(value):
    return str(value).replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')

def esc_prop(value):
    return esc_data(value).replace(':', '%3A').replace(',', '%2C')

for v in json.load(sys.stdin).get('violations', []):
    path = str(v.get('file', ''))
    path = path[2:] if path.startswith('./') else path
    try:
        line = int(v.get('line', 0))
    except (TypeError, ValueError):
        line = 0
    props = 'file=' + esc_prop(path)
    if line >= 1:
        props += ',line=%d' % line
    cmd = 'error' if v.get('severity') == 'critical' else 'warning'
    print('::%s %s::[%s] %s' % (cmd, props,
                                esc_data(v.get('rule', '')),
                                esc_data(v.get('message', ''))))
" < "$1"
}

adapter_annotate() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    if ! _gh_emit_annotations "$report_file"; then
        echo "craftsman-ci: could not render GitHub annotations from $report_file" >&2
        return 1
    fi
}

_gh_pr_number() {
    local pr_number="${GITHUB_PR_NUMBER:-}"
    if [[ -z "$pr_number" && "${GITHUB_REF:-}" == refs/pull/*/merge ]]; then
        pr_number=$(echo "$GITHUB_REF" | sed 's|refs/pull/||;s|/merge||')
    fi
    printf '%s' "$pr_number"
}

# The call used to be `>/dev/null 2>&1` with its status discarded, so a 401, a
# revoked token and a delivered comment were the same event. The comment is
# cosmetic and must not fail the build, but it must not pass silently either.
_gh_post_comment() {
    local repo="$1" pr_number="$2" body="$3"

    local existing_id
    existing_id=$(gh api "repos/${repo}/issues/${pr_number}/comments" \
        --jq '.[] | select(.body | contains("Craftsman Quality Gate")) | .id' \
        2>/dev/null | head -1)

    if [[ -n "$existing_id" ]]; then
        gh api "repos/${repo}/issues/comments/${existing_id}" \
            --method PATCH --field body="$body" >/dev/null && return 0
    else
        gh api "repos/${repo}/issues/${pr_number}/comments" \
            --method POST --field body="$body" >/dev/null && return 0
    fi

    echo "craftsman-ci: the GitHub PR comment was not delivered" >&2
    return 1
}

adapter_comment() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    local pr_number
    pr_number=$(_gh_pr_number)
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

    _gh_post_comment "$repo" "$pr_number" "$comment_body"
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
