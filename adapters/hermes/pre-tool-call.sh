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
# advisory channel and the skill to apply. A write blocked here says so, names
# the rule, and says how to get out (rewrite, or `craftsman-ignore: RULE` on
# the line when the finding is wrong), so the agent rewrites the content
# rather than the plan.
#
#   stdin   plugin form  {"tool_name":"write_file","args":{"path":"...","content":"..."},"cwd":"..."}
#           shell form   {"hook_event_name":"pre_tool_call","tool_name":"patch",
#                         "tool_input":{"path":"...","old_string":"...","new_string":"..."},
#                         "session_id":"...","cwd":"...","extra":{...}}
#           Hermes puts the tool arguments under `tool_input` on the shell
#           wire (agent/shell_hooks.py, _payload_fields) and hands a plugin
#           hook `args`; both are read. No `cwd` reaches a plugin hook and
#           the shell one is the Hermes process's, not the task's, so the
#           workspace is derived from the written path itself (see below).
#   stdout  {"action":"block","message":"..."}   refuse the write
#           nothing                                let it through
#
# Measured in the hermes-agent source (tools/file_tools.py): write_file takes
# path and content; patch takes path, old_string, new_string, replace_all, and
# applies old_string through a chain of fuzzy strategies (tools/fuzzy_match.py),
# and the handler also accepts a V4A patch (`mode: patch`) from any model,
# which this gate refuses rather than reads. Only those two tools mutate a
# file through a tool; a write through
# `terminal` (sed -i, tee, a redirect) is invisible here by construction and
# is what the conclusion gate's git-derived scope exists to catch.
#
# Install as a shell hook (Path 1, ~/.hermes/config.yaml), or set
# `write_gate: on` in the plugin config (Path 0):
#   hooks:
#     pre_tool_call:
#       - matcher: "write_file|patch"
#         command: "/opt/craftsman/adapters/hermes/pre-tool-call.sh"
#         timeout: 30        # above the script's own 20s bound, so a kill is never mistaken for a pass
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

# A block written with printf, not python3: the one failure this script must
# be able to report is python3 being absent, and a bail that needs python3 to
# say so is a silent pass. Exit 2 as well, which is the shell-wire block
# Hermes reads even when the JSON is not parsed (agent/shell_hooks.py:
# exit 2 blocks with stderr as the message).
_block() {
    local message="$1"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    message="${message//$'\n'/\\n}"
    printf '{"action": "block", "message": "%s"}\n' "$message"
    echo "$1" >&2
    exit 2
}

# Two failures, two messages. Infrastructure that is missing repeats on every
# write of every session and no agent can repair it: say so, and say not to
# retry. A verdict that failed on THIS file (a timeout, a crash of the scan)
# is worth one retry, which is the rule the conclusion gate applies too.
_bail_infra() {
    _block "The craftsman write gate cannot run at all ($1). Every write will be refused until the operator repairs this; do not retry, report it."
}
_bail_file() {
    _block "The craftsman write gate could not judge this file ($1). Retry the write once; if it repeats, the gate needs attention, not the write."
}
trap '_bail_file "aborted at line $LINENO"' ERR

command -v python3 >/dev/null 2>&1 || _bail_infra "python3 not found"
[[ -f "$CRAFTSMAN_CI" ]] || _bail_infra "craftsman-ci not found at ${CRAFTSMAN_CI}"
source "${PLUGIN_ROOT}/hooks/lib/portable-timeout.sh" 2>/dev/null || true

INPUT=$(cat)

# What the file WOULD contain, laid out under a mirror of its workspace so a
# rule that reads the path (LAYER001 keys on /Domain/) sees the real one, and
# the workspace's own .craft-config.yml and .craft-rules.yml apply.
#
# The workspace is the written path's own: walked up from the target to the
# nearest marker (.git, .craft-config.yml, composer.json, package.json,
# pyproject.toml, go.mod, Cargo.toml). Hermes hands a plugin hook no cwd, and
# the shell hook's cwd is the Hermes process's, which in gateway mode is not
# the task's directory: anchoring on it judged the first turn of a session,
# the one where the agent writes the most, against the wrong tree or not at
# all. A path with no marker above it is judged under its own directory: the
# four rules need the path suffix and the content, nothing more.
#
# Prints one of:
#   MIRROR <relative path>   judge this file in the mirror
#   GATE <relative path>     the write reconfigures the gate itself
#   UNJUDGED <why>           a form this gate cannot read (a V4A patch, a
#                            relative path with no workspace): refused, never
#                            waved, with the form to use instead
#   nothing                  not a write this hook judges (another tool)
MIRROR=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-write-gate.XXXXXX")
trap 'rm -rf "$MIRROR"' EXIT

PLACED=$(printf '%s' "$INPUT" | python3 "$SCRIPT_DIR/write_gate_place.py" "$MIRROR" 2>/dev/null)

[[ -n "$PLACED" ]] || exit 0

case "$PLACED" in
    GATE\ *)
        _block "This write edits the craftsman gate's own configuration (${PLACED#GATE }). The gated party does not reconfigure the gate: change the rules through a reviewed commit instead."
        ;;
    UNJUDGED\ *)
        # A form this gate cannot read is not a pass: an operator who opted in
        # asked for fail-closed on these rules, and the message names the form
        # that is judged.
        _block "The craftsman write gate cannot judge this write: ${PLACED#UNJUDGED }."
        ;;
esac
PLACED="${PLACED#MIRROR }"

GATE_STATUS=0
REPORT=$(cd "$MIRROR" && portable_timeout "${CRAFTSMAN_GATE_SECONDS:-20}" \
    bash "$CRAFTSMAN_CI" --format json "$PLACED" 2>/dev/null) || GATE_STATUS=$?
[[ "$GATE_STATUS" -eq 124 ]] && _bail_file "gate exceeded ${CRAFTSMAN_GATE_SECONDS:-20}s on ${PLACED}"
[[ -n "$REPORT" ]] || _bail_file "gate produced no report (exit ${GATE_STATUS})"

VERDICT=$(printf '%s' "$REPORT" | python3 -c '
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
print("\n".join("{}:{} {} - {}".format(path, v.get("line", 0), v.get("rule", "?"), v.get("message", ""))
                for v in hits))
' "$WRITE_GATE_RULES" "$PLACED")

[[ -n "$VERDICT" ]] || exit 0
_block "craftsman refused this write before it reached disk, on the rules no retry budget should let through (LAYER001, SEC001-003):
${VERDICT}
Rewrite the content without the finding, then write again. If the finding is wrong for this line (a test fixture, a query that is in fact bound), put \`craftsman-ignore: <RULE>\` in a comment on that line and it is honoured. Every other rule is judged at the conclusion, with the skill that fixes it."
