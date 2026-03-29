#!/usr/bin/env bash
# =============================================================================
# CI Adapter Tests
# Tests auto-detection, adapter loading, comment formatting, and exit codes.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ADAPTER_BASE="$ROOT_DIR/ci/adapters/adapter.sh"
CI_DIR="$ROOT_DIR/ci"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}+${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}x${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# =============================================================================
# Guard: adapter.sh must exist
# =============================================================================
if [[ ! -f "$ADAPTER_BASE" ]]; then
    echo "FATAL: adapter.sh not found at $ADAPTER_BASE" >&2
    exit 1
fi

TEMP_DIR="/tmp/craftsman-adapter-tests-$$"
mkdir -p "$TEMP_DIR"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# =============================================================================
# 1. Auto-detection tests
# =============================================================================
echo ""
echo "=== Auto-Detection Tests ==="

# No env vars -> generic
(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    result=$(adapter_auto_detect)
    if [[ "$result" == "generic" ]]; then
        echo "PASS:no-env-generic"
    else
        echo "FAIL:no-env-generic:got $result"
    fi
)
result_line=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_auto_detect
)
if [[ "$result_line" == "generic" ]]; then
    log_pass "No CI env vars -> generic"
else
    log_fail "No CI env vars should detect generic" "got $result_line"
fi

# GITHUB_ACTIONS -> github
result_line=$(
    export GITHUB_ACTIONS=true
    unset GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_auto_detect
)
if [[ "$result_line" == "github" ]]; then
    log_pass "GITHUB_ACTIONS=true -> github"
else
    log_fail "GITHUB_ACTIONS should detect github" "got $result_line"
fi

# GITLAB_CI -> gitlab
result_line=$(
    export GITLAB_CI=true
    unset GITHUB_ACTIONS BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_auto_detect
)
if [[ "$result_line" == "gitlab" ]]; then
    log_pass "GITLAB_CI=true -> gitlab"
else
    log_fail "GITLAB_CI should detect gitlab" "got $result_line"
fi

# BITBUCKET_BUILD_NUMBER -> bitbucket
result_line=$(
    export BITBUCKET_BUILD_NUMBER=42
    unset GITHUB_ACTIONS GITLAB_CI 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_auto_detect
)
if [[ "$result_line" == "bitbucket" ]]; then
    log_pass "BITBUCKET_BUILD_NUMBER=42 -> bitbucket"
else
    log_fail "BITBUCKET_BUILD_NUMBER should detect bitbucket" "got $result_line"
fi

# Priority: GitHub wins when multiple are set
result_line=$(
    export GITHUB_ACTIONS=true
    export GITLAB_CI=true
    export BITBUCKET_BUILD_NUMBER=42
    source "$ADAPTER_BASE"
    adapter_auto_detect
)
if [[ "$result_line" == "github" ]]; then
    log_pass "Multiple env vars -> github wins (first in chain)"
else
    log_fail "GitHub should win when multiple set" "got $result_line"
fi

# =============================================================================
# 2. Adapter loading tests
# =============================================================================
echo ""
echo "=== Adapter Loading Tests ==="

# Load github adapter
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "github"
)
if [[ "$loaded" == "github" ]]; then
    log_pass "adapter_load 'github' returns 'github'"
else
    log_fail "adapter_load github" "got '$loaded'"
fi

# Load gitlab adapter
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "gitlab"
)
if [[ "$loaded" == "gitlab" ]]; then
    log_pass "adapter_load 'gitlab' returns 'gitlab'"
else
    log_fail "adapter_load gitlab" "got '$loaded'"
fi

# Load bitbucket adapter
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "bitbucket"
)
if [[ "$loaded" == "bitbucket" ]]; then
    log_pass "adapter_load 'bitbucket' returns 'bitbucket'"
else
    log_fail "adapter_load bitbucket" "got '$loaded'"
fi

# Load generic adapter
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "generic"
)
if [[ "$loaded" == "generic" ]]; then
    log_pass "adapter_load 'generic' returns 'generic'"
