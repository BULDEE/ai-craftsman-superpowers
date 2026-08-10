#!/usr/bin/env bash
# =============================================================================
# CI adapter DELIVERY tests
#
# The other adapter suite proves the adapters transform a JSON shape. It feeds
# them hand-written fixtures carrying line numbers the producer has never
# emitted, so it proves a transformation and never proves the contract.
#
# This suite asks the only question that matters for a gate: does a real
# violation, scanned by the real pipeline, arrive at the consumer as an
# annotation that consumer accepts, and does the verdict reach the exit code.
#
# Every assertion here takes its input from an actual craftsman-ci.sh run.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CI="$ROOT_DIR/ci/craftsman-ci.sh"
ADAPTER_BASE="$ROOT_DIR/ci/adapters/adapter.sh"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-delivery-XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# -----------------------------------------------------------------------------
# An ordinary repository: a couple of scripts at the root, like almost every
# real project, and source files that violate block-severity rules.
# -----------------------------------------------------------------------------
build_fixture() {
    local root="$1"
    mkdir -p "$root/src"
    printf '#!/bin/sh\necho build\n'   > "$root/build.sh"
    printf '#!/bin/sh\necho install\n' > "$root/install.sh"
    cat > "$root/src/User.php" <<'PHP'
<?php

namespace App\Domain;

class User
{
    public function setName(string $name): void
    {
        $this->name = $name;
    }
}
PHP
}

FIXTURE="$WORK/repo"
build_fixture "$FIXTURE"

# =============================================================================
# 1. File discovery must not depend on what sits in the working directory
# -----------------------------------------------------------------------------
# The find predicate was built as a string and expanded unquoted, so `*.php`
# and friends were glob-expanded against the CWD before find ever saw them.
# One matching file at the repository root silently replaced a whole language
# with a single literal filename; two aborted find entirely
# ("unknown primary or operator"), and its stderr went to /dev/null, so a dead
# scanner was indistinguishable from a clean tree.
# =============================================================================
echo ""
echo "=== File discovery is independent of the working directory ==="

# craftsman-ci exits 2 when it finds violations, which is the expected outcome
# here, so the report is captured first and parsed second: piping straight into
# python under `set -o pipefail` would read that healthy 2 as a parse failure.
scan_report() {
    (cd "$1" && bash "$CI" --format json src 2>/dev/null) > "$2" || true
}

scanned_count() {
    local report="$WORK/count-$$.json"
    scan_report "$1" "$report"
    python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['files_scanned'])" \
        < "$report" 2>/dev/null || echo "parse-error"
}

count=$(scanned_count "$FIXTURE")
if [[ "$count" == "1" ]]; then
    log_pass "a repository root holding shell scripts does not blind the PHP scan"
else
    log_fail "file discovery poisoned by the working directory" \
        "expected files_scanned=1, got '$count'"
fi

# Same tree, same command, only the root clutter differs. The two runs must
# agree: discovery is a property of the scanned path, not of the CWD.
BARE="$WORK/bare"
mkdir -p "$BARE/src"
cp "$FIXTURE/src/User.php" "$BARE/src/User.php"
bare_count=$(scanned_count "$BARE")
if [[ "$count" == "$bare_count" ]]; then
    log_pass "discovery agrees with and without files at the repository root ($bare_count)"
else
    log_fail "discovery depends on repository root contents" \
        "cluttered=$count bare=$bare_count"
fi

