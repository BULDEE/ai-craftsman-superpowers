#!/usr/bin/env bash
# =============================================================================
# generic.sh - Generic/fallback CI adapter
#
# Works with Jenkins, CircleCI, local dev, or any unsupported CI.
# Annotations go to stdout, comments are written to a markdown file.
# =============================================================================

adapter_detect() {
    return 0
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

adapter_annotate() {
    local report_file="$1"

    [[ ! -f "$report_file" ]] && return 0

    python3 -c "
import json, sys
report = json.load(sys.stdin)
for v in report.get('violations', []):
    sev = v.get('severity', 'warning').upper()
    f = v.get('file', '')
    line = v.get('line', 0)
    rule = v.get('rule', '')
    msg = v.get('message', '')
    print(f'{sev}: {f}:{line} [{rule}] {msg}')
" < "$report_file" 2>/dev/null
}

adapter_comment() {
    local report_file="$1"
    local output_file="${2:-craftsman-comment.md}"

    [[ ! -f "$report_file" ]] && return 0

    adapter_format_comment "$report_file" > "$output_file"
    echo "Comment written to: $output_file"
}

adapter_exit() {
    local report_file="$1"
    adapter_compute_exit "$report_file"
}
