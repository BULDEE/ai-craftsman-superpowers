#!/usr/bin/env bash
# =============================================================================
# Pre-Write/Edit Validation Hook for Claude Code
# Validates BEFORE file is written: layer imports, path conventions.
#
# TRIGGERS: PreToolUse for Write and Edit tools
# EXIT CODES: 0 = allow, 2 = block with reason
# =============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/exported-gate.sh" # one gate per write on Grok (CR-310)

# A gate that cannot run is not a clean verdict (ADR-0029, which the Hermes
# adapter honoured and this hook did not: a crash here used to exit 0 and let
# the write land). Refused, with the line and the retry advice. Malformed or
# empty input is not a crash: it names no file, and the read below tolerates
# it so that nothing is refused for nothing.
trap 'echo "The craftsman pre-write gate could not run (pre-write-check.sh, line $LINENO). Retry the write once; if it repeats, the gate needs attention, not the write." >&2; exit 2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/session-files.sh"
INPUT=$(cat)
session_files_bind "$INPUT"
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

# Validate and decode the bound tool input
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
# precedence hold and the Level 2/3 analysers, neither of which belongs before
# a write. The metrics are recorded once the verdict is in, for a refusal only
# (see "A refusal is a finding" below).
# =============================================================================
# Grok cuts the long strings of a tool input over 128 KiB and sets
# toolInputTruncated (CR-311). Judging the cut text would wave through whatever
# sat in the missing end, so the write is refused with the reason: an unread
# mutation is not a pass, the same stance as an UNJUDGED hunk below.
# A bash match first, so the payloads of every other host pay no extra process.
if [[ "$INPUT" =~ \"toolInputTruncated\"[[:space:]]*:[[:space:]]*true ]] \
    && [[ "$(printf '%s' "$INPUT" | jq -r '.toolInputTruncated // false' 2>/dev/null)" == "true" ]]; then
    echo "🚫 BLOCKED by AI Craftsman - the host truncated this write's content (toolInputTruncated), so the gate cannot judge all of it. Split the file or write it in smaller edits." >&2
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "the host truncated this write (toolInputTruncated), so the gate cannot judge all of it: split it into smaller edits"}}'
    exit 2