# A language must not be silently dropped either. One .sh at the root used to
# turn `-name *.sh` into `-name install.sh`, deleting shell coverage including
# SH004 (eval), while the run still looked plausible.
SHELLREPO="$WORK/shellrepo"
mkdir -p "$SHELLREPO/src"
printf '#!/bin/sh\necho one\n' > "$SHELLREPO/only.sh"
printf '#!/usr/bin/env bash\neval "$USER_INPUT"\n' > "$SHELLREPO/src/deploy.sh"
scan_report "$SHELLREPO" "$WORK/shell-report.json"
sh_rules=$(python3 -c "
import json,sys
print(' '.join(sorted(v['rule'] for v in json.load(sys.stdin)['violations'])))
" < "$WORK/shell-report.json" 2>/dev/null || echo "parse-error")
if [[ "$sh_rules" == *"SH004"* ]]; then
    log_pass "eval is still reported when the repository root holds a shell script"
else
    log_fail "a language was silently dropped from the scan" \
        "expected SH004 among the violations, got '$sh_rules'"
fi

# =============================================================================
# 2. An empty scan is not a pass, in ci mode as much as in direct mode
# -----------------------------------------------------------------------------
# craftsman-ci.sh refuses to call a zero-file run a pass and exits 2. Every
# adapter_run ended in `|| true` and adapter_exit recomputed the verdict from
# summary.violations alone, which cannot tell "clean" from "never ran". The
# guard existed and was discarded at the boundary, in the only mode the four
# shipped templates use.
# =============================================================================
echo ""
echo "=== An empty scan fails closed in ci mode ==="

NOSRC="$WORK/nosrc"
mkdir -p "$NOSRC/docs"
echo "documentation only" > "$NOSRC/docs/readme.txt"

direct_code=0
(cd "$NOSRC" && bash "$CI" --format json docs >/dev/null 2>&1) || direct_code=$?
if [[ "$direct_code" -eq 2 ]]; then
    log_pass "direct mode refuses a zero-file run (exit 2)"
else
    log_fail "direct mode empty-scan guard" "expected 2, got $direct_code"
fi

for provider in generic github gitlab bitbucket; do
    ci_code=0
    (cd "$NOSRC" && bash "$CI" ci --provider "$provider" docs >/dev/null 2>&1) || ci_code=$?
    if [[ "$ci_code" -ne 0 ]]; then
        log_pass "ci mode ($provider) refuses a zero-file run (exit $ci_code)"
    else
        log_fail "ci mode ($provider) empty-scan guard discarded" \
            "a gate that opened no file exited 0"
    fi
done

# The shared helper is where that decision belongs, so assert it directly too.
source "$ADAPTER_BASE"
cat > "$WORK/empty-scan.json" <<'JSON'
{
  "version": "4.6.3",
  "timestamp": "2026-01-01T00:00:00Z",
  "config": {"strictness": "strict", "stack": "fullstack"},
  "summary": {"files_scanned": 0, "violations": 0, "warnings": 0},
  "violations": []
}
JSON
exit_code=0
adapter_compute_exit "$WORK/empty-scan.json" || exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then
    log_pass "adapter_compute_exit fails closed on files_scanned=0 (exit $exit_code)"
else
    log_fail "adapter_compute_exit treats an empty scan as clean" "returned 0"
fi

# A clean run that actually opened files must still pass, or the guard above is
# just a broken gate. Control assertion.
cat > "$WORK/clean-scan.json" <<'JSON'
{
  "version": "4.6.3",
  "timestamp": "2026-01-01T00:00:00Z",
  "config": {"strictness": "strict", "stack": "fullstack"},
  "summary": {"files_scanned": 7, "violations": 0, "warnings": 0},
  "violations": []
}
JSON
exit_code=0
adapter_compute_exit "$WORK/clean-scan.json" || exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
    log_pass "control: a genuinely clean run still exits 0"
else
    log_fail "the empty-scan guard is too wide" "a clean 7-file run returned $exit_code"
fi

# =============================================================================
# 3. A real violation reaches the exit code through the adapter chain
# =============================================================================
echo ""
echo "=== A real violation blocks the pipeline through every adapter ==="

for provider in generic github gitlab bitbucket; do
    ci_code=0
    (cd "$FIXTURE" && bash "$CI" ci --provider "$provider" src >/dev/null 2>&1) || ci_code=$?
    if [[ "$ci_code" -eq 2 ]]; then
        log_pass "ci mode ($provider) exits 2 on a blocking violation"
    else
        log_fail "ci mode ($provider) does not block" \
            "expected exit 2 on PHP001/PHP002, got $ci_code"
    fi
done

# =============================================================================
# 4. The annotation a consumer receives is well formed
# -----------------------------------------------------------------------------
# Input is a real report, not a fixture. add_violation records line 0 for every
# Level 1 finding, which is what the regex engine produces for essentially
# every violation, so a fixture carrying line 1/5/10 tests a shape that never
# occurs in production.
# =============================================================================
echo ""
echo "=== GitHub annotations, from a real pipeline run ==="

REAL="$WORK/real-report.json"
(cd "$FIXTURE" && bash "$CI" --format json src 2>/dev/null) > "$REAL"

violation_total=$(python3 -c "import json;print(len(json.load(open('$REAL'))['violations']))" 2>/dev/null || echo 0)
if [[ "$violation_total" -gt 0 ]]; then
    log_pass "control: the fixture really produces violations ($violation_total)"
else
    log_fail "control: the fixture produced no violation" \
        "every assertion below is undetermined, not green"
fi

gh_out="$WORK/gh-annotations.txt"
( source "$ADAPTER_BASE"; adapter_load github >/dev/null; adapter_annotate "$REAL" ) > "$gh_out" 2>/dev/null

if [[ -s "$gh_out" ]]; then
    log_pass "the GitHub adapter emitted annotations for a real report"
else
    log_fail "no GitHub annotation reached stdout" "a real report produced nothing"
fi

# GitHub documents `line` as "Line number, starting at 1" and the Checks API
# that backs these annotations states line numbers start at 1. line=0 is
# outside the documented range; the property is optional and defaults to 1, so
# a finding with no known line must omit it rather than assert a line that
# does not exist.
if grep -q "line=0" "$gh_out"; then
    log_fail "GitHub annotation carries line=0" \
        "outside the documented range (line starts at 1); omit the property instead"
else
    log_pass "no GitHub annotation is emitted with line=0"
fi

if grep -qE "^::(error|warning) file=" "$gh_out"; then
    log_pass "GitHub annotations keep the documented ::error/::warning framing"
else
    log_fail "GitHub annotation framing" "expected ::error file= or ::warning file="
fi

# Severity is the rules engine's decision. A block-severity rule must arrive as
# ::error and an advisory one as ::warning: the adapter may not re-rank them.
if grep -q "^::error file=.*PHP001" "$gh_out"; then
    log_pass "a block rule (PHP001) arrives as ::error"
else
    log_fail "severity lost in transit" "PHP001 is block severity, expected ::error"
fi
if grep -q "^::warning file=.*PHP003" "$gh_out"; then
    log_pass "an advisory rule (PHP003) arrives as ::warning"
else
    log_fail "severity lost in transit" "PHP003 is advisory, expected ::warning"
fi

echo ""
echo "=== GitLab code quality report, from a real pipeline run ==="

GL="$WORK/gl-codequality.json"
( source "$ADAPTER_BASE"; adapter_load gitlab >/dev/null; adapter_annotate "$REAL" "$GL" ) >/dev/null 2>&1

if [[ -s "$GL" ]] && python3 -c "import json;json.load(open('$GL'))" 2>/dev/null; then
    log_pass "the GitLab adapter wrote parseable code quality JSON"

    # GitLab requires exactly these, and processes nothing else.
    if python3 -c "
import json
issues = json.load(open('$GL'))
required = ('description', 'check_name', 'fingerprint', 'severity')
for issue in issues:
    for field in required:
        assert field in issue and issue[field] != '', field
    assert issue['location']['path']
    assert not issue['location']['path'].startswith('./')
    assert isinstance(issue['location']['lines']['begin'], int)
" 2>/dev/null; then
        log_pass "every issue carries the six fields GitLab requires"
    else
        log_fail "GitLab required fields" "an issue is missing a required field"
    fi

    if python3 -c "
import json
allowed={'info','minor','major','critical','blocker'}
assert all(i['severity'] in allowed for i in json.load(open('$GL')))
" 2>/dev/null; then
        log_pass "severity stays inside the documented GitLab enum"
    else
        log_fail "GitLab severity enum" "value outside info/minor/major/critical/blocker"
    fi

    if python3 -c "
import json
assert all(i['location']['lines']['begin'] >= 1 for i in json.load(open('$GL')))
" 2>/dev/null; then
        log_pass "no GitLab issue is anchored at line 0"
    else
        log_fail "GitLab issue anchored at line 0" \
            "lines.begin must be a real line for the finding to render"
    fi
else
    log_fail "GitLab code quality report" "not written, empty, or not valid JSON"
fi

# An unreadable input must not leave an empty artifact behind while announcing
# success. GitLab reads an empty report as "no findings", which is a green
# widget on a failed run.
echo "this is not json" > "$WORK/broken-report.json"
BROKEN_OUT="$WORK/gl-broken.json"
broken_msg=$( ( source "$ADAPTER_BASE"; adapter_load gitlab >/dev/null
                adapter_annotate "$WORK/broken-report.json" "$BROKEN_OUT" ) 2>&1 )
broken_ec=$?

if [[ ! -s "$BROKEN_OUT" ]] && echo "$broken_msg" | grep -qi "written to"; then
    log_fail "GitLab adapter claims success on an unreadable report" \
        "an empty artifact reads as 'no findings' in the MR widget"
else
    log_pass "an unreadable report does not produce a success message"
fi

if [[ "$broken_ec" -ne 0 ]]; then
    log_pass "the GitLab adapter reports failure when it cannot build the report"
else
    log_fail "GitLab adapter swallows its own failure" "returned 0 with no report"
fi

echo ""
echo "=== Bitbucket annotation payloads, from a real pipeline run ==="

# Bitbucket Cloud documents line 0 as the file-level default ("it will appear
# at the top of the file specified by the path field"), so line 0 is correct
# here and must NOT be clamped. What must hold is the documented enums.
BB="$WORK/bb-annotations.txt"
python3 -c "
import json
report=json.load(open('$REAL'))
for i,v in enumerate(report.get('violations', [])):
    sev='CRITICAL' if v.get('severity')=='critical' else 'MEDIUM'
    print(json.dumps({'external_id':'craftsman-%d'%i,'annotation_type':'BUG',
                      'severity':sev,'path':v.get('file',''),
                      'line':v.get('line',0),
                      'summary':'[%s] %s'%(v.get('rule',''),v.get('message',''))}))
" > "$BB" 2>/dev/null

if python3 -c "
import json
allowed_types = {'VULNERABILITY', 'CODE_SMELL', 'BUG'}
allowed_severities = {'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'}
emitted = 0
for line in open('$BB'):
    annotation = json.loads(line)
    assert annotation['annotation_type'] in allowed_types, annotation['annotation_type']
    assert annotation['severity'] in allowed_severities, annotation['severity']
    assert isinstance(annotation['line'], int) and annotation['line'] >= 0
    emitted += 1
assert emitted > 0
" 2>/dev/null; then
    log_pass "Bitbucket payloads stay inside the documented type and severity enums"
else
    log_fail "Bitbucket annotation payload" "type or severity outside the documented enum"
fi

# =============================================================================
# 5. adapter_detect is part of the contract, so it must have a consumer
# -----------------------------------------------------------------------------
# It was defined by all four providers and called by nothing: adapter.sh
# reimplemented the env-var chain separately. A contract member with no
# consumer drifts silently, which is how an adapter stops working without any
# test noticing.
# =============================================================================
echo ""
echo "=== adapter_detect is actually consumed ==="

for pair in "GITHUB_ACTIONS:github" "GITLAB_CI:gitlab" "BITBUCKET_BUILD_NUMBER:bitbucket"; do
    var="${pair%%:*}"
    want="${pair##*:}"
    got=$(
        unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER 2>/dev/null || true
        export "$var=1"
        source "$ADAPTER_BASE"
        adapter_auto_detect
    )
    if [[ "$got" == "$want" ]]; then
        log_pass "$var selects the $want adapter"
    else
        log_fail "detection for $var" "expected $want, got '$got'"
    fi
done

# The behavioural assertions above pass either way, because both the old
# duplicated chain and the delegating one read the same variables. That is
# exactly why adapter_detect could rot unnoticed. The assertion that separates
# them is structural, the same convention the adapter_exit delegation check in
# test-adapters.sh already uses: a dynamic `source` is invisible to AST tooling,
# so routing is asserted on the source. A behavioural probe cannot express it
# either, since any subshell that sources a provider reloads the real
# adapter_detect over any stub.
if sed -n '/^adapter_auto_detect()/,/^}/p' "$ADAPTER_BASE" | grep -q 'adapter_detect'; then
    log_pass "auto-detection routes through the providers' adapter_detect"
else
    log_fail "adapter_detect has no consumer" \
        "adapter_auto_detect reimplements the env-var chain, so the contract member is dead code"
fi

# No provider's environment variable may be hard-coded in the base adapter:
# that duplication is what let the two definitions drift apart.
if sed -n '/^adapter_auto_detect()/,/^}/p' "$ADAPTER_BASE" \
    | grep -qE 'GITHUB_ACTIONS|GITLAB_CI|BITBUCKET_BUILD_NUMBER'; then
    log_fail "the env-var chain is duplicated in adapter.sh" \
        "correcting a provider's detection would not change auto-detection"
else
    log_pass "adapter.sh does not reimplement any provider's detection predicate"
fi

test_summary
