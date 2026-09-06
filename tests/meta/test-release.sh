#!/usr/bin/env bash
# =============================================================================
# The release path, tested without pushing a tag.
#
# This suite sits in tests/meta/ rather than tests/ci/ on purpose: tests/ci/
# covers the product's CI front-end (craftsman-ci.sh, the provider adapters,
# severity parity), while this covers how the repository builds and signs
# itself. Two different axes, the same distinction CLAUDE.md already draws
# between ci/adapters/ and adapters/.
#
# The first two sections run the real scripts against a throwaway git
# repository, so they measure behaviour: a drifted version file, a marketplace
# tag on another commit, a rebuilt archive that must be byte-identical.
#
# The third section is an assumed lint over the workflow YAML. It is here
# because three of its properties cannot be observed without a runner and each
# of them fails silently: an unpinned action, permissions on the wrong job, and
# a `${{ }}` expression interpolated into a shell block. Every one of those
# checks is proved against a fixture that must fail it.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "=== Release guard, build and workflow ==="

# --- Fixture: a repository shaped like this one, at version 9.9.9 -----------

FIXTURE="$WORK/repo"

build_fixture() {
    rm -rf "$FIXTURE"
    mkdir -p "$FIXTURE/scripts" "$FIXTURE/.claude-plugin" "$FIXTURE/ci"
    cp "$ROOT_DIR/scripts/bump-version.sh" \
       "$ROOT_DIR/scripts/release-guard.sh" \
       "$ROOT_DIR/scripts/release-build.sh" "$FIXTURE/scripts/"
    printf '{"version": "9.9.9"}\n' > "$FIXTURE/.claude-plugin/plugin.json"
    printf '{"version": "9.9.9", "plugins": [{"version": "9.9.9"}]}\n' \
        > "$FIXTURE/.claude-plugin/marketplace.json"
    printf '#!/usr/bin/env bash\nVERSION="9.9.9"\n' > "$FIXTURE/ci/craftsman-ci.sh"
    printf '# Fixture\n\n**Current version:** 9.9.9\n' > "$FIXTURE/CLAUDE.md"
    git -C "$FIXTURE" init -q
    git -C "$FIXTURE" config user.email t@example.com
    git -C "$FIXTURE" config user.name Test
    git -C "$FIXTURE" add -A
    git -C "$FIXTURE" commit -qm "fixture at 9.9.9"
}

guard() {
    RELEASE_GUARD_TAG_WAIT=0 RELEASE_GUARD_FETCH=false \
        bash "$FIXTURE/scripts/release-guard.sh" "$@" 2>&1
}

# --- 1. release-guard.sh: what it refuses -----------------------------------

build_fixture
git -C "$FIXTURE" tag v9.9.9
git -C "$FIXTURE" tag craftsman--v9.9.9

out="$(guard v9.9.9)"; rc=$?
assert_exit_code "guard accepts a consistent release" 0 "$rc"

# A ref name may legally carry quotes, semicolons and `$`. An unanchored glob
# accepts all of them, and whatever follows lands in a shell block on a runner
# that holds the signing identity.
for bad in 'v9.9.9; rm -rf /' 'v1x.2y.3z' 'v0.0.0-../../etc/passwd' '4.9.0' 'vX.Y.Z'; do
    guard "$bad" >/dev/null 2>&1; rc=$?
    if [[ $rc -ne 0 ]]; then
        log_pass "guard refuses the tag '$bad'"
    else
        log_fail "guard refuses the tag '$bad'" "accepted"
    fi
done

# A newline in the tag forges a second key in $GITHUB_OUTPUT, which decouples
# the ref that was checked out from the version that gets reported.
guard "$(printf 'v1.1.1\nversion=9.9.9')" >/dev/null 2>&1; rc=$?
assert_exit_code "guard refuses a tag containing a newline" 1 "$rc"

# --- 2. release-guard.sh: version drift and tag divergence -------------------

