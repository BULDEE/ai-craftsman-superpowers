#!/usr/bin/env bash
# =============================================================================
# release-build.sh <tag> <output-dir>
#
# Builds the artifact the release publishes and the attestation signs, and
# prints its file name on stdout.
#
# `gzip -n` drops the mtime and the original file name from the gzip header, so
# two builds of one commit produce identical bytes. That is what makes the
# published checksum a durable claim instead of a record of one run: anyone can
# rebuild the archive from the tag and compare, which is the only part of the
# verification chain that does not require trusting GitHub.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TAG="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "$TAG" || -z "$OUT_DIR" ]]; then
    echo "Usage: $0 <tag> <output-dir>" >&2
    exit 1
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "FAILED: refusing to build from '${TAG}': expected v<x.y.z>." >&2
    exit 1
fi

VERSION="${TAG#v}"
NAME="craftsman-${VERSION}.tar.gz"

mkdir -p "$OUT_DIR"

# GNU coreutils on the runner, BSD on a maintainer's macOS. Both ship one of
# these, and a release that can only be reproduced on Linux is not reproducible.
checksum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

git -C "$ROOT_DIR" archive --format=tar --prefix="craftsman-${VERSION}/" "refs/tags/${TAG}" \
    | gzip -9 -n > "${OUT_DIR}/${NAME}"

( cd "$OUT_DIR" && checksum "$NAME" > SHA256SUMS.txt )

echo "$NAME"
