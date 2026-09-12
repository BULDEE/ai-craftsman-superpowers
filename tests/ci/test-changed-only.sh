#!/usr/bin/env bash
# =============================================================================
# --changed-only: a one-file pull request pays for one file.
#
# Measured on this repository, 83.2s for 197 files, 0.42s a file: a real
# Symfony application with 3119 PHP files under src/ pays roughly 22 minutes
# of CI per pull request and reports on the order of 3000 pre-existing findings
# on a one-file change. A job like that goes to allow_failure within the week,
# and the CI half of the gate becomes decorative.
#
# The filter is on the INPUT and never on the engine, and two things it must
# not become are asserted here before anything else: a violation introduced in
# a changed file must still fail the job, and a run that matches no file must
# say so rather than report a clean scan of nothing.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-changed-only.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
export HOME="$WORK/home"
mkdir -p "$CLAUDE_PLUGIN_DATA" "$HOME/.claude"

echo "=== craftsman-ci --changed-only ==="

CI="$ROOT_DIR/ci/craftsman-ci.sh"
REPO="$WORK/repo"
mkdir -p "$REPO/src/Domain" "$REPO/src/Other"
cd "$REPO" || exit 1
git init -q . && git checkout -qb main
_commit() { git add -A && git -c user.email=t@t -c user.name=t commit -qm "$1"; }

# The base: four clean files and one with pre-existing debt.
for name in A B C D; do
    printf '<?php\ndeclare(strict_types=1);\nfinal class %s {}\n' "$name" > "src/Other/$name.php"
done
printf '<?php\nclass Old { public function setX($v) { $this->x = $v; } }\n' > src/Domain/Old.php
_commit base

# The branch: one clean new file.
git checkout -qb feature
printf '<?php\ndeclare(strict_types=1);\nfinal class Fresh {}\n' > src/Domain/Fresh.php
_commit "one clean file"

_files_scanned() { grep -oE "in [0-9]+ file" | head -1 | grep -oE "[0-9]+"; }

full=$(bash "$CI" src 2>&1 | _files_scanned)
scoped=$(bash "$CI" --changed-only --base main src 2>&1 | _files_scanned)
if [[ "${full:-0}" -eq 6 && "${scoped:-0}" -eq 1 ]]; then
    log_pass "a one-file branch validates one file, not the repository ($scoped of $full)"
else
    log_fail "a one-file branch validates one file" "full=$full scoped=$scoped"
fi

# Pre-existing debt outside the diff is not reported. That is the point: the
# 3000 findings on a one-file pull request were all of this kind.
scoped_out=$(bash "$CI" --changed-only --base main src 2>&1)
if printf '%s' "$scoped_out" | grep -q "Old.php"; then
    log_fail "debt outside the diff stays out of the report" "Old.php was reported"
else
    log_pass "debt outside the diff stays out of the report"
fi

# --- The contra-test: a violation IN the diff still fails --------------------
printf '<?php\nclass Bad { public function setZ($v) { $this->z = $v; } }\n' > src/Domain/Bad.php
_commit "a bad file"
bad_code=0
bash "$CI" --changed-only --base main src >/dev/null 2>&1 || bad_code=$?
if [[ "$bad_code" -eq 2 ]]; then
    log_pass "a violation introduced in a changed file still fails the job (exit 2)"
else
    log_fail "a violation introduced in a changed file still fails the job" "exit $bad_code"
fi

# --- What "changed" includes ---------------------------------------------------
#
# Committed since the merge base, uncommitted, and untracked: a developer
# running this locally wants the file under their cursor, not only the ones
# they pushed.
# Counted, not grepped by name: a clean file prints nothing in text mode, so
# its presence in the scan is only visible in the file count.
before_edit=$(bash "$CI" --changed-only --base main src 2>&1 | _files_scanned)
printf '\n// touched\n' >> src/Other/A.php
with_edit=$(bash "$CI" --changed-only --base main src 2>&1 | _files_scanned)
git checkout -q src/Other/A.php
if [[ "${with_edit:-0}" -eq $(( ${before_edit:-0} + 1 )) ]]; then
    log_pass "an uncommitted edit is part of the diff ($before_edit then $with_edit files)"
else
    log_fail "an uncommitted edit is part of the diff" "$before_edit before, $with_edit with the edit"
fi

printf '<?php\nclass Untracked {}\n' > src/Other/Untracked.php
untracked=$(bash "$CI" --changed-only --base main src 2>&1)
rm -f src/Other/Untracked.php
if printf '%s' "$untracked" | grep -q "src/Other/Untracked.php"; then
    log_pass "an untracked new file is part of the diff"
else
    log_fail "an untracked new file is part of the diff" "Untracked.php not scanned"
fi