build_fixture
printf '#!/usr/bin/env bash\nVERSION="9.9.8"\n' > "$FIXTURE/ci/craftsman-ci.sh"
git -C "$FIXTURE" commit -qam "drift ci/craftsman-ci.sh"
git -C "$FIXTURE" tag v9.9.9
git -C "$FIXTURE" tag craftsman--v9.9.9
out="$(guard v9.9.9)"; rc=$?
assert_exit_code "guard refuses a file left behind on the old version" 1 "$rc"
assert_contains "guard names the drifted file" "$out" "ci/craftsman-ci.sh"

build_fixture
printf '{"version": "9.9.8"}\n' > "$FIXTURE/.claude-plugin/plugin.json"
git -C "$FIXTURE" commit -qam "manifest disagrees with the tag"
git -C "$FIXTURE" tag v9.9.9
git -C "$FIXTURE" tag craftsman--v9.9.9
guard v9.9.9 >/dev/null 2>&1; rc=$?
assert_exit_code "guard refuses a tag the manifest disagrees with" 1 "$rc"

build_fixture
git -C "$FIXTURE" tag v9.9.9
out="$(guard v9.9.9)"; rc=$?
assert_exit_code "guard refuses a release with no marketplace tag" 1 "$rc"
assert_contains "guard says which tag is missing" "$out" "craftsman--v9.9.9"

build_fixture
git -C "$FIXTURE" tag v9.9.9
echo "later" > "$FIXTURE/other.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -qm "a second commit"
git -C "$FIXTURE" tag craftsman--v9.9.9
out="$(guard v9.9.9)"; rc=$?
assert_exit_code "guard refuses two tags on two commits" 1 "$rc"
assert_contains "guard reports both commits" "$out" "craftsman--v9.9.9"

# --- 3. release-build.sh: the archive is reproducible ------------------------

build_fixture
git -C "$FIXTURE" tag v9.9.9
name_a="$(bash "$FIXTURE/scripts/release-build.sh" v9.9.9 "$WORK/out-a")"
sleep 1   # a gzip header carrying an mtime would differ across this boundary
name_b="$(bash "$FIXTURE/scripts/release-build.sh" v9.9.9 "$WORK/out-b")"

assert_contains "build names the artifact after the version" "$name_a" "craftsman-9.9.9.tar.gz"

digest() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
if [[ "$(digest "$WORK/out-a/$name_a")" == "$(digest "$WORK/out-b/$name_b")" ]]; then
    log_pass "two builds of one tag produce identical bytes"
else
    log_fail "two builds of one tag produce identical bytes" "digests differ"
fi

if [[ "$(digest "$WORK/out-a/$name_a")" == "$(cut -d' ' -f1 < "$WORK/out-a/SHA256SUMS.txt")" ]]; then
    log_pass "SHA256SUMS.txt matches the archive it ships with"
else
    log_fail "SHA256SUMS.txt matches the archive it ships with" "checksum mismatch"
fi

bash "$FIXTURE/scripts/release-build.sh" 'v9.9.9; id' "$WORK/out-c" >/dev/null 2>&1; rc=$?
assert_exit_code "build refuses a malformed tag" 1 "$rc"

# --- 4. Workflow lint, each check proved against a failing fixture -----------

# Every `uses:` pinned to a commit SHA, across every workflow. A floating tag
# in a workflow holding `id-token: write` hands the signing identity to whoever
# can move that tag.
floating_uses() {
    grep -oE 'uses:[[:space:]]*[^[:space:]]+' "$1" \
        | sed -E 's/uses:[[:space:]]*//' | grep -vE '@[0-9a-f]{40}$' || true
}
# Both extensions, and composite actions too: a glob on workflows/*.yml left
# .github/workflows/evil.yaml and .github/actions/*/action.yml unexamined.
workflow_files() {
    find "$ROOT_DIR/.github" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort
}
while IFS= read -r wf; do
    [[ -z "$wf" ]] && continue
    if [[ -z "$(floating_uses "$wf")" ]]; then
        log_pass "${wf#"$ROOT_DIR"/}: every action pinned to a commit SHA"
    else
        log_fail "${wf#"$ROOT_DIR"/}: every action pinned" \
            "$(floating_uses "$wf" | tr '\n' ' ')"
    fi
