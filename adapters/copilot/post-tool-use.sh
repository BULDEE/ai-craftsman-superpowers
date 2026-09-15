#!/usr/bin/env bash
# =============================================================================
# Copilot postToolUse adapter: validate what landed, hand the findings back.
#
# The core's post-write-check.sh runs on the translated payload. Its verdict
# reaches the model as the documented `additionalContext` (appended to the
# tool output, capped at 10 KB by the host); a blocking finding is also on
# stderr and the exit code is 2, which the reference logs as a warning and
# continues, since a landed write cannot be undone here either.
# =============================================================================
set -uo pipefail
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}"

INPUT=$(cat)
CORE=$(printf '%s' "$INPUT" | python3 "$ADAPTER_DIR/translate.py" 2>/dev/null) || exit 0
TOOL=$(printf '%s' "$CORE" | jq -r '.tool_name // empty')
case "$TOOL" in Write|Edit|apply_patch) ;; *) exit 0 ;; esac

RC=0
ERR=$(printf '%s' "$CORE" | bash "$PLUGIN_ROOT/hooks/post-write-check.sh" 2>&1 >/tmp/craftsman-copilot-post.$$) || RC=$?
OUT=$(cat "/tmp/craftsman-copilot-post.$$" 2>/dev/null); rm -f "/tmp/craftsman-copilot-post.$$"
CONTEXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // .systemMessage // empty' 2>/dev/null)
if [[ "$RC" -eq 2 ]]; then
    CONTEXT="${ERR}"
fi
if [[ -n "$CONTEXT" ]]; then
    jq -n --arg c "$CONTEXT" '{additionalContext: $c}'
fi
[[ "$RC" -eq 2 ]] && { printf '%s\n' "$ERR" >&2; exit 2; }
exit 0
