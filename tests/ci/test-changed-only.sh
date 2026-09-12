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

# --- The silent greens two reviews found, each one a violation IN the diff that
# reported "Nothing to validate", exit 0 ---------------------------------------
#
# Every case below is the exact failure this file's header says the feature
# must not become, and the first version of this file went red on none of them:
# its empty-scan JSON was checked by parsing it, never by handing it to the
# adapter that decides the exit code.
git checkout -q feature

# The spelling tab-completion produces, an absolute path, a path through `..`,
# and a run from inside the tree: git prints root-relative paths and the scope
# compare was a literal string prefix.
for spelling in "./src" "$REPO/src" "src/../src" "./src/Domain/Bad.php"; do
    spelled_code=0
    bash "$CI" --changed-only --base main "$spelling" >/dev/null 2>&1 || spelled_code=$?
    if [[ "$spelled_code" -eq 2 ]]; then
        log_pass "scope spelled '$spelling' still sees the violation (exit 2)"
    else
        log_fail "scope spelled '$spelling' still sees the violation" \
            "exit $spelled_code: a path spelling turned the gate green"
    fi
done

sub_code=0
( cd "$REPO/src" && bash "$CI" --changed-only --base main Domain >/dev/null 2>&1 ) || sub_code=$?
if [[ "$sub_code" -eq 2 ]]; then
    log_pass "run from a subdirectory, the violation is still seen (exit 2)"
else
    log_fail "run from a subdirectory, the violation is still seen" \
        "exit $sub_code: the monorepo layout turned the gate green"
fi

# A file name with an accent. git quotes it (core.quotePath), the quoted string
# is not a file, and the violation in it passed.
git checkout -qb accent feature
printf '<?php\nclass Societe { public function setN($v) { $this->n = $v; } }\n' > "src/Domain/Société.php"
_commit "accented name"
accent_code=0
accent_out=$(bash "$CI" --changed-only --base main src 2>&1) || accent_code=$?
if [[ "$accent_code" -eq 2 ]] && printf '%s' "$accent_out" | grep -q "Société"; then
    log_pass "a file whose name has an accent is in the diff and still fails"
else
    log_fail "a file whose name has an accent is in the diff and still fails" \
        "exit $accent_code, name reported: $(printf '%s' "$accent_out" | grep -c 'Société')"
fi
git checkout -q feature

# --- The false reds every shipped template hit -----------------------------------
#
# A pull request that changes README.md alone went red as "no source file was
# found", through all four adapters, because the changed set was non-empty and
# no file in it had an extension a pack claims. And through the `ci`
# subcommand, an empty diff went red because adapter_compute_exit read
# files_scanned=0 and never the scope block this PR claimed it would read.
git checkout -qb docs main
printf '\n# more docs\n' >> README.md 2>/dev/null || printf '# docs\n' > README.md
_commit "docs only"
docs_code=0
docs_out=$(bash "$CI" --changed-only --base main 2>&1) || docs_code=$?
if [[ "$docs_code" -eq 0 ]] && printf '%s' "$docs_out" | grep -q "Nothing to validate"; then
    log_pass "a docs-only pull request is nothing to validate, exit 0"
else
    log_fail "a docs-only pull request is nothing to validate" "exit $docs_code: $(printf '%s' "$docs_out" | tail -1)"
fi

ci_empty_code=0
( GITHUB_BASE_REF=main bash "$CI" ci --provider generic --changed-only >/dev/null 2>&1 ) || ci_empty_code=$?
if [[ "$ci_empty_code" -eq 0 ]]; then
    log_pass "through the ci subcommand, an empty diff is exit 0 (the adapter reads the scope)"
else
    log_fail "through the ci subcommand, an empty diff is exit 0" \
        "exit $ci_empty_code: the shipped templates fail every docs-only pull request"
fi
rm -f craftsman-comment.md
git checkout -q feature

