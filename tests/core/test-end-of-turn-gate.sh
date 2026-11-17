#!/usr/bin/env bash
# =============================================================================
# A turn does not end with a blocking finding left on disk (CR-259).
#
# A post-write refusal comes after the write has landed: the model reads
# "BLOCKED", and nothing made it come back to the file before it reported the
# work done. The Stop gate reads the session state alone, so the common case
# costs one jq: the blocking findings that LANDED this session and are still
# on disk. A refusal that never landed (the pre-write gate) is not on disk, and
# a finding the file already held before the session (CR-306) is the ratchet's
# business, not this turn's.
#
# The state each case starts from is written by the real producers,
# pre-write-check.sh and post-write-check.sh. The Stop payloads are the
# captured ones of Claude Code and Codex, with only the session swapped in.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-end-of-turn.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$WORK/data" CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CRAFTSMAN_RUNTIME_HOME="$HOME" CLAUDE_PLUGIN_OPTION_STRICTNESS=strict
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDE_CODE_SESSION_ID CRAFTSMAN_SESSION_ID
PROJECT="$WORK/project"
mkdir -p "$HOME/.claude" "$CLAUDE_PLUGIN_DATA" "$PROJECT/src/Domain"
printf '{}\n' > "$PROJECT/composer.json"

GATE="$ROOT_DIR/hooks/end-of-turn-gate.sh"
CLAUDE_STOP="$ROOT_DIR/tests/fixtures/hosts/claude-code/2.1.272/stop.json"
CODEX_STOP="$ROOT_DIR/tests/fixtures/hosts/codex/0.154.0/stop.json"

_php() { # <file> <class modifier>
    printf '<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\Domain;\n\n%sclass %s\n{\n    // body\n}\n' \
        "$2" "$(basename "$1" .php)" > "$1"
}
_hook() { # <hook> <tool> <file> [<content>]
    jq -n --arg t "$2" --arg f "$3" --arg c "${4:-}" \
        --arg s "$SID" '{session_id: $s, tool_name: $t, tool_input: ({file_path: $f} + (if $c == "" then {} else {content: $c} end))}' \
        | (cd "$PROJECT" && bash "$ROOT_DIR/hooks/$1" >/dev/null 2>&1)
}
# A write that lands: the file is on disk, then post-write judges it.
_landed() { # <file> <class modifier>
    _php "$1" "$2"
    _hook post-write-check.sh Write "$1"
}
STOP_OUT=""
# Sets STOP_OUT, the gate's stdout, in this shell (never through $(...)).
_stop() { # <fixture> [stop_hook_active] [strictness]
    STOP_OUT=$(jq --argjson a "${2:-false}" --arg cwd "$PROJECT" --arg s "$SID" \
        '.session_id = $s | .stop_hook_active = $a | .cwd = $cwd' "$1" \
        | (cd "$PROJECT" && CLAUDE_PLUGIN_OPTION_STRICTNESS="${3:-strict}" bash "$GATE" 2>/dev/null))
}
_blocked() { [[ "$(printf '%s' "$STOP_OUT" | jq -r '.decision // empty' 2>/dev/null)" == "block" ]]; }
_warned() { [[ -n "$(printf '%s' "$STOP_OUT" | jq -r '.systemMessage // empty' 2>/dev/null)" ]] && ! _blocked; }
_check() { # <label> <condition function>
    if "$2"; then log_pass "$1"; else log_fail "$1" "gate output: '${STOP_OUT}'"; fi
}
_silent() { [[ -z "$STOP_OUT" ]]; }

SID=s259-none
echo "=== Nothing written: the gate has nothing to say ==="
_stop "$CLAUDE_STOP"
_check "a session without writes ends quietly" _silent

SID=s259-landed
echo "=== A blocking finding landed and is still on disk ==="
BAD="$PROJECT/src/Domain/Bad.php"
_landed "$BAD" ""
_stop "$CLAUDE_STOP"
_check "the turn is sent back" _blocked
assert_contains "the reason names the rule" "$STOP_OUT" "PHP002"
assert_contains "and the file, relative to the project" "$STOP_OUT" "src/Domain/Bad.php"
_stop "$CODEX_STOP"
_check "a Codex Stop payload is sent back too" _blocked

_stop "$CLAUDE_STOP" true
_check "already sent back once: shown to the user, never looped" _warned
_stop "$CLAUDE_STOP" false moderate
_check "moderate warns and lets the turn end" _warned
_stop "$CLAUDE_STOP" false relaxed
_check "relaxed says nothing" _silent

echo "=== The finding is answered ==="
_landed "$BAD" "final "
_stop "$CLAUDE_STOP"
_check "a later clean write of the file settles it" _silent

SID=s259-gone
GONE="$PROJECT/src/Domain/Gone.php"
_landed "$GONE" ""
rm -f "$GONE"
_stop "$CLAUDE_STOP"
_check "a file deleted since is not held against the turn" _silent

SID=s259-refused
echo "=== Only what landed counts ==="
REFUSED="$PROJECT/src/Domain/Refused.php"
_php "$WORK/refused.php" ""
_hook pre-write-check.sh Write "$REFUSED" "$(cat "$WORK/refused.php")"
if [[ -f "$REFUSED" ]]; then log_fail "the fixture" "the refused file exists, the case proves nothing"; fi
_stop "$CLAUDE_STOP"
_check "a write the gate refused never reached the disk: nothing to answer" _silent

# A refusal on a file that exists: what the file owes now names the rule, the
# disk does not hold it.
CLEAN="$PROJECT/src/Domain/Clean.php"
_landed "$CLEAN" "final "
jq -n --arg f "$CLEAN" --arg s "$SID" '{session_id: $s, tool_name: "Edit",
    tool_input: {file_path: $f, old_string: "final class Clean", new_string: "class Clean"}}' \
    | (cd "$PROJECT" && bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1)
if ! grep -q 'final class Clean' "$CLEAN"; then log_fail "the fixture" "the refused edit landed"; fi
_stop "$CLAUDE_STOP"
_check "an edit the gate refused leaves the clean file clean: nothing to answer" _silent

SID=s259-legacy
LEGACY="$PROJECT/src/Domain/Legacy.php"
_php "$LEGACY" ""
jq -n --arg f "$LEGACY" --arg s "$SID" '{session_id: $s, tool_name: "Edit",
    tool_input: {file_path: $f, old_string: "// body", new_string: "// body, touched"}}' \
    | (cd "$PROJECT" && bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1)
sed -i.bak 's|// body|// body, touched|' "$LEGACY" && rm -f "$LEGACY.bak"
_hook post-write-check.sh Edit "$LEGACY"
_stop "$CLAUDE_STOP"
_check "a finding the file held before the session does not hold the turn" _silent

test_summary
