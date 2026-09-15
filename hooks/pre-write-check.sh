#!/usr/bin/env bash
# =============================================================================
# Pre-Write/Edit Validation Hook for Claude Code
# Validates BEFORE file is written: layer imports, path conventions.
#
# TRIGGERS: PreToolUse for Write and Edit tools
# EXIT CODES: 0 = allow, 2 = block with reason
# =============================================================================
set -uo pipefail

# A gate that cannot run is not a clean verdict (ADR-0029, which the Hermes
# adapter honoured and this hook did not: a crash here used to exit 0 and let
# the write land). Refused, with the line and the retry advice. Malformed or
# empty input is not a crash: it names no file, and the read below tolerates
# it so that nothing is refused for nothing.
trap 'echo "The craftsman pre-write gate could not run (pre-write-check.sh, line $LINENO). Retry the write once; if it repeats, the gate needs attention, not the write." >&2; exit 2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
# Severity is the rules engine's decision, resolved per file (CLAUDE.md).
# This hook used to resolve it through config.sh's strictness table and a
# hand-kept advisory list instead: the same file, rule and .craft-rules.yml
# gave "BLOCKED" before the write and nothing after it, two verdicts inside
# one front-end, and the parity suite could not see it because it ran the
# relaxation case through post-write only.
source "${SCRIPT_DIR}/lib/rules-engine.sh"
rules_init "$PWD" "$(rules_global_dir)"
# Needed for the language registry: which extensions are source files is the
# packs' answer, not this hook's. The registry is cached on disk, so the extra
# load costs a file read on the steady path.
source "${SCRIPT_DIR}/lib/pack-loader.sh"

# Read tool input from stdin
INPUT=$(cat)
command -v jq >/dev/null 2>&1 || false
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# A Write/Edit names its file here. A Codex apply_patch names its files inside
# `tool_input.command` and has no `file_path`: exiting on the missing field
# waved every patch through (audit CR-117, C1). The mirror helper reads both
# shapes; only a call that names no file at all is not this gate's.
[[ -z "$FILE_PATH" && "$TOOL_NAME" != "apply_patch" ]] && exit 0

# The whole content a write carries, when it carries one. It feeds the PHP001
# auto-fix below and nothing else: the would-be file the validators judge is
# laid out by the mirror helper, for every shape (a Write, an Edit applied to
# the file on disk, a patch), so the edit branch that used to be computed here
# fed nobody. Read with jq, no interpreter start on the common path.
FILE_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)

# Only check source files, as declared by the loaded packs. A patch is
# filtered per file below, since it may name several languages at once.
pack_loader_init
LANG_ID=""
if [[ -n "$FILE_PATH" ]]; then
    LANG_ID=$(lang_for_file "$FILE_PATH")
    [[ -z "$LANG_ID" ]] && exit 0
fi

VIOLATIONS=""
VIOLATION_COUNT=0

# =============================================================================
# The would-be file, judged by the packs themselves
#
# These detectors used to be a fork of the pack validators, written for the
# content in hand: "App" hardcoded where packs/symfony reads composer.json's
# psr-4 root, path-only where the pack is path-or-namespace, PHP001 only on a
# file declaring a class. Measured: an Acme\ project passed here and was
# refused post-write on the same file, two verdicts inside one front-end.
#
# The content is laid out under a mirror of its workspace (hooks/lib/
# write_mirror.py, shared with the Hermes write gate) with the rule files,
# the namespace roots and the baseline mark the engine reads for it, and the
# same pack validators post-write and CI run are run on the mirror. One set
# of detectors; the shims below are post-write's emit contract without the
# metrics, the precedence hold and the Level 2/3 analysers, none of which
# belong before a write.
# =============================================================================
MIRROR=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-pre-write.XXXXXX")
trap 'rm -rf "$MIRROR"' EXIT
# A relative file_path is relative to the session's working directory, which
# is this hook's; the helper is told, since the payload does not carry it.
PLACED=$(printf '%s' "$INPUT" | jq --arg cwd "$PWD" '. + {cwd: (.cwd // $cwd)}' 2>/dev/null \
    | python3 "${SCRIPT_DIR}/lib/write_mirror.py" "$MIRROR" 2>/dev/null); PLACED_RC=$?