done < <(workflow_files)
printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$WORK/floating.yml"
if [[ -n "$(floating_uses "$WORK/floating.yml")" ]]; then
    log_pass "pin check goes red on a floating tag"
else
    log_fail "pin check goes red on a floating tag" "fixture passed"
fi

# Permissions belong to the signing job, not to the file. A range-based `sed`
# reports the union of every job's block, so moving id-token to an unrelated
# job left the check green while the attestation could no longer be produced.
job_perms() {
    python3 - "$1" "$2" <<'PY'
import sys
path, job = sys.argv[1], sys.argv[2]
in_jobs = in_job = in_perms = False
for raw in open(path):
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    indent = len(line) - len(line.lstrip())
    if indent == 0:
        in_jobs = line.startswith("jobs:")
        in_job = in_perms = False
        continue
    if not in_jobs:
        continue
    if indent == 2 and line.rstrip().endswith(":"):
        in_job = line.strip()[:-1] == job
        in_perms = False
        continue
    if not in_job:
        continue
    if indent == 4:
        in_perms = line.strip() == "permissions:"
        continue
    if in_perms and indent == 6:
        print(line.strip().split("#")[0].strip())
PY
}
perms="$(job_perms "$WORKFLOW" provenance)"
for required in "contents: write" "id-token: write" "attestations: write"; do
    if echo "$perms" | grep -qx "$required"; then
        log_pass "the provenance job itself declares '$required'"
    else
        log_fail "the provenance job itself declares '$required'" "got: $(echo "$perms" | tr '\n' ' ')"
    fi
done
cat > "$WORK/moved.yml" <<'YAML'
jobs:
  unrelated:
    permissions:
      id-token: write
      attestations: write
    steps:
      - run: true
  provenance:
    permissions:
      contents: write
    steps:
      - run: true
YAML
if ! job_perms "$WORK/moved.yml" provenance | grep -qx "id-token: write"; then
    log_pass "permission check goes red when the grant sits on another job"
else
    log_fail "permission check goes red when the grant sits on another job" "fixture passed"
fi

# No `${{ }}` inside a shell block. A tag name is attacker-controlled text on a
# runner that holds `id-token: write`; `env:` is the only safe channel.
interpolated_run() {
    python3 - "$1" <<'PY'
import re, sys
# `needs.<job>.result` is a closed enum GitHub itself writes (success, failure,
# cancelled, skipped), so it cannot carry a payload into the shell. Every other
# expression is text somebody else can choose: a ref name, a branch, a title,
# an input. The exemption is narrow on purpose; widening it is how this check
# stops meaning anything.
SAFE = re.compile(r"\$\{\{\s*needs\.[A-Za-z0-9_-]+\.result\s*\}\}")
def risky(text):
    return "${{" in SAFE.sub("", text)
lines = open(sys.argv[1]).read().split("\n")
i, n = 0, len(lines)
while i < n:
    line = lines[i]
    stripped = line.strip()
    if stripped.startswith("- "):
        stripped = stripped[2:]
    if stripped.startswith("run:"):
        indent = len(line) - len(line.lstrip())
        if risky(stripped):
            print(f"{i+1}: {stripped}")
        i += 1
        while i < n:
            nxt = lines[i]
            if nxt.strip() and (len(nxt) - len(nxt.lstrip())) <= indent:
                break
            if risky(nxt):
                print(f"{i+1}: {nxt.strip()}")
            i += 1
        continue
    i += 1
PY
}
while IFS= read -r wf; do
    [[ -z "$wf" ]] && continue
    found="$(interpolated_run "$wf")"
    if [[ -z "$found" ]]; then
        log_pass "${wf#"$ROOT_DIR"/}: no expression interpolated into a shell block"
    else
        log_fail "${wf#"$ROOT_DIR"/}: no expression interpolated into a shell block" \
            "$(echo "$found" | head -3 | tr '\n' ' ')"
    fi