else
    log_fail "adapter_load generic" "got '$loaded'"
fi

# Auto-detect load (no arg, no env)
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load
)
if [[ "$loaded" == "generic" ]]; then
    log_pass "adapter_load (no args, no env) auto-detects generic"
else
    log_fail "adapter_load no args should auto-detect" "got '$loaded'"
fi

# Invalid provider falls back to generic
loaded=$(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "nonexistent"
)
if [[ "$loaded" == "generic" ]]; then
    log_pass "adapter_load 'nonexistent' falls back to 'generic'"
else
    log_fail "Unknown provider should fallback to generic" "got '$loaded'"
fi

# =============================================================================
# 3. Required functions exist after loading
# =============================================================================
echo ""
echo "=== Contract Verification Tests ==="

for provider in github gitlab bitbucket generic; do
    (
        unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
        source "$ADAPTER_BASE"
        adapter_load "$provider" >/dev/null

        missing=""
        for fn in adapter_detect adapter_run adapter_annotate adapter_comment adapter_exit; do
            if ! type "$fn" &>/dev/null; then
                missing="$missing $fn"
            fi
        done

        if [[ -z "$missing" ]]; then
            echo "PASS"
        else
            echo "FAIL:$missing"
        fi
    )
    result=$( (
        unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
        source "$ADAPTER_BASE"
        adapter_load "$provider" >/dev/null

        missing=""
        for fn in adapter_detect adapter_run adapter_annotate adapter_comment adapter_exit; do
            if ! type "$fn" &>/dev/null; then
                missing="$missing $fn"
            fi
        done

        if [[ -z "$missing" ]]; then
            echo "PASS"
        else
            echo "FAIL:$missing"
        fi
    ) )
    if [[ "$result" == "PASS" ]]; then
        log_pass "$provider adapter has all required functions"
    else
        log_fail "$provider adapter missing functions" "${result#FAIL:}"
    fi
done

# =============================================================================
# 4. Comment formatting tests
# =============================================================================
echo ""
echo "=== Comment Formatting Tests ==="

# Create mock report: clean (no violations)
cat > "$TEMP_DIR/clean-report.json" <<'JSON'
{
  "version": "2.6.0",
  "timestamp": "2025-01-01T00:00:00Z",
  "config": {
    "strictness": "strict",
    "stack": "fullstack"
  },
  "summary": {
    "files_scanned": 5,
    "violations": 0,
    "warnings": 0
  },
  "violations": []
}
JSON

# Create mock report: violations
cat > "$TEMP_DIR/violations-report.json" <<'JSON'
{
  "version": "2.6.0",
  "timestamp": "2025-01-01T00:00:00Z",
  "config": {
    "strictness": "strict",
    "stack": "fullstack"
  },
  "summary": {
    "files_scanned": 3,
    "violations": 2,
    "warnings": 0
  },
  "violations": [
    {"rule": "PHP001", "file": "src/Entity/User.php", "line": 1, "message": "Missing declare(strict_types=1)", "severity": "critical"},
    {"rule": "PHP002", "file": "src/Entity/User.php", "line": 5, "message": "Class should be final", "severity": "critical"}
  ]
}
JSON

# Create mock report: warnings only
cat > "$TEMP_DIR/warnings-report.json" <<'JSON'
{
  "version": "2.6.0",
  "timestamp": "2025-01-01T00:00:00Z",
  "config": {
    "strictness": "strict",
    "stack": "fullstack"
  },
  "summary": {
    "files_scanned": 2,
    "violations": 0,
    "warnings": 1
  },
  "violations": [
    {"rule": "WARN-PHP001", "file": "src/Service/Foo.php", "line": 10, "message": "Method with 4+ parameters", "severity": "warning"}
  ]
}
JSON

source "$ADAPTER_BASE"

# Clean report: status = Passed
comment=$(adapter_format_comment "$TEMP_DIR/clean-report.json")
if echo "$comment" | grep -q "Craftsman Quality Gate -- Passed"; then
    log_pass "Clean report: title shows 'Passed'"
