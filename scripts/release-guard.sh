#!/usr/bin/env bash
# =============================================================================
# release-guard.sh <tag>
#
# Everything a release must be true about itself before anything is signed.
# It lives here rather than inside .github/workflows/release.yml for one
# reason: a check that only runs on GitHub can only be tested by pushing a tag,
# so it gets tested by the release it was meant to protect.
#
# Refuses:
#   - a tag that is not exactly v<x.y.z>
#   - a tag whose version disagrees with the four tracked files
#   - a craftsman--v<version> tag pointing at a different commit
#
# The marketplace tag is pushed by the same `claude plugin tag --push` as the
# release tag, so it can legitimately land a few seconds late. It is waited for,
# not skipped: a guard whose degraded mode is green is not a guard.
#   RELEASE_GUARD_TAG_WAIT  seconds to wait for it (default 60, 0 disables)
#   RELEASE_GUARD_FETCH     `false` to skip `git fetch` (offline, tests)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TAG="${1:-}"
WAIT_SECONDS="${RELEASE_GUARD_TAG_WAIT:-60}"
DO_FETCH="${RELEASE_GUARD_FETCH:-true}"

if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>   # e.g. v4.9.0" >&2
    exit 1
fi

# Anchored, and a regex rather than a glob: `v[0-9]*.[0-9]*.[0-9]*` accepts
# `v4.9.0; rm -rf /` and `v1.1.1<newline>version=4.9.0`, both of which git
# accepts as ref names and the second of which forges a second key in
# $GITHUB_OUTPUT.
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "FAILED: refusing to release from '${TAG}': expected v<x.y.z>." >&2
    exit 1
fi

VERSION="${TAG#v}"

# One implementation of "which files carry the version", shared with the bump.
if ! bash "${SCRIPT_DIR}/bump-version.sh" --check "$VERSION"; then
    echo "FAILED: ${TAG} does not match the version in the tracked files." >&2
    exit 1
fi

MARKET="craftsman--v${VERSION}"

tag_commit() {
    git -C "$ROOT_DIR" rev-list -n 1 "refs/tags/$1" 2>/dev/null
}

waited=0
while ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/${MARKET}" >/dev/null; do
    if [[ "$waited" -ge "$WAIT_SECONDS" ]]; then
        echo "FAILED: ${MARKET} is absent after ${WAIT_SECONDS}s." >&2
        echo "The marketplace resolves that tag; releasing without it ships a version nobody can install." >&2
        exit 1
    fi
    [[ "$DO_FETCH" == "true" ]] && git -C "$ROOT_DIR" fetch --tags --quiet origin 2>/dev/null || true
    sleep 5
    waited=$((waited + 5))
done

RELEASE_COMMIT="$(tag_commit "$TAG")"
MARKET_COMMIT="$(tag_commit "$MARKET")"

if [[ "$RELEASE_COMMIT" != "$MARKET_COMMIT" ]]; then
    echo "FAILED: ${TAG} is ${RELEASE_COMMIT} but ${MARKET} is ${MARKET_COMMIT}." >&2
    echo "One version number would resolve to two different plugins." >&2
    exit 1
fi

echo "OK: ${TAG} and ${MARKET} both resolve to ${RELEASE_COMMIT}, version ${VERSION} is in sync."