fi
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
# =============================================================================
# The file on disk is an implicit mark (CR-306)
#
# This gate judges the whole would-be file, so a one-line edit to a file that
# already held a blocking finding was refused for code the edit did not touch:
# the adoption wall the rule baseline removes, back for every project that had
# not marked its debt. Before refusing, the file as it stands is judged the
# same way, and the Nth occurrence of a rule is held back (reported, not
# blocking) when the file already held N. What the edit brings still blocks, a
# new file holds nothing, the rules the baseline never holds (SEC*, RATCHET001)
# and a severity the user set by name still block. Ordinal and blind to
# content, like the mark it stands in for. Judged only on the way to a refusal,
# so a clean write pays nothing.
# =============================================================================
_SEEN_FINDINGS=""
_DISK_FINDINGS=""
_DISK_JUDGED=""
_TARGETS=""
_TARGETS_READ=false
# Every helper below sets globals instead of printing: called as $(...), a
# cache filled inside the subshell vanished with it (the CR-301 defect), and
# the counts handed to post-write came back empty.
DISK_TARGET=""
_disk_target() { # <mirror rel>: sets DISK_TARGET to the real file, if it exists
    if [[ "$_TARGETS_READ" == false ]]; then
        _TARGETS=$(printf '%s' "$INPUT" | jq --arg cwd "$PWD" '. + {cwd: (.cwd // $cwd)}' 2>/dev/null \
            | python3 "${SCRIPT_DIR}/lib/write_mirror.py" --targets "$MIRROR" 2>/dev/null)
        _TARGETS_READ=true
    fi
    DISK_TARGET=$(printf '%s\n' "$_TARGETS" | awk -F'\t' -v mirror="$1" '$1 == mirror {print $2; exit}')
    [[ -f "$DISK_TARGET" ]] || DISK_TARGET=""
}
# One rule per occurrence the file HELD, through _pre_emit's own filters: a
# finding silenced by a marker or an `ignore` severity was suppressed, not held,
# and deleting the marker exposes it (tests/core/test-host-payloads.sh, F2).
_disk_findings() { # <real file>
    local lang
    lang=$(lang_for_file "$1")
    [[ -n "$lang" ]] || return 0
    (
        _disk_held() {
            [[ "$(rules_severity_for_file "$MIRROR_FILE" "$1")" == "ignore" ]] && return 0
            file_has_ignore "$1" || printf '%s\n' "$1" >&3
        }
        add_violation() { _disk_held "$1"; }
        add_warning() { _disk_held "$1"; }
        MIRROR_FILE="$1"; FILE_PATH="$1"
        pack_dispatch_file "$1"
        rules_check_custom "$1" "$lang"
    ) 3>&1 >/dev/null 2>&1
}
# The rules a write of this session left on the file, reported blocking by
# its post-write (CR-313). They are not the file's past: held as such, one
# Bash write that lands without the gate would let every later edit through.
LANDED_RULES=""
_session_landed() { # <real file>: sets LANDED_RULES, space-separated
    LANDED_RULES=$(jq -r --arg key "$(session_pending_key "$1")" '.landed_violations[$key] // [] | join(" ")' \
        "$(session_file session-state.json)" 2>/dev/null)
}
_judge_disk() { # judges MIRROR_REL's file as it stands on disk, once
    grep -qxF "$MIRROR_REL" <<< "$_DISK_JUDGED" && return 0
    _DISK_JUDGED+="${MIRROR_REL}"$'\n'
    _disk_target "$MIRROR_REL"
    [[ -n "$DISK_TARGET" ]] || return 0
    _session_landed "$DISK_TARGET"
    _DISK_FINDINGS+=$(_disk_findings "$DISK_TARGET" | awk -v landed=" ${LANDED_RULES} " 'index(landed, " " $0 " ") == 0' \
        | sed "s|^|${MIRROR_REL}"$'\t'"|")$'\n'
}
_held_by_disk() { # <rule> <severity>
    [[ "$2" == "block" ]] || return 1
    _rule_baseline_never_holds "$1" && return 1
    rules_severity_is_explicit "$MIRROR_FILE" "$1" && return 1
    _judge_disk
    local key="${MIRROR_REL}"$'\t'"$1"
    [[ "$(grep -cxF "$key" <<< "$_SEEN_FINDINGS")" -le "$(grep -cxF "$key" <<< "$_DISK_FINDINGS")" ]]
}
# Sets HELD to why a blocking finding is held back, or empty. A global, not
# $(...): the disk judgement it may trigger is cached for the next finding.
HELD=""
_hold_reason() { # <rule> <severity>
    HELD=""
    if rules_baseline_holds "$MIRROR_FILE" "$1" "$2"; then
        HELD="already present at the baseline"
    elif _held_by_disk "$1" "$2"; then
        HELD="already in the file before this edit"
        _HELD_BY_DISK+="${MIRROR_REL}"$'\t'"$1"$'\n'
    fi
}
_HELD_BY_DISK=""
# The post-write of the same file must agree, or the model reads "allowed"
# before the write and "BLOCKED" after it for the one finding. The disk count of
# every rule held here goes to the session state under the key post-write uses,
# and post-write takes it once (session_state.py hold / take-held).
_hand_held_to_post_write() {
    [[ -n "$_HELD_BY_DISK" ]] || return 0
    local rel target counts
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        _disk_target "$rel"
        target="$DISK_TARGET"
        counts=$(awk -F'\t' -v rel="$rel" 'NR == FNR {if ($1 == rel) held[$2] = 1; next}
            $1 == rel && ($2 in held) {count[$2]++} END {for (r in count) print r "\t" count[r]}' \
            <(printf '%s' "$_HELD_BY_DISK") <(printf '%s' "$_DISK_FINDINGS") \
            | jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {}')
        python3 "${SCRIPT_DIR}/lib/session_state.py" hold "$(session_file session-state.json)" \
            "$(session_pending_key "$target")" "$counts" 2>/dev/null || true
    done <<< "$(cut -f1 <<< "$_HELD_BY_DISK" | sort -u)"
}

