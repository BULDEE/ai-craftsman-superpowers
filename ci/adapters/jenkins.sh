#!/usr/bin/env bash
# =============================================================================
# jenkins.sh - Jenkins CI adapter
#
# Emits a Checkstyle XML report, which the Warnings Next Generation plugin
# reads natively: findings land on the file and line in the build's Issues
# view, in the diff of a change request, and in the trend graph, instead of
# scrolling past in the console log.
#
# Checkstyle rather than one of the plugin's other formats because the rules
# engine already produces exactly what its schema carries: a file, a line, a
# severity, a message, and a rule identifier. `source` is the identifier, so a
# LAYER001 in Jenkins is the same LAYER001 the hook prints locally and the same
# one GitLab's code quality report names.
#
# Jenkins has no comment API of its own: a change request comment needs the
# plugin for whichever forge hosts the branch, with credentials this adapter
# has no business holding. The markdown file is written instead, and the
# Jenkinsfile archives it.
# =============================================================================

adapter_detect() {
    # JENKINS_URL alone is not enough. Jenkins documents it as "only available
    # if Jenkins URL set in system configuration", so an instance that never
    # had one set exports nothing and the build falls back to generic.
    # BUILD_TAG is `jenkins-${JOB_NAME}-${BUILD_NUMBER}`, self-identifying and
    # not gated on that setting. BUILD_NUMBER on its own is not usable: several
    # other systems export it too.
    [[ -n "${JENKINS_URL:-}" || -n "${BUILD_TAG:-}" ]]
}

adapter_run() {
    local report_file="${1:-craftsman-report.json}"
    local extra_args=("${@:2}")

    # Streams kept apart, for the reason the GitLab adapter records: folding
    # stderr into the report means any writer to it corrupts the JSON.
    bash "${CI_DIR}/craftsman-ci.sh" --format json "${extra_args[@]}" \
        > "$report_file" 2> "${report_file}.log" || true
    [[ -s "${report_file}.log" ]] && cat "${report_file}.log" >&2
    echo "$report_file"
}

_JENKINS_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_jenkins_build_checkstyle() {
    python3 "${_JENKINS_ADAPTER_DIR}/checkstyle_report.py" < "$1"
}

adapter_annotate() {
    local report_file="$1"
    local checkstyle_file="${2:-craftsman-checkstyle.xml}"

    [[ ! -f "$report_file" ]] && return 0

    # Built into a temporary file and moved into place only on success. A
    # redirect straight onto the target truncates it before python runs, so a
    # parse failure leaves a zero-byte file, which Warnings NG reads as "no
    # findings" rather than as a broken report.
    local staged="${checkstyle_file}.tmp.$$"
    if ! _jenkins_build_checkstyle "$report_file" > "$staged" 2>/dev/null; then
        rm -f "$staged"
        echo "craftsman-ci: could not build the Checkstyle report from ${report_file}" >&2
        return 1
    fi
    mv -f "$staged" "$checkstyle_file"

    echo "Checkstyle report written to: $checkstyle_file"

    # The console still gets the findings. A build whose Warnings NG step is
    # not configured, or whose plugin is absent, must not lose them.
    adapter_format_comment "$report_file"
}

adapter_comment() {
    local report_file="$1"
    local comment_file="${2:-craftsman-comment.md}"

    [[ ! -f "$report_file" ]] && return 0

    adapter_format_comment "$report_file" > "$comment_file"
    echo "Comment written to: $comment_file"
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
