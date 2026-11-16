#!/usr/bin/env bash
# =============================================================================
# An edit is refused for what it brings, not for what the file already held
# (CR-306).
#
# The pre-write gate judged the whole would-be file. Editing one line of a file
# that already carried a blocking finding was refused for code the edit did not
# touch, in every project that had not marked its debt first: the adoption
# problem the rule baseline exists to remove, back through the unmarked door.
#
# The file on disk before the edit is now an implicit mark: the Nth occurrence
# of a rule is held back (reported, not blocking) when the file already held at
# least N. A finding the edit introduces still blocks, a new file has nothing to
# hold, and the rules the baseline never holds (SEC*, RATCHET001) still block.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-preexisting.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$WORK/data" CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
mkdir -p "$HOME" "$CLAUDE_PLUGIN_DATA" "$WORK/project/src/Domain"
printf '{}\n' > "$WORK/project/composer.json"

_php() { # <file> <class modifier> [<extra body line>]
    printf '<?php\n\ndeclare(strict_types=1);\n\nnamespace App\\Domain;\n\n%sclass %s\n{\n%s\n}\n' \
        "$2" "$(basename "$1" .php)" "${3:-}" > "$1"
}
_edit() { # <file> <old> <new>
    jq -n --arg f "$1" --arg o "$2" --arg n "$3" \
        '{session_id:"preexisting", hook_event_name:"PreToolUse", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}'
}
_write() { # <file> <content>
    jq -n --arg f "$1" --arg c "$2" \
        '{session_id:"preexisting", hook_event_name:"PreToolUse", tool_name:"Write", tool_input:{file_path:$f, content:$c}}'
}
GATE_OUT=""
GATE_CODE=0
# Sets GATE_OUT and GATE_CODE in this shell. Called as $(...), the output would
# vanish with the subshell: the CR-301 defect, which this test first reproduced.
_gate() { # <payload>
    GATE_CODE=0
    GATE_OUT=$(cd "$WORK/project" && printf '%s' "$1" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1) || GATE_CODE=$?
}

echo "=== CR-306: findings the file already held ==="

LEGACY="$WORK/project/src/Domain/Legacy.php"
_php "$LEGACY" "" "    // legacy"
_gate "$(_edit "$LEGACY" '// legacy' '// legacy, touched')"
assert_exit_code "an edit leaves a non-final class it did not touch" 0 "$GATE_CODE"
assert_contains "and still reports it" "$GATE_OUT" "PHP002"
assert_contains "as held back, not blocking" "$GATE_OUT" "already in the file before this edit"

# The post-write that follows must agree: a gate that lets the edit through and
# a post-write that blocks the same finding after it lands send the model two
# verdicts on one write.
sed -i.bak 's|// legacy|// legacy, touched|' "$LEGACY" && rm -f "$LEGACY.bak"
POST_CODE=0
POST_OUT=$(cd "$WORK/project" && _edit "$LEGACY" '// legacy' '// legacy, touched' \
    | jq '.hook_event_name = "PostToolUse"' | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1) || POST_CODE=$?
assert_exit_code "the post-write agrees with the gate" 0 "$POST_CODE"
assert_contains "and reports the finding as held too" "$POST_OUT" "already in the file before this edit"
_php "$LEGACY" "" "    // legacy"

_gate "$(_edit "$LEGACY" '// legacy' '$at = new \DateTime();')"
assert_exit_code "an edit that brings a new finding is refused" 2 "$GATE_CODE"
assert_contains "and names what it brought" "$GATE_OUT" "PHP004"

CLEAN="$WORK/project/src/Domain/Clean.php"
_php "$CLEAN" "final " "    // clean"
_gate "$(_edit "$CLEAN" 'final class Clean' 'class Clean')"
assert_exit_code "an edit that removes final is refused" 2 "$GATE_CODE"
assert_contains "for PHP002" "$GATE_OUT" "PHP002"

FRESH="$WORK/project/src/Domain/Fresh.php"
_gate "$(_write "$FRESH" "$(_php /dev/stdout "" | sed 's/class stdout/class Fresh/')")"
assert_exit_code "a new file has nothing to hold back" 2 "$GATE_CODE"

# A finding the file silenced was not held: it was suppressed. Deleting the
# marker exposes it, and that is something the edit brings.
MARKED="$WORK/project/src/Domain/Marked.php"
MARKER="    // craftsman-""ignore: PHP002 (debt: kept for the test)"
_php "$MARKED" "" "$MARKER"
_gate "$(_edit "$MARKED" "$MARKER" '    // marker gone')"
assert_exit_code "deleting a suppression marker exposes what it hid" 2 "$GATE_CODE"

SECRET="$WORK/project/src/Domain/Secret.php"
_php "$SECRET" "final " '    private string $apiKey = "sk_live_abcdef1234567890abcdef"; // secrets-scan: allow'
_gate "$(_edit "$SECRET" 'final class Secret' 'final class Secret // touched')"
assert_exit_code "a secret the file already held still blocks" 2 "$GATE_CODE"
assert_contains "for SEC001" "$GATE_OUT" "SEC001"

test_summary
