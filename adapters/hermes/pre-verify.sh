#!/usr/bin/env bash
# =============================================================================
# Hermes pre_verify adapter
#
# Hermes fires pre_verify once per turn, when the agent edited code and is about
# to conclude. A hook keeps that turn going by printing a directive on stdout.
# The exit code carries nothing: Hermes logs a non-zero exit and continues
# (agent/shell_hooks.py), so the verdict travels as JSON or not at all.
#
#   stdin   {"hook_event_name":"pre_verify","session_id":"...","cwd":"...",
#            "extra":{"changed_paths":[...],"coding":true,"attempt":0,...}}
#   stdout  {"decision":"block","reason":"..."}    Claude-Code shape
#           {"action":"continue","message":"..."}  Hermes-canonical, equivalent
#
# Hermes accepts either and takes the first directive carrying a non-empty
# message (hermes_cli/plugins.py:get_pre_verify_continue_message).
#
# Why this event and not pre_tool_call: blocking a write assumes someone can
# break the loop it creates. An autonomous agent has nobody. Refusing a
# conclusion does not trap anything, and Hermes bounds the retries itself
# through agent.max_verify_nudges, so the agent always gets to finish.
#
# jq is absent from the nousresearch/hermes-agent image; python3 is present.
# Parsing goes through python3 for that reason, not by preference.
#
# Install (~/.hermes/config.yaml):
#   hooks:
#     pre_verify:
#       - command: "/opt/craftsman/adapters/hermes/pre-verify.sh"
#         timeout: 60
# =============================================================================
set -uo pipefail

# A hook that dies must not stop the agent, and must not look like a clean
# file. Every exit below says why on stderr, which Hermes logs: silence must
# only ever mean "the gate ran and found nothing".
trap '_bail "aborted at line $LINENO"' ERR

# A gate that could not run is not a clean file. stderr goes to a container log
# nobody reads in an autonomous loop, so a failure that only writes there
# removes the gate without removing the appearance of one. The turn is blocked
# instead, which traps nothing: Hermes bounds the retries with
# agent.max_verify_nudges, the same argument that put this hook on pre_verify.
_bail() {
    echo "craftsman/hermes: $1" >&2
    python3 -c '
import json, sys
print(json.dumps({"decision": "block",
                  "reason": "The craftsman gate could not run (" + sys.argv[1]
                            + "). Do not conclude until it does."},
                 ensure_ascii=False))
' "$1" 2>/dev/null
    exit 0
}

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
CRAFTSMAN_CI="${PLUGIN_ROOT}/ci/craftsman-ci.sh"

command -v python3 >/dev/null 2>&1 || _bail "python3 not found, gate not run"
[[ -f "$CRAFTSMAN_CI" ]] || _bail "craftsman-ci not found at ${CRAFTSMAN_CI}, gate not run"
source "${PLUGIN_ROOT}/hooks/lib/portable-timeout.sh" 2>/dev/null || true

INPUT=$(cat)

# Emit a directive and stop. Both shapes are accepted upstream; the Claude-Code
# one is used so the same verdict text serves this adapter and the Stop hook.
_verdict() {
    python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}, ensure_ascii=False))
' "$1"
    exit 0
}

# Fields the event carries, one per line, empty when absent.
_field() {
    printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
extra = payload.get("extra") or {}
key = sys.argv[1]
value = payload.get(key, extra.get(key))
if isinstance(value, list):
    print("\n".join(str(item) for item in value))
elif value is not None:
    print(value)
' "$1" 2>/dev/null
}

HINTED_PATHS=$(_field changed_paths)
CODING=$(_field coding)
CWD=$(_field cwd)

# Scope like a pre_tool_call hook scopes on tool_name: a non-coding session has
# nothing for this gate to say.
[[ "$CODING" == "True" || "$CODING" == "true" ]] || exit 0
[[ -n "$CWD" && -d "$CWD" ]] || _bail "no usable cwd in the payload, gate not run"
cd "$CWD" || _bail "cannot enter ${CWD}, gate not run"

