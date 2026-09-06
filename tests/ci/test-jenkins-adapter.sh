#!/usr/bin/env bash
# =============================================================================
# The Jenkins adapter turns the rules engine's verdict into something Jenkins
# can attach to a file and a line.
#
# The report is parsed with a real XML parser rather than grepped. A message
# carrying `<`, `&` or a quote is the ordinary case here, not the exotic one:
# rule messages quote code. A grep-based assertion passes on a document no
# parser would accept, and Warnings NG would then read the build as having no
# findings rather than as having a broken report.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-jenkins.XXXXXX")"
PREV_PWD="$PWD"
cleanup() { cd "$PREV_PWD" || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "=== Jenkins adapter ==="

RENDER="$ROOT_DIR/ci/adapters/checkstyle_report.py"

# --- Detection ----------------------------------------------------------------

detect_with() {
    env -i PATH="$PATH" HOME="$HOME" "$@" bash -c \
        "cd '$ROOT_DIR' && source ci/adapters/adapter.sh && adapter_auto_detect" 2>/dev/null
}

result="$(detect_with JENKINS_URL=https://ci.example.com)"
if [[ "$result" == "jenkins" ]]; then
    log_pass "JENKINS_URL selects the jenkins adapter"
else
    log_fail "JENKINS_URL selects the jenkins adapter" "got '$result'"
fi

# A Jenkins build of a repository hosted on GitHub exports both, and the forge
# adapter wins because it can post a comment where jenkins can only write one.
result="$(detect_with JENKINS_URL=https://ci.example.com GITHUB_ACTIONS=true)"
if [[ "$result" == "github" ]]; then
    log_pass "a forge adapter still outranks jenkins when both are present"
else
    log_fail "a forge adapter still outranks jenkins when both are present" "got '$result'"
fi

result="$(detect_with)"
if [[ "$result" == "generic" ]]; then
    log_pass "no CI environment still falls back to generic"
else
    log_fail "no CI environment still falls back to generic" "got '$result'"
fi

# --- The report is well-formed XML, and says what the engine said -------------

cat > "$WORK/report.json" <<'JSON'
{
  "version": "4.9.0",
  "summary": {"files_scanned": 3, "violations": 2, "warnings": 1},
  "violations": [
    {"rule": "LAYER001", "file": "./src/Domain/Order.php", "line": 12,
     "message": "Domain imports Infrastructure <App\\Infra> & \"Doctrine\"",
     "severity": "critical"},
    {"rule": "TS002", "file": "src/app/store.ts", "line": 0,
     "message": "prefer readonly", "severity": "warning"},
    {"rule": "XX001", "file": "src/app/store.ts", "line": 4,
     "message": "a severity nobody declared", "severity": "unheard-of"}
  ]
}
JSON

xml="$WORK/out.xml"
if python3 "$RENDER" < "$WORK/report.json" > "$xml" 2>"$WORK/render.err"; then
    log_pass "the renderer exits 0 on a valid report"
else
    log_fail "the renderer exits 0 on a valid report" "$(cat "$WORK/render.err")"
fi

parsed="$(python3 - "$xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
root = tree.getroot()
print("root:%s" % root.tag)
for file_node in root.findall("file"):
    for error in file_node.findall("error"):
        print("%s|%s|%s|%s|%s" % (
            file_node.get("name"), error.get("line"), error.get("severity"),
            error.get("source"), error.get("message")))
PY
)" || parsed="PARSE FAILED"

if [[ "$parsed" == "PARSE FAILED" ]]; then
    log_fail "the report is well-formed XML" "a parser refused it"
else
    log_pass "the report is well-formed XML"
fi

assert_contains "the root element is checkstyle" "$parsed" "root:checkstyle"

# The engine already resolved severity per file. Translating it is all this
# does; deciding it again would put the pipeline and the hooks at odds.
assert_contains "a critical violation becomes a checkstyle error" \
    "$parsed" "src/Domain/Order.php|12|error|LAYER001|"
assert_contains "a warning stays a warning" \
    "$parsed" "src/app/store.ts|1|warning|TS002|"

