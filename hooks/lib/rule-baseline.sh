#!/usr/bin/env bash
# =============================================================================
# Rule baseline - what a file already carried when its mark was taken.
#
# The structural ratchet answers "is this file worse than it was" for
# complexity and size. This answers it for rules, which is the half that made
# the plugin hard to adopt: on a codebase with three years of history, the
# first edit to nearly every file was refused for code the user did not write.
#
# A finding is HELD BACK, never dropped: it is still printed, so the model and
# the user see the debt, and it stops the write only when the file is worse
# than its mark. That distinction is the whole design. Silencing pre-existing
# debt would make the gate lie about the state of the file; blocking on it
# makes the gate unusable. Reporting without blocking is neither.
#
# Requires: python3. Without it every finding blocks as before, which is the
# safe direction: a missing interpreter must not open a gate.
# craftsman-ignore: SH001
# =============================================================================

_RULE_BASELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RULE_BASELINE_PY="${_RULE_BASELINE_DIR}/rule_baseline.py"

# What this mechanism does NOT catch, stated where the next reader will look.
#
# The comparison is ordinal and blind to content. A file marked with one
# PHP001 and one PHP002, replaced wholesale by an entirely different class that
# violates the same two rules, comes back as pre-existing debt: same rules,
# same counts, nothing to compare. Only the structural ratchet reacts, and only
# if the size or complexity moved.
#
# That is a deliberate limit, not an oversight, and the reasoning is the same
# one that makes the whole feature safe: a mark is a statement about a file's
# debt, not a signature of its contents. Hashing the file would turn every
# legitimate edit into a re-mark, which is the behaviour this exists to remove.
# The rules that must never be waved through regardless are listed below.
#
# Occurrences seen in THIS run, per file and rule. The comparison is ordinal:
# the Nth occurrence of a rule in a file is pre-existing when the mark recorded
# at least N. So a file marked with one PHP002 that now has two blocks on the
# second, and a file that fixed one and kept one still passes.
_RULE_BASELINE_SEEN=""

# Called at the start of each file, by every front-end that walks more than one.
# Without it, a file reached twice (overlapping scan roots, a common shape)
# inherits the first pass's counter and its recorded debt is counted as new: a
# green build turns red on `craftsman-ci src src/sub` and stays green on
# `craftsman-ci src`, for the same repository.
rule_baseline_reset() {
    _RULE_BASELINE_SEEN=""
    rm -f "$_RULE_BASELINE_CACHE" 2>/dev/null || true
}

# One interpreter start per file, not per rule.
#
# `get <file> <rule>` reloads and re-parses the whole baseline on every call,
# and it is called once per finding (post-write-check.sh:260, craftsman-ci.sh:566).
# Measured, rather than assumed: a validator reports one hit per rule per file,
# so the bound is rules-per-file and not occurrences. On a 40-method PHP class
# with a mark the delta was 1 interpreter start (52 -> 51); the case this pays
# for is a wide file under `strict`, where every rule resolves to block and each
# one asks the same question of the same JSON.
# On disk, not in a shell variable.
#
# Every caller reads this through `$(...)`, so a variable assignment happens in
# a subshell and is gone before the next finding: a cache kept in memory here
# measured exactly zero saved interpreter starts. The file survives the
# subshell, which is the whole point. First line is the path it answers for.
_RULE_BASELINE_CACHE="${TMPDIR:-/tmp}/craftsman-rule-baseline-cache.$$"

_rule_baseline_recorded() {
    local file="$1" rule="$2"
    if [[ ! -f "$_RULE_BASELINE_CACHE" ]] \
        || [[ "$(head -1 "$_RULE_BASELINE_CACHE" 2>/dev/null)" != "$file" ]]; then
        {
            printf '%s\n' "$file"
            python3 "$_RULE_BASELINE_PY" counts "$file" 2>/dev/null
        } > "$_RULE_BASELINE_CACHE" 2>/dev/null || return 0
    fi
    # awk with -v, not grep: a rule id must match the whole field, and the key
    # must never be read as a pattern.
    awk -F= -v r="$rule" 'NR > 1 && $1 == r { print $2; exit }' "$_RULE_BASELINE_CACHE"
}

# -cxF, not -c with an anchored pattern. A path is not a regex: `[` opens a
# character class, so `app/[slug]/page.tsx` never matched itself, the count came
# back 0 for every occurrence, and every finding in such a file was pardoned as
# its own first one. That path shape is exactly what post-write-check.sh widened
# its allowlist to accept. -x anchors on the whole line, -F takes the key
# literally, and -- stops a key starting with a dash being read as an option.
_rule_baseline_seen_count() {
    local key="$1" count
    count=$(printf '%s' "$_RULE_BASELINE_SEEN" | grep -cxF -- "$key" 2>/dev/null || true)
    printf '%s' "${count:-0}"
}

# Rules a baseline may never hold back.
#
# The premise of this whole mechanism is that inherited debt is a thing you
# pay down on your own schedule. A hardcoded secret is not that. It is a live
# credential in a repository, and the only correct response is to rotate it
# now, so recording one at the mark and waving it through on every later edit
# would be the plugin helping to keep it there. SEC003 (SQL built by
# concatenation) is the same argument: an injection is not a style you grow out
# of.
#
# RATCHET001 is excluded for a different reason: it IS a baseline comparison,
# and baselining a baseline says nothing.
_rule_baseline_never_holds() {
    case "$1" in
        SEC*|RATCHET001) return 0 ;;
    esac
    return 1
}

# rule_baseline_is_preexisting <file> <rule>
# Exit 0 when this occurrence was already there at the mark.
rule_baseline_is_preexisting() {
    local file="$1" rule="$2"
    _rule_baseline_never_holds "$rule" && return 1
    command -v python3 >/dev/null 2>&1 || return 1
    [[ -f "$_RULE_BASELINE_PY" ]] || return 1

    local key="${file}|${rule}"
    local seen recorded
    seen=$(_rule_baseline_seen_count "$key")
    _RULE_BASELINE_SEEN="${_RULE_BASELINE_SEEN}${key}"$'\n'

    recorded=$(_rule_baseline_recorded "$file" "$rule")
    [[ "$recorded" =~ ^[0-9]+$ ]] || return 1

    # seen is the count BEFORE this occurrence, so occurrence number is seen+1.
    [[ $((seen + 1)) -le "$recorded" ]]
}
