#!/usr/bin/env bash
# =============================================================================
# Hermes pre_tool_call adapter: the write-time promise, opt-in (#21)
#
# The README headline is "refuses the write before it reaches disk", and on
# Hermes the gate refuses the CONCLUSION (pre-verify.sh): blocking a write
# assumes somebody can break the loop it creates, and an autonomous agent has
# nobody. That stays the default. This hook is the opt-in exception for the
# findings no retry budget should ever let reach disk, and for nothing else:
#
#   LAYER001         Domain importing Infrastructure
#   SEC001 to SEC003 a hardcoded secret, data executed as code, SQL built by
#                    concatenation
#
# Everything else waits for the conclusion gate, which reports it with the
# advisory channel and the skill to apply. A write blocked here says so, and
# names the rule, so the agent rewrites the content rather than the plan.
#
#   stdin   {"tool_name":"write_file","args":{"path":"...","content":"..."},"cwd":"..."}
#           {"tool_name":"patch","args":{"path":"...","old_string":"...","new_string":"...","replace_all":false},"cwd":"..."}
#           (Hermes passes tool_name and args to a plugin hook; a shell hook
#            receives the same fields as JSON on stdin.)
#   stdout  {"action":"block","message":"..."}   refuse the write
#           nothing                                let it through
#
# Measured in the hermes-agent source (tools/file_tools.py): write_file takes
# path and content, patch takes path, old_string, new_string and replace_all.
# Only those two tools mutate a file through a tool; a write through
# `terminal` (sed -i, tee, a redirect) is invisible here by construction and
# is what the conclusion gate's git-derived scope exists to catch.
#
# Install as a shell hook (Path 1, ~/.hermes/config.yaml), or set
# `write_gate: on` in the plugin config (Path 0):
#   hooks:
#     pre_tool_call:
#       - matcher: "write_file|patch"
#         command: "/opt/craftsman/adapters/hermes/pre-tool-call.sh"
#         timeout: 20
#         fail_closed: true
# Try it: `hermes hooks test pre_tool_call`.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
CRAFTSMAN_CI="$PLUGIN_ROOT/ci/craftsman-ci.sh"

# The rules this hook may refuse a write on. A finding outside this set is
# never reported here, whatever its severity: that is the promise the default
# makes to an agent with no human to break its loop.
WRITE_GATE_RULES="LAYER001 SEC001 SEC002 SEC003"

# fail_closed is a decision the operator makes in config.yaml; this script's
# own failure is reported as a block so the operator's choice is what applies,
# and a silent pass never hides a gate that did not run.
_bail() {
    echo "craftsman pre_tool_call: $1" >&2
    python3 -c '
import json, sys
print(json.dumps({"action": "block", "message": "The craftsman write gate could not run (" + sys.argv[1] + "). Retry the write once; if it repeats, the gate needs attention, not the write."}, ensure_ascii=False))
' "$1" 2>/dev/null
    exit 0
}
trap '_bail "aborted at line $LINENO"' ERR

command -v python3 >/dev/null 2>&1 || _bail "python3 not found"
[[ -f "$CRAFTSMAN_CI" ]] || _bail "craftsman-ci not found at ${CRAFTSMAN_CI}"
source "${PLUGIN_ROOT}/hooks/lib/portable-timeout.sh" 2>/dev/null || true

INPUT=$(cat)

# What the file WOULD contain, laid out under a mirror of the workspace so a
# rule that reads the path (LAYER001 keys on /Domain/) sees the real one, and
# the project's own .craft-config.yml and .craft-rules.yml apply. Prints the
# mirror root and the relative path, or nothing when this is not a write this
# hook judges: another tool, a path outside the workspace, a patch whose
# old_string is not in the file (Hermes will refuse that one itself).
MIRROR=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-write-gate.XXXXXX")
trap 'rm -rf "$MIRROR"' EXIT

PLACED=$(printf '%s' "$INPUT" | python3 -c '
import json, os, sys, shutil

mirror = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
tool = payload.get("tool_name") or ""
args = payload.get("args") or {}
if tool not in ("write_file", "patch") or not isinstance(args, dict):
    sys.exit(0)
cwd = os.path.realpath(payload.get("cwd") or os.getcwd())
path = str(args.get("path") or "")
if not path:
    sys.exit(0)
target = os.path.realpath(os.path.join(cwd, path))
if not (target == cwd or target.startswith(cwd + os.sep)):
    sys.exit(0)
relative = os.path.relpath(target, cwd)

if tool == "write_file":
    content = args.get("content")
    if not isinstance(content, str):
        sys.exit(0)
else:
    old, new = args.get("old_string"), args.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str):
        sys.exit(0)
    try:
        with open(target, encoding="utf-8", errors="replace") as handle:
            current = handle.read()
    except OSError:
        sys.exit(0)
    if old not in current:
        sys.exit(0)
    content = current.replace(old, new) if args.get("replace_all") else current.replace(old, new, 1)

destination = os.path.join(mirror, relative)
os.makedirs(os.path.dirname(destination), exist_ok=True)
with open(destination, "w", encoding="utf-8") as handle:
    handle.write(content)
for name in (".craft-config.yml", ".craft-rules.yml"):
    source = os.path.join(cwd, name)
    if os.path.isfile(source):
        shutil.copy(source, os.path.join(mirror, name))
print(relative)
' "$MIRROR" 2>/dev/null)

[[ -n "$PLACED" ]] || exit 0

GATE_STATUS=0
REPORT=$(cd "$MIRROR" && portable_timeout "${CRAFTSMAN_GATE_SECONDS:-20}" \
    bash "$CRAFTSMAN_CI" --format json "$PLACED" 2>/dev/null) || GATE_STATUS=$?
[[ "$GATE_STATUS" -eq 124 ]] && _bail "gate exceeded ${CRAFTSMAN_GATE_SECONDS:-20}s on ${PLACED}"
[[ -n "$REPORT" ]] || _bail "gate produced no report (exit ${GATE_STATUS})"

printf '%s' "$REPORT" | python3 -c '
import json, sys
try:
    report = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
allowed = set(sys.argv[1].split())
path = sys.argv[2]
hits = [v for v in (report.get("violations") or [])
        if v.get("rule") in allowed and v.get("severity") == "critical"]
if not hits:
    sys.exit(0)
lines = ["{}:{} {} - {}".format(path, v.get("line", 0), v.get("rule", "?"), v.get("message", ""))
         for v in hits]
message = ("craftsman refused this write before it reached disk, on the rules no retry "
           "budget should let through (LAYER001, SEC001-003):\n" + "\n".join(lines)
           + "\nRewrite the content without the finding, then write again. "
           "Every other rule is judged at the conclusion, with the skill that fixes it.")
print(json.dumps({"action": "block", "message": message}, ensure_ascii=False))
' "$WRITE_GATE_RULES" "$PLACED"
exit 0