# A helper that crashed placed nothing, and nothing is not a pass (ADR-0029;
# review F3: `|| true` here let a missing python3 wave every write through).
if [[ "$PLACED_RC" -ne 0 ]]; then
    echo "🚫 BLOCKED by AI Craftsman - the pre-write gate could not lay out the would-be file (write_mirror.py exit ${PLACED_RC}). Retry the write once; if it repeats, the gate needs attention, not the write." >&2
    jq -n --arg rc "$PLACED_RC" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: ("the pre-write gate could not lay out the would-be file (write_mirror.py exit " + $rc + "); retry once, then report the gate")}}'
    exit 2
fi
# One `MIRROR <relative path>` per would-be file (one for a Write/Edit, any
# number for a patch). GATE lines are config-protection.sh's to refuse. An
# UNJUDGED line is a write this gate could not read (an unplaceable hunk, a
# relative path with no workspace) and is refused here, with the reason: an
# unread mutation is not a pass.
UNJUDGED=$(printf '%s\n' "$PLACED" | awk '/^UNJUDGED /{print substr($0, 10); exit}')
if [[ -n "$UNJUDGED" ]]; then
    echo "🚫 BLOCKED by AI Craftsman - the write cannot be judged before it lands: ${UNJUDGED}" >&2
    jq -n --arg why "$UNJUDGED" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: ("the write cannot be judged before it lands: " + $why)}}'
    exit 2
fi
MIRROR_FILES=$(printf '%s\n' "$PLACED" | awk '/^MIRROR /{print substr($0, 8)}')
[[ -z "$MIRROR_FILES" ]] && exit 0
MIRROR_FILE_COUNT=$(printf '%s\n' "$MIRROR_FILES" | grep -c .)

# Same order as post-write's add_violation: severity for THIS file, an
# explicit ignore leaves, a marker the rule allows silences, a baseline mark
# demotes to a warning. Findings are keyed by rule, once each.
_rule_marker_honoured() {
    ! { type rule_never_ignorable >/dev/null 2>&1 && rule_never_ignorable "$1"; }
}
line_has_ignore() {
    _rule_marker_honoured "$2" || return 1
    echo "$1" | grep -qE "craftsman-ignore:\s*[^#]*\b${2}\b" 2>/dev/null
}
file_has_ignore() {
    _rule_marker_honoured "$1" || return 1
    grep -qE "craftsman-ignore:\s*[^#]*\b${1}\b" "$MIRROR_FILE" 2>/dev/null
}
BLOCKING_RULES=""
_pre_emit() {
    local rule="$1" message="$2" severity
    severity=$(rules_severity_for_file "$MIRROR_FILE" "$rule")
    [[ "$severity" == "ignore" ]] && return 0
    file_has_ignore "$rule" && return 0
    if rules_baseline_holds "$MIRROR_FILE" "$rule" "$severity"; then
        severity="warn"; message="${message} (already present at the baseline, not blocking)"
    fi
    case " $BLOCKING_RULES " in *" ${MIRROR_REL}:${rule} "*) return 0 ;; esac
    [[ "$severity" == "block" ]] && BLOCKING_RULES="$BLOCKING_RULES ${MIRROR_REL}:${rule}"
    # A patch names several files: the finding says which one.
    [[ "$MIRROR_FILE_COUNT" -gt 1 ]] && message="${message} [${MIRROR_REL#ws[0-9]*/}]"
    VIOLATIONS="${VIOLATIONS}${rule}: ${message}\n"
    ((VIOLATION_COUNT++)) || true
}
add_violation() { _pre_emit "$1" "$2"; }
add_warning()   { _pre_emit "$1" "$2"; }
metrics_record_violation() { :; }
FILE_PATH_REAL="$FILE_PATH"
while IFS= read -r MIRROR_REL; do
    [[ -z "$MIRROR_REL" ]] && continue
    MIRROR_FILE="$MIRROR/$MIRROR_REL"
    LANG_ID=$(lang_for_file "$MIRROR_FILE")
    [[ -z "$LANG_ID" ]] && continue
    FILE_PATH="$MIRROR_FILE"
    pack_dispatch_file "$MIRROR_FILE"
