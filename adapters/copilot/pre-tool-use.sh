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

_deny() {
    printf '%s\n' "$1" >&2
    jq -n --arg r "$1" '{permissionDecision: "deny", permissionDecisionReason: $r}'
    exit 2
}

INPUT=$(cat)
CORE=$(printf '%s' "$INPUT" | python3 "$ADAPTER_DIR/translate.py" 2>/dev/null) || _deny "craftsman: the Copilot payload could not be translated; the write is refused, not waved through"
TOOL=$(printf '%s' "$CORE" | jq -r '.tool_name // empty')
case "$TOOL" in Write|Edit|apply_patch) ;; *) exit 0 ;; esac

for gate in config-protection.sh pre-write-check.sh; do
    RC=0
    OUT=$(printf '%s' "$CORE" | bash "$PLUGIN_ROOT/hooks/$gate" 2>&1 >/dev/null) || RC=$?
    if [[ "$RC" -ne 0 ]]; then
        _deny "${OUT:-craftsman: $gate refused the write (exit $RC)}"
    fi
done
exit 0
