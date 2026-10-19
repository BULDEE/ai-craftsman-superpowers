#!/usr/bin/env bash
# =============================================================================
# CR-230: no message offers a way out that does not exist.
#
# Measured 2026-10-18: the pre-write refusal of SEC001 ended on "Use //
# craftsman-ignore: <RULE_ID> to suppress", a marker the gate refuses for that
# rule (`never_ignorable: true` in rules/core.yml). post-write told the model
# the same in its JSON, and its stderr claimed no SEC* finding takes a marker,
# false for SEC004 since CR-231. What a rule allows comes from the manifest,
# in every channel the model reads: stderr, JSON, the warning actions, the
# subagent gate and the exported doctrine.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-cr230-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-cr230.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT
mkdir -p "$WORK/src/ui" "$WORK/src/relaxed" "$WORK/home"
cd "$WORK" && git init -q . && printf '{"name":"fixture"}\n' > package.json

# Assembled at run time: the repository never holds a key-shaped literal.
KEY="sk_""live_51HxQ$(printf 'a%.0s' {1..24})"
SECRET_TS="export const stripe = \"$KEY\";"
OPEN_PHP=$'<?php\n\ndeclare(strict_types=1);\n\nnamespace App;\n\nclass Invoice\n{\n}'
SECRET_PHP=$'<?php\n\ndeclare(strict_types=1);\n\nnamespace App;\n\nfinal class Gateway\n{\n    private const KEY = "'"$KEY"$'";\n}'
SINK_JS="export const show = (el, comment) => { el.innerHTML = comment; };"

RC=0
ERR=""
OUT=""
_payload() { # $1 event, $2 path, $3 content
    python3 -c '
import json, sys
print(json.dumps({"session_id": "s230", "hook_event_name": sys.argv[1], "tool_name": "Write", "cwd": sys.argv[4],
                  "tool_input": {"file_path": sys.argv[2], "content": sys.argv[3]}, "tool_response": {"success": True}}))' \
        "$1" "$WORK/$2" "$3" "$WORK"
}
# Results travel back through RC, OUT and ERR, read by the assertions below.
# craftsman-ignore: WARN-SH001
_run() { # $1 hook, $2 event, $3 path, $4 content
    RC=0
    OUT=$(_payload "$2" "$3" "$4" | HOME="$WORK/home" bash "$ROOT_DIR/hooks/$1" 2>"$WORK/err") || RC=$?
    ERR=$(cat "$WORK/err")
}
_pre()  { _run pre-write-check.sh PreToolUse "$1" "$2"; }
_post() { printf '%s\n' "$2" > "$WORK/$1"; _run post-write-check.sh PostToolUse "$1" "$2"; }
_model_text() { printf '%s\n%s' "$ERR" "$(printf '%s' "$OUT" | jq -r '.. | strings' 2>/dev/null)"; }
_advice_lines() { _model_text | grep -i 'craftsman-ignore'; }

expect() { # $1 label, $2 condition result (0 = holds), $3 detail
    if [[ "$2" -eq 0 ]]; then log_pass "$1"; else log_fail "$1" "$3"; fi
}
_flat() { _model_text | tr '\n' ' ' | cut -c1-220; }

echo ""
echo "--- pre-write: the refusal names only markers that work ---"
_pre "src/ui/pay.ts" "$SECRET_TS"
[[ "$RC" -eq 2 && -z "$(_advice_lines)" && "$(_model_text)" == *"No marker silences SEC001"* ]]
expect "SEC001 refused: no craftsman-ignore advice, and it says no marker silences it" $? "rc=$RC $(_flat)"

_pre "src/Invoice.php" "$OPEN_PHP"
[[ "$RC" -eq 2 && "$(_advice_lines)" == *PHP002* && "$(_model_text)" != *"No marker"* ]]
expect "control: an ignorable rule (PHP002) is offered its marker" $? "rc=$RC $(_flat)"

_pre "src/Gateway.php" "${SECRET_PHP/final class/class}"
[[ "$RC" -eq 2 && "$(_advice_lines)" == *PHP002* && "$(_advice_lines)" != *SEC001* && "$(_model_text)" == *"No marker silences SEC001"* ]]
expect "both at once: the marker is offered for PHP002, never for SEC001" $? "rc=$RC $(_flat)"

echo ""
echo "--- post-write: stderr and JSON agree with the manifest ---"
_post "src/ui/pay.ts" "$SECRET_TS"
[[ "$RC" -eq 2 && -z "$(_advice_lines)" && "$(_model_text)" == *"No marker silences SEC001"* ]]
expect "SEC001 on disk: neither channel offers a marker" $? "rc=$RC $(_flat)"

_post "src/ui/comment.js" "$SINK_JS"
[[ "$RC" -eq 2 && "$(_advice_lines)" == *SEC004* && "$(_model_text)" != *"never silenced"* && "$(_model_text)" != *"No marker silences SEC004"* ]]
expect "SEC004 is ignorable: it is offered its marker, not told no SEC rule takes one" $? "rc=$RC $(_flat)"

for spread in a b c; do _post "src/ui/pay-$spread.ts" "$SECRET_TS"; done
[[ "$RC" -eq 2 && -z "$(_advice_lines)" ]]
expect "SEC001 across files: the project-wide pattern offers no global marker" $? "rc=$RC $(_flat)"

printf 'rules:\n  SEC001: warn\n' > "$WORK/src/relaxed/.craft-rules.yml"
_post "src/relaxed/pay.ts" "$SECRET_TS"
[[ "$RC" -eq 0 && "$(_model_text)" == *SEC001* && -z "$(_advice_lines)" && "$(_model_text)" == *"No marker silences SEC001"* ]]
expect "SEC001 relaxed to warn: the warning actions offer no marker either" $? "rc=$RC $(_flat)"

echo ""
echo "--- the subagent gate honours the manifest like the write gates ---"
printf '%s // craftsman-ignore: SEC001\n' "$SECRET_TS" > "$WORK/src/ui/marked.ts"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' \
    "$WORK/src/ui/marked.ts" > "$WORK/transcript.jsonl"
SQG=$(jq -n --arg t "$WORK/transcript.jsonl" --arg c "$WORK" '{agent_type:"architect", agent_transcript_path:$t, cwd:$c}' \
    | HOME="$WORK/home" bash "$ROOT_DIR/hooks/subagent-quality-gate.sh" 2>/dev/null)
[[ "$SQG" == *SEC001* ]]
expect "a craftsman-ignore marker does not hide SEC001 from the subagent gate" $? "out=${SQG:0:160}"

echo ""
echo "--- the doctrine and the config gate say the same ---"
mkdir -p "$WORK/export" && ( cd "$WORK/export" && git init -q . && bash "$ROOT_DIR/ci/craftsman-ci.sh" export --target agents-md >/dev/null 2>&1 )
DOCTRINE=$(cat "$WORK/export/AGENTS.md" 2>/dev/null)
[[ "$DOCTRINE" == *'**SEC001** (block, no marker)'* && "$DOCTRINE" == *'**SEC004** (block):'* && "$DOCTRINE" == *'`no marker`'* ]]
expect "AGENTS.md marks the rules no marker silences, and says what that means" $? "$(printf '%s' "$DOCTRINE" | grep -E 'SEC00[14]|craftsman-ignore' | tr '\n' ' ')"

_run config-protection.sh PreToolUse ".eslintrc.json" '{"rules":{}}'
[[ "$RC" -eq 2 && "$(_advice_lines)" == *"where the rule allows it"* ]]
expect "config-protection offers the marker only where the rule allows it" $? "rc=$RC $(_flat)"

test_summary