done <<< "$MIRROR_FILES"
FILE_PATH="$FILE_PATH_REAL"

local_should_block=false
[[ -n "$BLOCKING_RULES" ]] && local_should_block=true

# =============================================================================
# Auto-fix (ADR-0018): a Write missing only strict_types is corrected in
# place via updatedInput instead of blocking. The violation is still
# surfaced as additionalContext so the correction learning loop keeps its
# signal. Only when PHP001 would have blocked: a directory that demoted the
# rule asked not to be policed on it, and a fix nobody asked for is policing.
# =============================================================================

# A call that carries the whole file is a write, whatever the host names it
# (Write, write_file, Grok's `write`); the fix rewrites `content` in place.
if [[ $VIOLATION_COUNT -eq 1 && -n "$FILE_CONTENT" && "$LANG_ID" == "php" && "$local_should_block" == true ]] \
   && [[ "$VIOLATIONS" == PHP001* ]] \
   && echo "$FILE_CONTENT" | head -1 | grep -q "^<?php" 2>/dev/null; then
    FIXED_CONTENT=$(printf '%s\n' "$FILE_CONTENT" | awk 'NR==1 && $0 ~ /^<\?php/ {print; print ""; print "declare(strict_types=1);"; next} {print}')
    echo "$INPUT" | jq --arg content "$FIXED_CONTENT" \
    '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: (.tool_input | .content = $content),
            additionalContext: "PHP001 auto-fixed: declare(strict_types=1) was missing and has been inserted after the <?php tag. Include it yourself in future PHP files."
        }
    }'
    exit 0
fi

# =============================================================================
# Output Decision
# =============================================================================

if [[ $VIOLATION_COUNT -gt 0 ]]; then
    if [[ "$local_should_block" == true ]]; then
        # Human-readable message on stderr (shown in Claude Code UI)
        echo "🚫 BLOCKED by AI Craftsman - ${VIOLATION_COUNT} violation(s) detected before write:" >&2
        while IFS= read -r vline; do
            [[ -n "$vline" ]] && echo "  ✗ $vline" >&2
        done <<< "$(echo -e "$VIOLATIONS")"
        echo "Fix these before writing. Use // craftsman-ignore: <RULE_ID> to suppress." >&2

        # Structured JSON on stdout. Exit 2 is the refusal on every host; the
        # deny is stated as well, since a host that reads the JSON before the
        # exit code (Codex) must not read an advisory additionalContext as
        # the whole verdict.
        jq -n --arg v "$(echo -e "$VIOLATIONS")" \
               --arg c "$VIOLATION_COUNT" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: ("BLOCKED before write: " + $c + " violation(s):\n" + $v + "\nFix the code before writing."),
                additionalContext: ("BLOCKED before write: " + $c + " violation(s):\n" + $v + "\nFix the code before writing.")
            }
        }'
        exit 2
    else
        # See session-start.sh: systemMessage is user-facing only, so a warning
        # sent on that channel alone never reaches the model it is meant to steer.
        jq -n --arg v "$(echo -e "$VIOLATIONS")" \
               --arg c "$VIOLATION_COUNT" \
        '(("PRE-WRITE WARNING: " + $c + " issue(s) detected:\n" + $v)) as $body
         | {
            systemMessage: $body,
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                additionalContext: $body
            }
        }'
        exit 0
    fi
fi

exit 0