# The payload is a hint, never the truth.
#
# Hermes collects changed_paths from the tool name, not from the filesystem:
# agent/tool_dispatch_helpers.py returns [] for anything outside
# FILE_MUTATING_TOOL_NAMES, and only write_file and patch are in it. A write
# through `terminal` (sed -i, python -c, tee, a redirect, git apply) never
# reaches the list, so a gate that trusted it would miss every file written
# that way. Scope comes from git, with the payload merged in for a workspace
# that is not a repository.
# The worktree is not the whole turn. An autonomous agent commits, and a
# committed violation left the worktree clean and the gate silent: everything
# it had just written escaped the scan. The branch point is included so the
# turn is judged on what it produced, not on what it has not tidied away yet.
_diff_base() {
    local base
    for base in "${CRAFTSMAN_DIFF_BASE:-}" "@{u}" "origin/HEAD" "origin/main" "origin/master"; do
        [[ -n "$base" ]] || continue
        git merge-base "$base" HEAD 2>/dev/null && return 0
    done
    return 1
}

_git_scope() {
    git rev-parse --show-toplevel >/dev/null 2>&1 || return 0
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
    local base
    base=$(_diff_base) && git diff --name-only "$base"..HEAD 2>/dev/null
    return 0
}

# Contained to the workspace: an absolute or traversing path in the payload
# would drag host files into the report.
SCAN_PATHS=()
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    # Relative on the way out as well as contained on the way in: an absolute
    # path in the directive would put the host's directory structure into the
    # model's context for no benefit.
    resolved=$(python3 -c '
import os, sys
root = os.path.realpath(sys.argv[1])
target = os.path.realpath(os.path.join(root, sys.argv[2]))
inside = target == root or target.startswith(root + os.sep)
print(os.path.relpath(target, root) if inside else "")
' "$CWD" "$path" 2>/dev/null)
    [[ -n "$resolved" && -f "$resolved" ]] || continue
    case " ${SCAN_PATHS[*]:-} " in *" $resolved "*) continue ;; esac
    SCAN_PATHS+=("$resolved")
done <<< "$(printf '%s\n%s\n' "$(_git_scope)" "$HINTED_PATHS")"

[[ ${#SCAN_PATHS[@]} -gt 0 ]] || exit 0

# Hermes kills the hook at its configured timeout, and a kill is
# indistinguishable from a pass. Bound it here so the adapter can say so.
GATE_STATUS=0
REPORT=$(portable_timeout "${CRAFTSMAN_GATE_SECONDS:-45}" \
    bash "$CRAFTSMAN_CI" --format json "${SCAN_PATHS[@]}" 2>/dev/null) || GATE_STATUS=$?
[[ "$GATE_STATUS" -eq 124 ]] && _bail "gate exceeded ${CRAFTSMAN_GATE_SECONDS:-45}s on ${#SCAN_PATHS[@]} file(s), verdict unknown"
[[ -n "$REPORT" ]] || _bail "gate produced no report (exit ${GATE_STATUS}), verdict unknown"

SUMMARY=$(printf '%s' "$REPORT" | python3 -c '
import json, sys
try:
    report = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
violations = report.get("violations") or []
blocking = [v for v in violations if v.get("severity") == "critical"]
if not blocking:
    sys.exit(0)
lines = [
    "{}:{} {} - {}".format(v.get("file", "?"), v.get("line", 0), v.get("rule", "?"), v.get("message", ""))
    for v in blocking[:10]
]
more = len(blocking) - len(lines)
if more > 0:
    lines.append("and {} more".format(more))
print("The craftsman gate rejects this change, so it is not finished:\n" + "\n".join(lines)
      + "\nFix these and say what you ran to prove it.")
' 2>/dev/null)

[[ -n "$SUMMARY" ]] && _verdict "$SUMMARY"
exit 0
