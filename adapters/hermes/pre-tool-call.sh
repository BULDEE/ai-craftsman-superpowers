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
#   SEC001    a hardcoded secret: the one finding whose cost is not bounded
#             by waiting, because a secret on disk in an autonomous loop can be
#             committed, pushed or logged before the conclusion, and then it
#             has to be rotated
#   LAYER001  Domain importing Infrastructure: reversible in one line, kept
#             because it is free and keyed on the path, so it has no false
#             positive outside test code; test paths are left to the
#             conclusion, where an in-memory adapter under tests/Domain is
#             the normal shape
#
# Not SEC002 and SEC003, though #21 first named them. Both are line-local
# regexes with no notion of a sanitizer, and they fire on the documented
# mitigation: `exec('git -C ' . escapeshellarg($dir))` (SEC002, escapeshellarg
# is what the PHP manual prescribes), `createQuery('SELECT e FROM ' .
# $this->entityClass . ' e WHERE e.id = :id')` (SEC003, a class name and a
# bound parameter). Telling sanitized from unsanitized data needs taint
# analysis (sources, sanitizers, sinks), which is what psalm and phpstan
# supersede the regex with at Level 2, and no taint run fits the 20s a write
# gets under Hermes's 30s callback cap. At the conclusion those two rules
# block exactly as before, the loop is bounded by max_verify_nudges, and the
# analyser can outrank the regex; at write time they would only teach the
# agent to split a line. The scope is revisited on data: the acceptance
# report (/craftsman:metrics) says whether SEC001 refusals are fixed or
# suppressed.
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
WRITE_GATE_RULES="LAYER001 SEC001"
# LAYER001 is not judged here on a test path: the engine's own notion of one
# (rules-engine.sh, _RULES_TEST_PATH_RE), because a test double in memory
# under tests/Domain imports Infrastructure by design.
WRITE_GATE_TEST_PATH_RE='(^|/)(tests?|spec|__tests__|__mocks__|fixtures?|factories)(/|$)'

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
import json, re, sys
try:
    report = json.load(sys.stdin)
except (ValueError, TypeError):
    sys.exit(0)
allowed = set(sys.argv[1].split())
path = sys.argv[2]
if re.search(sys.argv[3], path):
    allowed.discard("LAYER001")
hits = [v for v in (report.get("violations") or [])
        if v.get("rule") in allowed and v.get("severity") == "critical"]
if not hits:
    sys.exit(0)
print("\n".join("{}:{} {} - {}".format(path, v.get("line", 0), v.get("rule", "?"), v.get("message", ""))
                for v in hits))
' "$WRITE_GATE_RULES" "$PLACED" "$WRITE_GATE_TEST_PATH_RE")

[[ -n "$VERDICT" ]] || exit 0
_block "craftsman refused this write before it reached disk, on the rules no retry budget should let through (SEC001, LAYER001):
${VERDICT}
Rewrite the content without the finding, then write again: a secret is read from the environment or a vault, never written; a Domain class does not import Infrastructure. If a LAYER001 finding is wrong for this file, \`craftsman-ignore: LAYER001\` in a comment on that line is honoured. Every other rule is judged at the conclusion, with the skill that fixes it."
