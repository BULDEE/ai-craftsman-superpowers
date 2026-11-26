#!/usr/bin/env bash
# =============================================================================
# End-of-turn Gate (CR-259)
# Stop hook, synchronous. A post-write refusal comes after the write landed:
# the model reads "BLOCKED", and nothing brought it back to the file before it
# reported the work done. The turn does not end while a blocking finding a
# write of this session left on disk is still there.
#
# Reads the session state alone: `landed_violations`, which only post-write
# fills, replaced on every write of the file. A refusal of the pre-write gate
# never landed and is not in it, and a finding the file held before the
# session is held back (CR-306) before it gets there.
#
# Strictness-aligned: block in strict, warn in moderate, silent in relaxed.
# stop_hook_active means the turn was already sent back once: the second stop
# is shown to the user, never looped (Claude Code also overrides a block after
# 8 continuations without a tool call).
#
# EXIT CODES: 0 always; the decision is the JSON on stdout.
# =============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/exported-gate.sh" # one gate per write on Grok (CR-310)

trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Is this file in the checkout the session works in? A finding a SUBAGENT left
# in another git worktree is owed to that worktree's own judge (a factory job's
# gate, a CI run), not to the session that dispatched the agent: an
# orchestrator told to "fix each one" was being asked to write code it must
# not touch. Outside a repository there is one checkout: the answer is yes,
# and the gate holds as it always did.
_same_checkout() { # <file> <cwd>
    local mine theirs
    mine=$(git -C "$2" rev-parse --show-toplevel 2>/dev/null) || return 0
    theirs=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || return 0
    [[ "$mine" == "$theirs" ]]
}

# One "<file>: <rules>" line per file still on disk, the path relative to the
# project when it is under it. `landed_agents` names the subagent that wrote
# the file, empty for the session's own agent, whose findings are always held.
_open_findings() { # <state> <cwd>
    local file rules agent
    while IFS=$'\t' read -r file rules agent; do
        [[ -n "$file" && -f "$file" ]] || continue
        [[ -z "$agent" ]] || _same_checkout "$file" "$2" || continue
        printf -- '- %s: %s\n' "${file#"$2"/}" "$rules"
    done <<< "$(jq -r '(.landed_agents // {}) as $agents | .landed_violations // {} | to_entries[]
        | select(.value | length > 0) | "\(.key)\t\(.value | join(", "))\t\($agents[.key] // "")"' "$1" 2>/dev/null)"
}

# Every turn ends here, so the common case, nothing open, exits on the session
# state before the config is read.
INPUT=$(cat)
source "${SCRIPT_DIR}/lib/session-files.sh"
session_files_bind "$INPUT"
SESSION_STATE=$(session_file session-state.json)
[[ -n "$SESSION_STATE" && -f "$SESSION_STATE" ]] || exit 0
grep -q '"landed_violations"' "$SESSION_STATE" 2>/dev/null || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD=$(cd "${CWD:-$PWD}" 2>/dev/null && pwd -P) || CWD="$PWD"
OPEN=$(_open_findings "$SESSION_STATE" "$CWD")
[[ -z "$OPEN" ]] && exit 0

source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/hook-profile.sh"
hook_profile_should_run "end-of-turn-gate" "standard,strict" || exit 0
STRICTNESS=$(config_strictness)
[[ "$STRICTNESS" == "relaxed" ]] && exit 0

if [[ "$STRICTNESS" == "strict" && "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" != "true" ]]; then
    # The marker is spelled in two parts: written whole, this file would count
    # as carrying one (ratchet `ignores`).
    jq -n --arg open "$OPEN" --arg marker "craftsman-""ignore" '{decision: "block", reason: ("Blocking findings that writes of this session left on disk are still there:\n" + $open + "\nFix each one before you end the turn. If one must stay, say why on its line with `" + $marker + ": <RULE> (debt: why it stays)`: the write that adds the marker is judged again. If the user asked to keep it, say so in your report.")}'
    exit 0
fi
jq -n --arg open "$OPEN" '{systemMessage: ("craftsman: this turn ends with blocking findings still on disk:\n" + $open)}'
exit 0
