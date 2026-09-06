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

pack_sa_rust() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    _pack_sa_rust_available || return 0

    # Declared past the availability probe, never before it: clippy answers for
    # RUST001 and RUST005 whether or not it found anything, and a clean run is
    # a verdict. An absent clippy must not silence the Level 1 rules.
    if type precedence_declare_covered >/dev/null 2>&1; then
        precedence_declare_covered "RUST001"
        precedence_declare_covered "RUST005"
    fi

    local target
    target="$(basename "$file")"

    # cargo clippy runs on a crate, so it is asked once and its diagnostics are
    # filtered down to the file under review. --message-format=json is stable;
    # the human reporter is not.
    cargo clippy --message-format=json --quiet 2>/dev/null | python3 -c '
import json, sys

target = sys.argv[1]
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
    if not str(primary.get("file_name", "")).endswith(target):
        continue
    text = (message.get("message") or "clippy lint").replace("\n", " ")
    print("CLIPPY001:%s:%s" % (primary.get("line_start", 0), text))
' "$target"
}
