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

# A hook that dies must not stop the agent, and must not look like a verdict.
trap 'exit 0' ERR

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
CRAFTSMAN_CI="${PLUGIN_ROOT}/ci/craftsman-ci.sh"

command -v python3 >/dev/null 2>&1 || exit 0
[[ -x "$CRAFTSMAN_CI" || -f "$CRAFTSMAN_CI" ]] || exit 0

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

COMPILED_PATHS=$(_field changed_paths)
CODING=$(_field coding)
CWD=$(_field cwd)

# Scope like a pre_tool_call hook scopes on tool_name: a non-coding session has
# nothing for this gate to say.
[[ "$CODING" == "True" || "$CODING" == "true" ]] || exit 0
[[ -n "$COMPILED_PATHS" ]] || exit 0

[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD"

# Only the files this turn touched, and only those still on disk.
SCAN_PATHS=()
while IFS= read -r path; do
    [[ -n "$path" && -f "$path" ]] && SCAN_PATHS+=("$path")
done <<< "$COMPILED_PATHS"
[[ ${#SCAN_PATHS[@]} -gt 0 ]] || exit 0

REPORT=$(bash "$CRAFTSMAN_CI" --format json "${SCAN_PATHS[@]}" 2>/dev/null) || true
[[ -n "$REPORT" ]] || exit 0

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