# A non-source file UNDER a source root is the case the scope alone does not
# cover: `src/Domain/services.yaml` is inside src/, no pack claims .yaml, and
# without the extension filter it entered the scan as a file that discovered
# nothing, which the misconfiguration guard reads as a failed run. Every
# Symfony pull request that touches only src/Resources/config/*.yaml went red.
git checkout -qb config-only main
mkdir -p src/Resources/config
printf 'services:\n  _defaults:\n    autowire: true\n' > src/Resources/config/services.yaml
_commit "config only, under src"
config_code=0
config_out=$(bash "$CI" --changed-only --base main src 2>&1) || config_code=$?
if [[ "$config_code" -eq 0 ]] && printf '%s' "$config_out" | grep -q "Nothing to validate"; then
    log_pass "a config-only change under src/ is nothing to validate, exit 0"
else
    log_fail "a config-only change under src/ is nothing to validate" \
        "exit $config_code: $(printf '%s' "$config_out" | tail -1)"
fi
git checkout -q feature

# --- The filter must not WIDEN what the full scan validates --------------------
#
# With no path given the full scan walks the default roots and prunes vendor/,
# dist/, build/, var/, node_modules/. The first version validated every changed
# file in the repository instead, so a changed vendor/ file failed the pull
# request and a tests/ file was validated on pull requests and never on main.
git checkout -qb widen feature
mkdir -p vendor/acme dist tests/Unit
printf '<?php\nclass V { public function setA($a) { $this->a = $a; } }\n' > vendor/acme/V.php
cp vendor/acme/V.php dist/D.php
printf '<?php\nclass T { public function setB($b) { $this->b = $b; } }\n' > tests/Unit/T.php
_commit "files outside the default roots"
widen_out=$(bash "$CI" --changed-only --base main 2>&1)
for outside in vendor/acme/V.php dist/D.php tests/Unit/T.php; do
    if printf '%s' "$widen_out" | grep -q "$outside"; then
        log_fail "$outside stays outside the scope the full scan uses" "it was validated on the pull request only"
    else
        log_pass "$outside stays outside the scope the full scan uses"
    fi
done
git checkout -q feature

# --- A base named by the provider that does not resolve is an error ------------
#
# GITHUB_BASE_REF=develop with origin/develop unfetched slid to a stale
# origin/main and reported other people's commits as this pull request's.
named_code=0
named_out=$(env -u CRAFTSMAN_BASE_REF GITHUB_BASE_REF=develop bash "$CI" --changed-only src 2>&1) || named_code=$?
if [[ "$named_code" -eq 2 ]] && printf '%s' "$named_out" | grep -q "named by the environment"; then
    log_pass "a provider-named base that does not resolve is an error, not a stale fallback"
else
    log_fail "a provider-named base that does not resolve is an error" "exit $named_code"
fi

guessed=$(env -u CRAFTSMAN_BASE_REF -u GITHUB_BASE_REF bash "$CI" --changed-only --format json src 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["scope"]["base_source"])' 2>/dev/null)
if [[ "$guessed" == "guess" ]]; then
    log_pass "a base nobody named is reported as a guess in the JSON scope"
else
    log_fail "a base nobody named is reported as a guess" "base_source='$guessed'"
fi

# --- An option missing its value must not hang a runner for six hours -------------
#
# Bounded with perl's alarm, not `timeout`: coreutils timeout does not exist
# on the macOS runner (exit 127), and the first version of this block reported
# "it hung" for a command that had exited 2 on the spot.
_bounded() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}
for option in --base --config --format; do
    hang_code=0
    ( _bounded 5 bash "$CI" --changed-only "$option" >/dev/null 2>&1 ) || hang_code=$?
    if [[ "$hang_code" -eq 2 ]]; then
        log_pass "$option with no value exits 2 at once"
    else
        log_fail "$option with no value exits 2 at once" "exit $hang_code (142 is the alarm: it hung)"
    fi
done

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