BLOCKING_RULES=""
REFUSED_FINDINGS=""
# A blocking finding, kept with the file it names: one line per refusal to record.
_hold_blocking() {
    local rule="$1"
    BLOCKING_RULES="$BLOCKING_RULES ${MIRROR_REL}:${rule}"
    REFUSED_FINDINGS+="${MIRROR_REL}"$'\t'"${rule}"$'\n'
}
_pre_emit() {
    local rule="$1" message="$2" severity
    severity=$(rules_severity_for_file "$MIRROR_FILE" "$rule")
    [[ "$severity" == "ignore" ]] && return 0
    file_has_ignore "$rule" && return 0
    _SEEN_FINDINGS+="${MIRROR_REL}"$'\t'"${rule}"$'\n'
    _hold_reason "$rule" "$severity"
    [[ -n "$HELD" ]] && { severity="warn"; message="${message} (${HELD}, not blocking)"; }
    case " $BLOCKING_RULES " in *" ${MIRROR_REL}:${rule} "*) return 0 ;; esac
    [[ "$severity" == "block" ]] && _hold_blocking "$rule"
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
    # The project's own rules too, the pass post-write and CI run (CR-171).
    rules_check_custom "$MIRROR_FILE" "$LANG_ID"
done <<< "$MIRROR_FILES"
FILE_PATH="$FILE_PATH_REAL"
_hand_held_to_post_write

local_should_block=false
[[ -n "$BLOCKING_RULES" ]] && local_should_block=true

# =============================================================================
# Auto-fix (ADR-0018): a Write missing only strict_types is corrected in
# place via updatedInput instead of blocking. The model is told through
# additionalContext. Nothing reaches metrics.db: this branch exits before the
# refusal is recorded, so the correction learning loop never sees an
# auto-fixed PHP001 (CR-304). Only when PHP001 would have blocked: a directory
# that demoted the rule asked not to be policed on it, and a fix nobody asked
# for is policing.
# =============================================================================

# A call that carries the whole file is a write, whatever the host names it
# (Write, write_file, Grok's `write`); the fix rewrites `content` in place.
FIXED_CONTENT=""
if [[ $VIOLATION_COUNT -eq 1 && -n "$FILE_CONTENT" && "$LANG_ID" == "php" && "$local_should_block" == true ]] \
   && [[ "$VIOLATIONS" == PHP001* ]] \
   && echo "$FILE_CONTENT" | head -1 | grep -qE '^<\?php([[:space:]]|$)' 2>/dev/null; then
    # PHP refuses a declare that is not the very first statement, so code
    # sharing the opening line moves below it (CR-226).
    FIXED_CONTENT=$(printf '%s\n' "$FILE_CONTENT" | awk 'NR==1 {rest = substr($0, 6); sub(/^[[:space:]]+/, "", rest); print "<?php"; print ""; print "declare(strict_types=1);"; if (rest != "") {print ""; print rest}; next} {print}')
    # Judged as it lands (CR-314): the fix moves the code sharing the opening
    # line below the declare, where a rule anchored on the line start sees it,
    # and the post-write judges what landed. A finding there joins PHP001 and
    # the write is refused with both, the verdict a finding beside PHP001 gets
    # from the start.
    printf '%s' "$FIXED_CONTENT" > "$MIRROR_FILE"
    FILE_PATH="$MIRROR_FILE"
    pack_dispatch_file "$MIRROR_FILE"
    rules_check_custom "$MIRROR_FILE" "$LANG_ID"
    FILE_PATH="$FILE_PATH_REAL"
