#!/usr/bin/env bash
# =============================================================================
# Rust Pack: Rust Static Analysis (Level 2) - clippy today, room for more
#
# The file is not named after clippy on purpose: `supersedes:` names the tool
# that outranks a Level 1 rule, and lang_registry.py refuses an entry whose tool
# shares its name with the pack's own adapter (a tool may not outrank its own
# verdicts). The adapter is the pack's Level 2 entry point; clippy is one
# analyser behind it.
#
# Graceful degradation: prints nothing when the tool is not installed.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/packs/rust/static-analysis/rust-analysis.sh"
#   findings=$(pack_sa_rust "/path/to/file.rs")
#
# Returns "CODE:LINE:MESSAGE", one per line. The code is what the rules engine
# resolves severity for, so it is the only thing a project's `.craft-config.yml`
# can reach.
#
# clippy is asked for its JSON diagnostics rather than its prose reporter. The
# prose is written for a human watching a terminal: it is reworded between
# releases and it announces success in the same stream as the failures.
#
# craftsman-ignore: SH001
# =============================================================================

_pack_sa_rust_available() {
    command -v cargo >/dev/null 2>&1 || return 1
    cargo clippy --version >/dev/null 2>&1 || return 1
    return 0
}

# The Cargo.toml that owns this file, walking up from it. Without it clippy
# runs on whatever crate the hook's working directory happens to sit in, which
# in a workspace is a different unit of code entirely.
_pack_sa_rust_manifest() {
    local directory
    directory="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 1
    while [[ -n "$directory" && "$directory" != "/" ]]; do
        if [[ -f "${directory}/Cargo.toml" ]]; then
            printf '%s' "${directory}/Cargo.toml"
            return 0
        fi
        directory="$(dirname "$directory")"
    done
    return 1
}

# The JSON filter, kept out of pack_sa_rust so the orchestration reads as the
# five steps it is: probe, locate the crate, run, declare, filter.
_pack_sa_rust_filter() {
    python3 -c '
import json, os, sys

target = os.path.realpath(sys.argv[1])
root = os.path.dirname(os.path.realpath(sys.argv[2]))
for raw in sys.stdin:
    raw = raw.strip()
    if not raw or not raw.startswith("{"):
        continue
    try:
        record = json.loads(raw)
    except ValueError:
        continue
    message = record.get("message")
    if not isinstance(message, dict):
        continue
    spans = message.get("spans") or []
    primary = next((s for s in spans if s.get("is_primary")), None)
    if not primary:
        continue
    # Resolved paths, not basenames: mod.rs, lib.rs and main.rs are the three
    # most common file names in a Rust workspace, so a suffix match attributes
    # one crate diagnostics that belong to another.
    reported = primary.get("file_name") or ""
    if not os.path.isabs(reported):
        reported = os.path.join(root, reported)
    if os.path.realpath(reported) != target:
        continue
    text = (message.get("message") or "clippy lint").replace("\n", " ")
    print("CLIPPY001:%s:%s" % (primary.get("line_start", 0), text))
' "$1" "$2"
}

pack_sa_rust() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    _pack_sa_rust_available || return 0

    local manifest
    manifest="$(_pack_sa_rust_manifest "$file")" || return 0

    local absolute
    absolute="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"

    # `unwrap_used` and `expect_used` are `restriction` lints: clippy ships them
    # off by default, so a run that did not ask for them says nothing about
    # RUST001 or RUST005. Declaring those covered anyway deleted the pack's
    # headline rule on every machine with clippy installed. They are requested
    # explicitly, and coverage is declared only after the run that asked.
    local output status=0
    output=$(sa_timeout "${SA_BUDGET_PROJECT_SECONDS:-30}" \
        cargo clippy --manifest-path "$manifest" --message-format=json --quiet \
        -- -W clippy::unwrap_used -W clippy::expect_used 2>/dev/null) || status=$?

    # No verdict is not a clean verdict: a timeout or a failed build leaves the
    # Level 1 rules to answer, which is what precedence_flush is for.
    [[ $status -eq 124 ]] && return 0

    if type precedence_declare_covered >/dev/null 2>&1; then
        precedence_declare_covered "RUST001"
        precedence_declare_covered "RUST005"
    fi

    printf '%s' "$output" | _pack_sa_rust_filter "$absolute" "$manifest"
}