# A finding nobody can see is worse than one ranked too high.
assert_contains "an unknown severity is reported rather than dropped" \
    "$parsed" "src/app/store.ts|4|error|XX001|"

# './' is what the walk emits whenever the scanned path is '.', and Jenkins
# cannot resolve a path in that shape.
assert_not_contains "the ./ prefix is stripped" "$parsed" "./src/Domain"

# line 0 means "the whole file" to the engine and "no line" to Jenkins.
assert_not_contains "no finding is reported on line 0" "$parsed" "|0|"

# The message quotes code, so it carries the characters XML reserves. Compared
# as a string rather than grepped: the needle contains a backslash and a quote,
# and grep would read the first as an escape.
expected_message='Domain imports Infrastructure <App\Infra> & "Doctrine"'
actual_message="$(printf '%s\n' "$parsed" | grep '^src/Domain' | cut -d'|' -f5-)"
if [[ "$actual_message" == "$expected_message" ]]; then
    log_pass "the message survives escaping intact"
else
    log_fail "the message survives escaping intact" \
        "expected [$expected_message], got [$actual_message]"
fi

# --- The renderer refuses what it cannot read ---------------------------------

if printf 'not json at all' | python3 "$RENDER" > "$WORK/bad.xml" 2>/dev/null; then
    log_fail "the renderer refuses a report it cannot parse" "it exited 0"
else
    log_pass "the renderer refuses a report it cannot parse"
fi

# --- adapter_annotate leaves no half-written report ----------------------------

run_annotate() {
    ( cd "$WORK" && CI_DIR="$ROOT_DIR/ci" ADAPTER_DIR="$ROOT_DIR/ci/adapters" \
        bash -c "source '$ROOT_DIR/ci/adapters/adapter.sh'; source '$ROOT_DIR/ci/adapters/jenkins.sh'; adapter_annotate '$1' '$2'" )
}

run_annotate "$WORK/report.json" "$WORK/annotated.xml" >/dev/null 2>&1
if [[ -s "$WORK/annotated.xml" ]] && python3 -c "
import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" "$WORK/annotated.xml" 2>/dev/null; then
    log_pass "adapter_annotate writes a parseable report"
else
    log_fail "adapter_annotate writes a parseable report" "missing or malformed"
fi

# A redirect straight onto the target truncates it before python runs, so a
# parse failure would leave a zero-byte file, which Warnings NG reads as "no
# findings" rather than as a broken report.
printf 'still not json' > "$WORK/broken.json"
cp "$WORK/annotated.xml" "$WORK/previous.xml"
run_annotate "$WORK/broken.json" "$WORK/previous.xml" >/dev/null 2>&1
if [[ -s "$WORK/previous.xml" ]]; then
    log_pass "a failed render leaves the previous report untouched"
else
    log_fail "a failed render leaves the previous report untouched" "the file was truncated"
fi

# --- The Jenkinsfile template consumes what the adapter produces ---------------

TEMPLATE="$ROOT_DIR/ci/templates/Jenkinsfile.craftsman"
template_text="$(cat "$TEMPLATE")"

assert_contains "the template asks for the jenkins provider" \
    "$template_text" "provider jenkins"
assert_contains "the template records the checkstyle report" \
    "$template_text" "craftsman-checkstyle.xml"
assert_contains "the template uses the Warnings NG step" \
    "$template_text" "recordIssues"

# `error` aborts the stage, so recording the issues after the verdict loses
# them on exactly the builds that have some.
publish_line="$(grep -n 'recordIssues' "$TEMPLATE" | head -1 | cut -d: -f1)"
verdict_line="$(grep -n "error 'Craftsman quality gate failed" "$TEMPLATE" | head -1 | cut -d: -f1)"
if [[ -n "$publish_line" && -n "$verdict_line" && "$publish_line" -lt "$verdict_line" ]]; then
    log_pass "issues are recorded before the build is failed"
else
    log_fail "issues are recorded before the build is failed" \
        "recordIssues at ${publish_line:-none}, error at ${verdict_line:-none}"
fi

test_summary
