#!/usr/bin/env bash
# =============================================================================
# Copilot preToolUse adapter: the write gate, on the documented envelope.
#
# Translates the Copilot payload (translate.py), then runs the two core gates
# a Claude Code PreToolUse runs, config-protection.sh and pre-write-check.sh,
# and answers in the documented Copilot form: exit 2 with a top-level
# `permissionDecision: deny` (exit 2 "is treated as deny" for preToolUse on
# both surfaces; `ask` is deny under the cloud agent, and the core never asks
# a host it cannot name as Claude Code). A gate that cannot run denies: a
# non-zero exit fails closed for preToolUse, which is the documented default
# and the plugin's own rule (ADR-0029). The one thing this script cannot
# repair is a TIMEOUT, which the reference says always fails open, so the
# hooks file keeps timeoutSec well above the gates' measured latency.
#
# The matcher is applied by the adapter too: Copilot's PascalCase matchers
# map `create` to Write and `edit`/`str_replace_editor` to Edit, but a
# surface that ignores matchers (VS Code, per its own docs) would send every
# tool here, so a tool that is not a write returns at once.
# =============================================================================
set -uo pipefail
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}"
# Copilot's data (metrics, registry cache, session files) lives in its own
# directory; unset, the core fell back to Claude Code's ~/.claude tree
# (independent verification, 2026-09-15). Ephemeral in the cloud agent.
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${CRAFTSMAN_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/craftsman/copilot}}"
mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null || true

_deny() {
    printf '%s\n' "$1" >&2
    jq -n --arg r "$1" '{permissionDecision: "deny", permissionDecisionReason: $r}'
    exit 2
}

INPUT=$(cat)
WHY=$(mktemp "${TMPDIR:-/tmp}/craftsman-copilot-why.XXXXXX") || _deny "craftsman: no temporary file; the write is refused, not waved through"
trap 'rm -f "$WHY"' EXIT
CORE=$(printf '%s' "$INPUT" | python3 "$ADAPTER_DIR/translate.py" 2>"$WHY") || _deny "$(cat "$WHY" 2>/dev/null || echo "craftsman: the Copilot payload could not be translated"); the write is refused, not waved through"
TOOL=$(printf '%s' "$CORE" | jq -r '.tool_name // empty')
case "$TOOL" in Write|Edit|apply_patch) ;; *) exit 0 ;; esac

ALLOW_OUT=""
for gate in config-protection.sh pre-write-check.sh; do
    RC=0
    GATE_OUT=$(printf '%s' "$CORE" | bash "$PLUGIN_ROOT/hooks/$gate" 2>"$WHY") || RC=$?
    if [[ "$RC" -ne 0 ]]; then
        _deny "$(cat "$WHY" 2>/dev/null || echo "craftsman: $gate refused the write (exit $RC)")"
    fi
    [[ "$gate" == "pre-write-check.sh" ]] && ALLOW_OUT="$GATE_OUT"
done

# pre-write-check.sh may allow WITH a corrected content (a Write missing only
# declare(strict_types=1) comes back as updatedInput, ADR-0018). Dropping it
# let the uncorrected file land as allowed (review of 84b2350, F3): the
# correction is translated back into the tool's own argument name and
# returned as the documented `modifiedArgs`.
FIXED=$(printf '%s' "$ALLOW_OUT" | jq -r '.hookSpecificOutput.updatedInput.content // empty' 2>/dev/null)
if [[ -n "$FIXED" ]]; then
    printf '%s' "$INPUT" | jq --arg c "$FIXED" '
        (if has("tool_input") then .tool_input else (.toolArgs | if type == "string" then fromjson else . end) end) as $args
        | ($args | if has("file_text") then .file_text = $c elif has("content") then .content = $c else .content = $c end) as $fixed
        | {permissionDecision: "allow", permissionDecisionReason: "craftsman: declare(strict_types=1) inserted (PHP001)", modifiedArgs: $fixed}'
fi
exit 0
