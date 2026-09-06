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

# Occurrences seen in THIS run, per file and rule. The comparison is ordinal:
# the Nth occurrence of a rule in a file is pre-existing when the mark recorded
# at least N. So a file marked with one PHP002 that now has two blocks on the
# second, and a file that fixed one and kept one still passes.
_RULE_BASELINE_SEEN=""

rule_baseline_reset() {
    _RULE_BASELINE_SEEN=""
}

_rule_baseline_seen_count() {
    local key="$1" count
    count=$(printf '%s' "$_RULE_BASELINE_SEEN" | grep -c "^${key}$" 2>/dev/null || true)
    printf '%s' "${count:-0}"
}

# rule_baseline_is_preexisting <file> <rule>
# Exit 0 when this occurrence was already there at the mark.
rule_baseline_is_preexisting() {
    local file="$1" rule="$2"
    command -v python3 >/dev/null 2>&1 || return 1
    [[ -f "$_RULE_BASELINE_PY" ]] || return 1

    local key="${file}|${rule}"
    local seen recorded
    seen=$(_rule_baseline_seen_count "$key")
    _RULE_BASELINE_SEEN="${_RULE_BASELINE_SEEN}${key}"$'\n'

    recorded=$(python3 "$_RULE_BASELINE_PY" get "$file" "$rule" 2>/dev/null)
    [[ "$recorded" =~ ^[0-9]+$ ]] || return 1

    # seen is the count BEFORE this occurrence, so occurrence number is seen+1.
    [[ $((seen + 1)) -le "$recorded" ]]
}