done < <(workflow_files)
cat > "$WORK/interp.yml" <<'YAML'
jobs:
  x:
    steps:
      - run: |
          echo "${{ github.ref_name }}"
YAML
if [[ -n "$(interpolated_run "$WORK/interp.yml")" ]]; then
    log_pass "interpolation check goes red on an expression inside run"
else
    log_fail "interpolation check goes red on an expression inside run" "fixture passed"
fi

# --- 5. The workflow does what the documentation says ------------------------

workflow_text="$(cat "$WORKFLOW")"

assert_contains "the guard script runs before anything is signed" \
    "$workflow_text" "scripts/release-guard.sh"
assert_contains "the build script produces the attested artifact" \
    "$workflow_text" "scripts/release-build.sh"
assert_contains "the artifact is attested" \
    "$workflow_text" "actions/attest-build-provenance@"
assert_contains "the attested subject is the archive the build step named" \
    "$workflow_text" 'subject-path: dist/${{ steps.build.outputs.name }}'
assert_contains "the archive is published under that same name" \
    "$workflow_text" 'gh release upload "$TAG" "dist/${NAME}"'
assert_contains "the checksums are published alongside it" \
    "$workflow_text" "dist/SHA256SUMS.txt"
assert_contains "the attestation is verified with the signer workflow pinned" \
    "$workflow_text" "--signer-workflow"
assert_contains "the job runs under a protectable environment" \
    "$workflow_text" "environment: release"

# workflow_dispatch can be aimed at any branch or tag, and the workflow file
# that runs is the one on that ref, so it turns the signing identity into a
# primitive available to anyone with write access.
if grep -qE '^\s*workflow_dispatch:' "$WORKFLOW"; then
    log_fail "no workflow_dispatch trigger" "the workflow can be aimed at any ref"
else
    log_pass "no workflow_dispatch trigger"
fi

if grep -qE "^\s+- 'v\[0-9\]" "$WORKFLOW"; then
    log_pass "the trigger is anchored on v<x.y.z>, so craftsman--v* fires nothing"
else
    log_fail "the trigger is anchored on v<x.y.z>" "the tag filter is not anchored"
fi

# --- 6. The documented verification matches the workflow ---------------------

security_text="$(cat "$ROOT_DIR/SECURITY.md")"

assert_contains "SECURITY.md documents gh attestation verify" \
    "$security_text" "gh attestation verify"
assert_contains "SECURITY.md pins the signer workflow" \
    "$security_text" "--signer-workflow"
assert_contains "SECURITY.md documents the checksum check" \
    "$security_text" "sha256sum --check"
assert_contains "SECURITY.md states the source tarball is not attested" \
    "$security_text" "archive/refs/tags"
assert_contains "SECURITY.md states what the attestation does not prove" \
    "$security_text" "protect against someone who already has write access"

# README points at an anchor in SECURITY.md; a heading that no longer exists
# sends every reader of the install instructions to the top of the file.
for readme in "$ROOT_DIR/README.md" "$ROOT_DIR/README.fr.md"; do
    while IFS= read -r anchor; do
        [[ -z "$anchor" ]] && continue
        expected="$(echo "$security_text" | grep -iE "^#{2,3} " \
            | sed -E 's/^#+ //' | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9 -]//g; s/ /-/g' | grep -Fx "$anchor" || true)"
        if [[ -n "$expected" ]]; then
            log_pass "$(basename "$readme"): SECURITY.md#${anchor} resolves"
        else
            log_fail "$(basename "$readme"): SECURITY.md#${anchor} resolves" "no such heading"
        fi
    done < <(grep -oE 'SECURITY\.md#[a-z0-9-]+' "$readme" | sed 's/.*#//' | sort -u)
done

test_summary