else
    log_fail "Clean report title" "expected 'Passed' in title"
fi

# Clean report: metrics table present
if echo "$comment" | grep -q "Files scanned | 5"; then
    log_pass "Clean report: metrics table has correct files_scanned"
else
    log_fail "Clean report metrics" "expected 'Files scanned | 5'"
fi

# Clean report: no Issues section
if ! echo "$comment" | grep -q "### Issues"; then
    log_pass "Clean report: no Issues section when clean"
else
    log_fail "Clean report" "should not have Issues section"
fi

# Clean report: footer present
if echo "$comment" | grep -q "craftsman v2.1.0"; then
    log_pass "Clean report: footer has version"
else
    log_fail "Clean report footer" "expected 'craftsman v2.1.0'"
fi

# Violations report: status = Failed
comment=$(adapter_format_comment "$TEMP_DIR/violations-report.json")
if echo "$comment" | grep -q "Craftsman Quality Gate -- Failed"; then
    log_pass "Violations report: title shows 'Failed'"
else
    log_fail "Violations report title" "expected 'Failed'"
fi

# Violations report: has Issues section
if echo "$comment" | grep -q "### Issues"; then
    log_pass "Violations report: has Issues section"
else
    log_fail "Violations report" "should have Issues section"
fi

# Violations report: issues table has rules
if echo "$comment" | grep -q "PHP001" && echo "$comment" | grep -q "PHP002"; then
    log_pass "Violations report: issues table lists PHP001 and PHP002"
else
    log_fail "Violations report issues" "expected PHP001 and PHP002 in table"
fi

# Violations report: metrics are correct
if echo "$comment" | grep -q "Violations | 2"; then
    log_pass "Violations report: metrics table shows 2 violations"
else
    log_fail "Violations report metrics" "expected 'Violations | 2'"
fi

# Warnings report: status = Passed with warnings
comment=$(adapter_format_comment "$TEMP_DIR/warnings-report.json")
if echo "$comment" | grep -q "Craftsman Quality Gate -- Passed with warnings"; then
    log_pass "Warnings report: title shows 'Passed with warnings'"
else
    log_fail "Warnings report title" "expected 'Passed with warnings'"
fi

# Warnings report: config in metrics
if echo "$comment" | grep -q "strict / fullstack"; then
    log_pass "Warnings report: config shows 'strict / fullstack'"
else
    log_fail "Warnings report config" "expected 'strict / fullstack'"
fi

# Formatting: docs link present
if echo "$comment" | grep -q "https://github.com/BULDEE/ai-craftsman-superpowers"; then
    log_pass "Comment has docs link"
else
    log_fail "Comment docs link" "expected docs link in footer"
fi

# =============================================================================
# 5. Exit code logic tests
# =============================================================================
echo ""
echo "=== Exit Code Logic Tests ==="

# Clean -> 0
adapter_compute_exit "$TEMP_DIR/clean-report.json"
ec=$?
if [[ "$ec" -eq 0 ]]; then
    log_pass "Clean report -> exit 0"
else
    log_fail "Clean report exit code" "expected 0, got $ec"
fi

# Violations -> 2
adapter_compute_exit "$TEMP_DIR/violations-report.json"
ec=$?
if [[ "$ec" -eq 2 ]]; then
    log_pass "Violations report -> exit 2"
else
    log_fail "Violations report exit code" "expected 2, got $ec"
fi

# Warnings only -> 1
adapter_compute_exit "$TEMP_DIR/warnings-report.json"
ec=$?
if [[ "$ec" -eq 1 ]]; then
    log_pass "Warnings-only report -> exit 1"
else
    log_fail "Warnings-only report exit code" "expected 1, got $ec"
fi

# =============================================================================
# 6. GitHub adapter annotation format
# =============================================================================
echo ""
echo "=== GitHub Adapter Annotation Tests ==="

(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "github" >/dev/null
    output=$(adapter_annotate "$TEMP_DIR/violations-report.json")
    echo "$output" > "$TEMP_DIR/gh-annotations.txt"
)

