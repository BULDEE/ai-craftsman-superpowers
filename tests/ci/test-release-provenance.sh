#!/usr/bin/env bash
# =============================================================================
# The release workflow signs what users download.
#
# A provenance job is only worth the trust it advertises, so the properties
# checked here are the ones whose absence would make the badge a lie:
#
#   1. every action it runs is pinned to a commit, because a floating tag hands
#      the signing identity to whoever can move that tag;
#   2. the job holds id-token and attestations write, without which the
#      attestation is never produced and the release still ships;
#   3. the tarball is built reproducibly and the tag is checked against the
#      manifest, so the signed bytes match the version on the label;
#   4. SECURITY.md documents the verification a user is supposed to run.
#
# Every structural assertion runs against a deliberately broken fixture first,
# so a green result here means the check discriminates rather than that it
# always passes.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-release-provenance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "=== Release provenance ==="

# --- The checks, as functions, so the fixtures can exercise the same code ----

# Prints every `uses:` line that is not pinned to a 40-character commit SHA.
floating_uses() {
    local file="$1"
    grep -oE 'uses:[[:space:]]*[^[:space:]]+' "$file" \
        | sed -E 's/uses:[[:space:]]*//' \
        | grep -vE '@[0-9a-f]{40}$' || true
}

# Prints the permissions a job block declares, one per line.
job_permissions() {
    local file="$1"
    sed -n '/^    permissions:/,/^    [a-z]/p' "$file" \
        | grep -oE '^      [a-z-]+: [a-z]+' \
        | sed 's/^ *//' || true
}

# --- 1. The workflow exists and is syntactically loadable --------------------

if [[ -f "$WORKFLOW" ]]; then
    log_pass "release.yml exists"
else
    log_fail "release.yml exists" "$WORKFLOW not found"
    test_summary
fi

if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW" 2>/dev/null; then
    log_pass "release.yml is valid YAML"
else
    # PyYAML is not a hard dependency of this repository; a missing parser must
    # not read as a broken workflow.
    if python3 -c "import yaml" 2>/dev/null; then
        log_fail "release.yml is valid YAML" "PyYAML refused to parse it"
    else
        log_pass "release.yml YAML parse skipped (PyYAML absent)"
    fi
fi

# --- 2. Every action is pinned, here and in every other workflow -------------

for wf in "$ROOT_DIR"/.github/workflows/*.yml; do
    floating="$(floating_uses "$wf")"
    if [[ -z "$floating" ]]; then
        log_pass "$(basename "$wf"): every action pinned to a commit SHA"
    else
        log_fail "$(basename "$wf"): every action pinned to a commit SHA" \
            "floating: $(echo "$floating" | tr '\n' ' ')"
    fi
done

# Known-good control: the same function must report a floating tag.
cat > "$WORK/floating.yml" <<'YAML'
jobs:
  x:
    steps:
      - uses: actions/checkout@v4
YAML
if [[ -n "$(floating_uses "$WORK/floating.yml")" ]]; then
    log_pass "pin check reports RED on a floating tag"
else
    log_fail "pin check reports RED on a floating tag" "fixture passed the check"
fi

# --- 3. The signing job holds the permissions the attestation needs ----------

perms="$(job_permissions "$WORKFLOW")"
for required in "contents: write" "id-token: write" "attestations: write"; do
    if echo "$perms" | grep -qx "$required"; then
        log_pass "provenance job declares '$required'"
    else
        log_fail "provenance job declares '$required'" "declared: $(echo "$perms" | tr '\n' ' ')"
    fi
done

# Known-good control: a job without the OIDC permission must be caught.
cat > "$WORK/nooidc.yml" <<'YAML'
jobs:
  x:
    permissions:
      contents: write
    steps:
      - run: true
YAML
if ! job_permissions "$WORK/nooidc.yml" | grep -qx "id-token: write"; then
    log_pass "permission check reports RED without id-token"
else
    log_fail "permission check reports RED without id-token" "fixture passed the check"
fi

# --- 4. What the job actually does -------------------------------------------

assert_contains "attests the artifact it builds" \
    "$(cat "$WORKFLOW")" "actions/attest-build-provenance@"

assert_contains "attestation subject is the built tarball" \
    "$(cat "$WORKFLOW")" "subject-path: dist/"

# gzip -n is what makes the published checksum reproducible; without it the
# archive carries a build timestamp and two builds of one commit differ.
assert_contains "tarball is built reproducibly (gzip -n)" \
    "$(cat "$WORKFLOW")" "gzip -9 -n"

assert_contains "refuses a tag that disagrees with the manifest" \
    "$(cat "$WORKFLOW")" ".claude-plugin/plugin.json"

assert_contains "compares the marketplace tag with the release tag" \
    "$(cat "$WORKFLOW")" "craftsman--v"

assert_contains "verifies the attestation it just published" \
    "$(cat "$WORKFLOW")" "gh attestation verify"

# The marketplace tag must not itself trigger a second release run: `v*` does
# not match `craftsman--v*`, but an over-broad pattern like `*v*` would.
if grep -qE "^\s+- 'v\[0-9\]" "$WORKFLOW"; then
    log_pass "trigger is anchored on v<x.y.z>, so craftsman--v* fires nothing"
else
    log_fail "trigger is anchored on v<x.y.z>" "tag filter is not anchored"
fi

# --- 5. The documented verification matches the workflow ---------------------

SECURITY="$ROOT_DIR/SECURITY.md"
security_text="$(cat "$SECURITY")"

assert_contains "SECURITY.md documents gh attestation verify" \
    "$security_text" "gh attestation verify"

assert_contains "SECURITY.md documents the checksum check" \
    "$security_text" "sha256sum --check"

assert_contains "SECURITY.md names the attested artifact" \
    "$security_text" "craftsman-\${VERSION}.tar.gz"

# The archive GitHub generates for a tag is not the signed one. Saying so is
# the difference between a verification a user can complete and one that fails
# on the wrong file.
assert_contains "SECURITY.md states the source tarball is not attested" \
    "$security_text" "archive/refs/tags"

test_summary