# A deleted file cannot be validated and must not break the run.
git rm -q src/Other/B.php && _commit "delete B"
deleted_code=0
bash "$CI" --changed-only --base main src >/dev/null 2>&1 || deleted_code=$?
if [[ "$deleted_code" -eq 2 ]]; then
    log_pass "a deleted file does not break the run (Bad.php still fails it)"
else
    log_fail "a deleted file does not break the run" "exit $deleted_code"
fi

# --- Scope narrows, never widens -----------------------------------------------
#
# `--changed-only src/Other` means "changed files under src/Other", and with
# the branch's changes all under src/Domain, that is nothing: said out loud,
# exit 0, and never a clean scan of the whole of src/Other.
none_out=$(bash "$CI" --changed-only --base main src/Other 2>&1)
none_code=$?
if [[ "$none_code" -eq 0 ]] && printf '%s' "$none_out" | grep -q "Nothing to validate"; then
    log_pass "no changed file in scope is said out loud, exit 0"
else
    log_fail "no changed file in scope is said out loud" "exit $none_code: $(printf '%s' "$none_out" | tail -1)"
fi
none_json=$(bash "$CI" --changed-only --base main --format json src/Other 2>&1)
if printf '%s' "$none_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["scope"]["changed_only"] and d["summary"]["files_scanned"] == 0 else 1)' 2>/dev/null; then
    log_pass "and the JSON report says so in a shape an adapter can read"
else
    log_fail "and the JSON report says so in a shape an adapter can read" "$(printf '%s' "$none_json" | head -c 200)"
fi

# --- A filter must fail closed --------------------------------------------------
#
# No base ref is an ERROR, never a full scan: a filter that silently widens to
# the whole repository puts the 22 minutes back on the day a runner's
# environment changes, and nobody notices until the job is on allow_failure.
typo_code=0
typo_out=$(bash "$CI" --changed-only --base nope src 2>&1) || typo_code=$?
if [[ "$typo_code" -eq 2 ]] && printf '%s' "$typo_out" | grep -q "not a ref"; then
    log_pass "an explicit base that does not exist is an error, not a fallback"
else
    log_fail "an explicit base that does not exist is an error" "exit $typo_code"
fi

NOGIT="$WORK/nogit"
mkdir -p "$NOGIT/src"
printf '<?php\nclass X {}\n' > "$NOGIT/src/X.php"
nogit_code=0
( cd "$NOGIT" && bash "$CI" --changed-only src >/dev/null 2>&1 ) || nogit_code=$?
if [[ "$nogit_code" -eq 2 ]]; then
    log_pass "outside a git repository the filter refuses rather than scanning everything"
else
    log_fail "outside a git repository the filter refuses" "exit $nogit_code"
fi

# --- The CI providers already know the base -------------------------------------
#
# Each names the target branch in its own variable; the resolver reads them so
# `craftsman-ci ci --changed-only` needs no --base on a runner.
git branch -q -f origin/main main 2>/dev/null || git update-ref refs/remotes/origin/main main
for pair in "GITHUB_BASE_REF main" "CI_MERGE_REQUEST_TARGET_BRANCH_NAME main" "BITBUCKET_PR_DESTINATION_BRANCH main" "CHANGE_TARGET main"; do
    variable="${pair%% *}"
    value="${pair##* }"
    resolved=$(env -u CRAFTSMAN_BASE_REF "$variable=$value" bash "$CI" --changed-only src 2>&1 | _files_scanned)
    if [[ "${resolved:-0}" -ge 1 ]]; then
        log_pass "$variable resolves the base on its provider's runner"
    else
        log_fail "$variable resolves the base on its provider's runner" "scanned '${resolved:-nothing}'"
    fi
done

# And the `ci` subcommand carries the flag through to the scan.
ci_out=$(GITHUB_BASE_REF=main bash "$CI" ci --provider generic --changed-only src 2>&1)
if printf '%s' "$ci_out" | grep -q "Fresh.php\|Bad.php"; then
    if printf '%s' "$ci_out" | grep -q "Old.php"; then
        log_fail "craftsman-ci ci forwards --changed-only" "Old.php reported: the whole tree was scanned"
    else
        log_pass "craftsman-ci ci forwards --changed-only to the scan"
    fi
else
    log_fail "craftsman-ci ci forwards --changed-only" "$(printf '%s' "$ci_out" | tail -2)"
fi

# --- The templates opt in on pull requests only ----------------------------------
for template in craftsman-quality-gate.yml .gitlab-ci.craftsman.yml bitbucket-pipelines.craftsman.yml Jenkinsfile.craftsman; do
    if grep -q -- "--changed-only" "$ROOT_DIR/ci/templates/$template"; then
        log_pass "$template uses --changed-only"
    else
        log_fail "$template uses --changed-only" "a fresh install would still pay for the whole repository"
    fi
done

cd "$ROOT_DIR" || true
test_summary