gh_annotations=$(cat "$TEMP_DIR/gh-annotations.txt")

if echo "$gh_annotations" | grep -q "::error file="; then
    log_pass "GitHub adapter emits ::error annotations"
else
    log_fail "GitHub annotations" "expected ::error annotations"
fi

if echo "$gh_annotations" | grep -q "PHP001"; then
    log_pass "GitHub annotations include rule ID"
else
    log_fail "GitHub annotations rule ID" "expected PHP001 in annotation"
fi

# =============================================================================
# 7. GitLab adapter codequality report
# =============================================================================
echo ""
echo "=== GitLab Adapter Codequality Tests ==="

(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "gitlab" >/dev/null
    adapter_annotate "$TEMP_DIR/violations-report.json" "$TEMP_DIR/gl-codequality.json" >/dev/null
)

if [[ -f "$TEMP_DIR/gl-codequality.json" ]]; then
    if python3 -c "import json; d=json.load(open('$TEMP_DIR/gl-codequality.json')); assert len(d) == 2" 2>/dev/null; then
        log_pass "GitLab codequality JSON has 2 issues"
    else
        log_fail "GitLab codequality" "expected 2 issues in JSON"
    fi

    if python3 -c "import json; d=json.load(open('$TEMP_DIR/gl-codequality.json')); assert d[0]['check_name'] == 'PHP001'" 2>/dev/null; then
        log_pass "GitLab codequality issue has correct check_name"
    else
        log_fail "GitLab codequality check_name" "expected PHP001"
    fi

    if python3 -c "import json; d=json.load(open('$TEMP_DIR/gl-codequality.json')); assert 'fingerprint' in d[0]" 2>/dev/null; then
        log_pass "GitLab codequality issue has fingerprint"
    else
        log_fail "GitLab codequality fingerprint" "expected fingerprint field"
    fi
else
    log_fail "GitLab codequality file" "gl-codequality.json not created"
fi

# =============================================================================
# 8. Generic adapter writes markdown file
# =============================================================================
echo ""
echo "=== Generic Adapter Tests ==="

(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "generic" >/dev/null
    adapter_comment "$TEMP_DIR/violations-report.json" "$TEMP_DIR/generic-comment.md" >/dev/null
)

if [[ -f "$TEMP_DIR/generic-comment.md" ]]; then
    log_pass "Generic adapter writes craftsman-comment.md"

    if grep -q "Craftsman Quality Gate" "$TEMP_DIR/generic-comment.md"; then
        log_pass "Generic comment file contains Quality Gate title"
    else
        log_fail "Generic comment content" "expected Quality Gate title"
    fi
else
    log_fail "Generic adapter file" "craftsman-comment.md not created"
fi

# Generic adapter annotate outputs plain text
(
    unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
    source "$ADAPTER_BASE"
    adapter_load "generic" >/dev/null
    adapter_annotate "$TEMP_DIR/violations-report.json" > "$TEMP_DIR/generic-annotations.txt"
)

generic_ann=$(cat "$TEMP_DIR/generic-annotations.txt")

if echo "$generic_ann" | grep -q "CRITICAL:"; then
    log_pass "Generic adapter annotate outputs CRITICAL: prefix"
else
    log_fail "Generic annotate format" "expected 'CRITICAL:' prefix"
fi

if echo "$generic_ann" | grep -q "PHP001"; then
    log_pass "Generic annotate includes rule ID"
else
    log_fail "Generic annotate rule" "expected PHP001"
fi

# =============================================================================
# 9. Comment format missing file
# =============================================================================
echo ""
echo "=== Edge Case Tests ==="

error_output=$(adapter_format_comment "/nonexistent/file.json" 2>&1)
ec=$?
if [[ "$ec" -ne 0 ]]; then
    log_pass "adapter_format_comment with missing file returns error"
else
    log_fail "Missing file should error" "got exit $ec"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==================================="
echo -e " ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e " ${RED}Failed:${NC} $TESTS_FAILED"
echo "==================================="

[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
