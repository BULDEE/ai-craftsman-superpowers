#!/usr/bin/env bash
# =============================================================================
# SEC001's credential shapes, one list for every pack.
#
# A key is the same string whatever file holds it, so the shapes live here and
# each pack's security validator reads them through secret_hits, adding only
# its own comment syntax and runtime idiom. Two copies of this list lived in
# two packs and both missed sk-proj- and sk-ant- keys that the repository's
# secrets scanner already knew (CR-257).
#
# Sourced by pack-loader.sh, so every front-end that loads packs has it.
# NOTE: sourced, never executed. Do NOT add set -euo pipefail.
# =============================================================================

# A literal assigned to a name that says it is a credential. Matched without
# case. A type annotation may sit between the name and the `=`. A bare `*_KEY`
# name only counts with a long separator-free value: storage, cache and i18n
# keys are dotted or dashed words, issued keys are not.
_SECRET_SHAPES_ANNOTATION='([[:space:]]*:[[:space:]]*[A-Za-z_][][A-Za-z0-9_.|<> ]*)?'
_SECRET_SHAPES_NAMED="((api|access|secret|private|auth|client|signing|encryption)[_-]?key|secret|password|passwd|token)[\"']?${_SECRET_SHAPES_ANNOTATION}[[:space:]]*[:=][[:space:]]*[\"'\`][A-Za-z0-9_/+.=-]{12,}[\"'\`]|key[\"']?${_SECRET_SHAPES_ANNOTATION}[[:space:]]*[:=][[:space:]]*[\"'\`][A-Za-z0-9]{32,}[\"'\`]"

# A credential its issuer made recognisable by a prefix. Matched WITH case
# (`ASIA` opens an AWS key id, `Asia/` opens a time zone) and never inside a
# longer word (`task-` ends in `sk-`).
_SECRET_SHAPES_ISSUED='(^|[^A-Za-z0-9])((sk|rk)_live[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{8,}|github_pat_[A-Za-z0-9_]{8,}|xox[abposr]-[A-Za-z0-9-]{8,}|A(KIA|SIA)[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{8,}|sk-(ant|proj|svcacct|admin)-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,})|hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]{16,}|BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'

# Values that document a credential instead of being one.
_SECRET_SHAPES_FAKE='(YOUR[_-]?|CHANGE[_-]?ME|EXAMPLE|PLACEHOLDER|DUMMY|SAMPLE|REDACTED|X{6,}|\.\.\.)'

# secret_hits [runtime_re] - read numbered code lines (`12:code`) on stdin and
# print, in line order, those that hold a credential, minus documentation
# values. A line that also reads a value at run time (runtime_re, the caller's
# idiom: process.env, getenv, os.environ) is spared the name rule only: an
# issued prefix is a key wherever it sits, an env fallback included.
secret_hits() {
    local runtime="${1:-}" lines
    lines=$(cat)
    { grep -Ei "$_SECRET_SHAPES_NAMED" <<< "$lines" | grep -viE "${_SECRET_SHAPES_FAKE}${runtime:+|$runtime}"
      grep -E "$_SECRET_SHAPES_ISSUED" <<< "$lines" | grep -viE "$_SECRET_SHAPES_FAKE"; } \
        | sort -t: -k1,1n -u
}