fi
if [[ -n "${FIXED_CONTENT:-}" && $VIOLATION_COUNT -eq 1 ]]; then
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
# A refusal is a finding (CR-300)
#
# This gate used to drop its findings, metrics being post-write's. Since every
# pack rule is judged here (a9b0f51), a blocking finding almost never lands, so
# post-write never saw one and the correction learning starved: 176 fixes
# recorded in August, 3 in November, under daily use. A refused finding is now
# recorded as blocking and left pending on its file, the shape post-write gives
# a blocked write, so the next accepted write answers it through
# _check_corrections like any other. Warnings stay post-write's: their file
# lands, and recording them here as well would count them twice.
# =============================================================================
REFUSED_MAP=""
# The real file a mirror path stands for, from the mirror's own resolution:
# the payload's cwd, the workspace of each file of a patch.
_refused_target() {
    printf '%s\n' "$REFUSED_MAP" | awk -F'\t' -v mirror="$1" '$1 == mirror {print $2; exit}'
}
_record_refused_file() {
    local target rules
    target=$(_refused_target "$1")
    [[ -n "$target" ]] || return 0
    rules=$(printf '%s' "$REFUSED_FINDINGS" | awk -F'\t' -v mirror="$1" '$1 == mirror {print $2}')
    _record_refused_metrics "$target" "$rules"
    _leave_refusal_pending "$target" "$rules"
}
_record_refused_metrics() {
    local rule
    for rule in $2; do
        metrics_record_violation "$rule" "$(metrics_file_pattern "$1")" critical 1 0 "$1"
    done
}
# Pending on the file exactly as post-write leaves a blocked write.
_leave_refusal_pending() {
    local state
    state=$(session_file session-state.json)
    mkdir -p "$(dirname "$state")"
    python3 "${SCRIPT_DIR}/lib/session_state.py" record-violation "$state" \
        "$(session_pending_key "$1")" "$(dirname "$1" | sed -E "s|${PWD}/||")" \
        "$(printf '%s\n' "$2" | jq -Rnc '[inputs | select(length > 0)]')" --keep
}
_record_refusals() {
    source "${SCRIPT_DIR}/lib/metrics-db.sh"
    metrics_init_once
    metrics_project_resolve
    REFUSED_MAP=$(printf '%s' "$INPUT" | jq --arg cwd "$PWD" '. + {cwd: (.cwd // $cwd)}' \
        | python3 "${SCRIPT_DIR}/lib/write_mirror.py" --targets "$MIRROR")
    metrics_violations_queue_open
    local mirror_rel
    while IFS= read -r mirror_rel; do
        [[ -n "$mirror_rel" ]] && _record_refused_file "$mirror_rel"
    done <<< "$(printf '%s' "$REFUSED_FINDINGS" | cut -f1 | sort -u)"
    metrics_violations_queue_flush
}
# Recorded in a subshell: a recording that fails costs the learning one
# finding and says so, it never costs the refusal.
_record_refusals_or_say() {
    local errors
    errors=$( { _record_refusals >/dev/null; } 2>&1 ) || true
    [[ -z "$errors" ]] || echo "craftsman: this refusal was not recorded for correction learning: ${errors%%$'\n'*}" >&2
}

# =============================================================================
# Output Decision
# =============================================================================

if [[ $VIOLATION_COUNT -gt 0 ]]; then
    if [[ "$local_should_block" == true ]]; then
        _record_refusals_or_say
        # Human-readable message on stderr (shown in Claude Code UI)
        echo "🚫 BLOCKED by AI Craftsman - ${VIOLATION_COUNT} violation(s) detected before write:" >&2
        while IFS= read -r vline; do
            [[ -n "$vline" ]] && echo "  ✗ $vline" >&2
        done <<< "$(echo -e "$VIOLATIONS")"
        MARKER_ADVICE=$(rule_marker_advice "$(echo -e "$VIOLATIONS")")
        echo "Fix these before writing." >&2
        echo "$MARKER_ADVICE" >&2

        # Structured JSON on stdout. Exit 2 is the refusal on every host; the
        # deny is stated as well, since a host that reads the JSON before the
        # exit code (Codex) must not read an advisory additionalContext as
        # the whole verdict.
        jq -n --arg v "$(echo -e "$VIOLATIONS")" \
               --arg c "$VIOLATION_COUNT" \
               --arg a "$MARKER_ADVICE" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: ("BLOCKED before write: " + $c + " violation(s):\n" + $v + "\nFix the code before writing.\n" + $a),
                additionalContext: ("BLOCKED before write: " + $c + " violation(s):\n" + $v + "\nFix the code before writing.\n" + $a)
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
