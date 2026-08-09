#!/usr/bin/env bash
# =============================================================================
# Level precedence - which level answers for a rule, and when.
#
# A rule can be checked twice: by a pack's Level 1 regex, and by the Level 2/3
# analyser that same pack declared owner of the rule under `supersedes:` in its
# manifest. Both emitted, so one defect got two verdicts and nothing made them
# agree.
#
# The engine DEFERS the Level 1 finding, it never deletes it:
#
#   1. A finding whose rule a higher level claims is held, not emitted.
#   2. Level 2/3 emits directly. It is never held and never superseded, and it
#      declares the rule codes it actually produced a verdict for.
#   3. At the end of the run every held finding no higher verdict covered is
#      emitted normally, through the front-end's own path and therefore with
#      full severity resolution.
#
# Deleting was the first shape of this and it was wrong twice over. sa_timeout
# returns 124 when a cold analyser overruns its budget and the caller flattens
# that into success, so the file would have got no verdict from either level
# and the defect would have vanished without a trace. And an analyser
# configured to ignore the rule produces no verdict either, while the mere
# presence of its binary had already silenced the regex. Absence of a verdict
# now means the Level 1 finding comes back, so the machine owner's doctrine
# outlives a project's analyser configuration.
#
# This lives beside rules-engine.sh rather than inside static-analysis.sh on
# purpose: precedence is a decision about verdicts, like severity, and it is
# the engine's to make. The analyser dispatcher runs tools and knows nothing
# about it.
#
# A manifest entry is `<tool>=<RULE>,<RULE>`. The tool name is not consulted at
# runtime - see _precedence_load_claims - but it is not decoration: it is what
# lang_registry.py checks the claim against, refusing at build time any entry
# where a tool would outrank its own verdicts.
#
# Usage (front-end):
#   precedence_reset
#   ... Level 1 emitters call precedence_defers <rule> <file> and, when true,
#       precedence_hold <rule> <file> <line> <message>
#   precedence_higher_level_begin; ... Level 2/3 emits ...; _end
#   precedence_flush
#
# The front-end supplies two callbacks, by name:
#   precedence_emit <rule> <file> <line> <message>   re-emit a flushed finding
#   precedence_note_superseded <rule> <file>         record the deferral
# =============================================================================

# Which rules a higher level claims, for one file, and which it has answered
# for. Held findings sit in parallel arrays for bash 3.2, which has no
# associative arrays and ships on every macOS.
_PRECEDENCE_CLAIM_FILE=""
_PRECEDENCE_CLAIMED=""
_PRECEDENCE_COVERED=""
_PRECEDENCE_HIGHER_LEVEL=0
_PRECEDENCE_HELD_RULES=()
_PRECEDENCE_HELD_FILES=()
_PRECEDENCE_HELD_LINES=()
_PRECEDENCE_HELD_MESSAGES=()

# Start of a run, and end of one. A front-end that scans many files calls this
# per file: a verdict on one file answers for nothing in the next.
precedence_reset() {
    _PRECEDENCE_CLAIM_FILE=""
    _PRECEDENCE_CLAIMED=""
    _PRECEDENCE_COVERED=""
    _PRECEDENCE_HIGHER_LEVEL=0
    _PRECEDENCE_HELD_RULES=()
    _PRECEDENCE_HELD_FILES=()
    _PRECEDENCE_HELD_LINES=()
    _PRECEDENCE_HELD_MESSAGES=()
    return 0
}

# Level 2/3 emits between these two. Its verdicts go straight out: they are
# never held, and they cannot be superseded - not even by a manifest that
# names the analyser as the owner of the analyser's own codes, which is the
# self-silencing loop this bracket closes structurally rather than by rule.
precedence_higher_level_begin() {
    _PRECEDENCE_HIGHER_LEVEL=1
    return 0
}

precedence_higher_level_end() {
    _PRECEDENCE_HIGHER_LEVEL=0
    return 0
}

# precedence_declare_covered <rule> - a higher level answered for this rule.
# Called with the code of every Level 2/3 verdict, and callable by an adapter
# that ran clean and knows which rules its run actually covered.
precedence_declare_covered() {
    local rule="$1"
    [[ -z "$rule" ]] && return 0
    if ! precedence_rule_covered "$rule"; then
        _PRECEDENCE_COVERED="${_PRECEDENCE_COVERED}${rule}"$'\n'
    fi
    return 0
}

precedence_rule_covered() {
    case $'\n'"$_PRECEDENCE_COVERED" in
        *$'\n'"$1"$'\n'*) return 0 ;;
    esac
    return 1
}

# precedence_defers <rule> <file> - exit 0 when this Level 1 finding must be
# held back rather than emitted now.
precedence_defers() {
    local rule="$1" file="$2"
    [[ -z "$rule" || -z "$file" ]] && return 1
    [[ "$_PRECEDENCE_HIGHER_LEVEL" == "1" ]] && return 1

    [[ "$file" == "$_PRECEDENCE_CLAIM_FILE" ]] || _precedence_load_claims "$file"
    [[ -z "$_PRECEDENCE_CLAIMED" ]] && return 1

    # Pure-bash membership: one fork per violation is a fork the 50ms Level 1
    # budget cannot spare. Both delimiters are re-added here rather than
    # assumed, because command substitution strips the list's trailing newline
    # and anchoring on the stored one silently matched nothing.
    case $'\n'"$_PRECEDENCE_CLAIMED"$'\n' in
        *$'\n'"$rule"$'\n'*) return 0 ;;
    esac
    return 1
}

# precedence_hold <rule> <file> <line> <message>
precedence_hold() {
    _PRECEDENCE_HELD_RULES+=("$1")
    _PRECEDENCE_HELD_FILES+=("$2")
    _PRECEDENCE_HELD_LINES+=("$3")
    _PRECEDENCE_HELD_MESSAGES+=("$4")
    return 0
}

# End of run. Every held finding the higher level did not answer for is emitted
# now; the rest is recorded as deferred so it stays visible to the metrics and
# to the correction learning, which would otherwise read a rule gone quiet as a
# rule the developer fixed.
precedence_flush() {
    local index=0 total="${#_PRECEDENCE_HELD_RULES[@]}"
    _PRECEDENCE_HIGHER_LEVEL=1
    while [[ $index -lt $total ]]; do
        _precedence_flush_one "$index"
        index=$((index + 1))
    done
    precedence_reset
    return 0
}

_precedence_flush_one() {
    local index="$1" rule="${_PRECEDENCE_HELD_RULES[$1]}"
    if precedence_rule_covered "$rule"; then
        if type precedence_note_superseded >/dev/null 2>&1; then
            precedence_note_superseded "$rule" "${_PRECEDENCE_HELD_FILES[$index]}" || true
        fi
        return 0
    fi
    if type precedence_emit >/dev/null 2>&1; then
        precedence_emit "$rule" "${_PRECEDENCE_HELD_FILES[$index]}" \
            "${_PRECEDENCE_HELD_LINES[$index]}" \
            "${_PRECEDENCE_HELD_MESSAGES[$index]}" || true
    fi
    return 0
}

# The rules a higher level claims on this file, memoised: the question is asked
# once per violation and a single edit can raise a dozen, while the answer
# cannot change inside one run. An empty answer is the safe one - every rule
# reports.
#
# The memo is filled and read through globals, never through `$(...)`: a command
# substitution runs in a subshell, so the first shape of this cache stored its
# answer in a child that then exited and every call paid the registry lookup and
# the tool probe again.
_precedence_load_claims() {
    local file="$1" language="" entries=""
    _PRECEDENCE_CLAIM_FILE="$file"
    _PRECEDENCE_CLAIMED=""

    type lang_capability >/dev/null 2>&1 || return 0
    type _sa_language_of >/dev/null 2>&1 || return 0
    language=$(_sa_language_of "$file")
    [[ -z "$language" ]] && return 0

    # The manifest is the whole predicate, deliberately. Whether the higher
    # level is installed, trusted and configured to check this rule is not
    # guessed here: the flush answers it from what actually arrived.
    #
    # This resolver used to probe all three - trust_project_tools, the declared
    # binary, a static_analysis adapter for the language - because under the
    # earlier "drop the Level 1 finding" design each of them was the difference
    # between one verdict and none at all. Deferring makes them redundant, and
    # the binary probe was worse than redundant: an adapter that reports through
    # some other path than the tool the manifest names would have had its
    # verdict AND the regex's, which is the duplication this exists to remove.
    entries=$(lang_capability "$language" supersedes)
    [[ -z "$entries" ]] && return 0

    _PRECEDENCE_CLAIMED=$(_precedence_collect_claims "$entries")
    return 0
}

_precedence_collect_claims() {
    local entry rules rule resolved=""
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        rules="${entry#*=}"
        # No '=' means the manifest named a tool with no rules behind it. It
        # claims nothing rather than everything.
        [[ "$rules" == "$entry" ]] && continue
        for rule in ${rules//,/ }; do
            [[ -n "$rule" ]] && resolved="${resolved}${rule}"$'\n'
        done
    done <<< "$1"
    printf '%s' "$resolved"
}

# sa_language_has_analyser <language> - the loaded packs contribute a Level 2/3
# adapter for this language. Memoised and shared: the front-end asks it to
# decide whether to run Level 2/3 at all, and the claim resolver asks it again
# a few lines later. Two forks for one answer that cannot have changed.
_PRECEDENCE_ANALYSER_KEY=""
_PRECEDENCE_ANALYSER_VALUE=""

sa_language_has_analyser() {
    local language="$1"
    [[ -z "$language" ]] && return 1
    if [[ "$language" != "$_PRECEDENCE_ANALYSER_KEY" ]]; then
        _PRECEDENCE_ANALYSER_KEY="$language"
        _PRECEDENCE_ANALYSER_VALUE=""
        if type lang_capability >/dev/null 2>&1; then
            _PRECEDENCE_ANALYSER_VALUE=$(lang_capability "$language" static_analysis)
        fi
    fi
    [[ -n "$_PRECEDENCE_ANALYSER_VALUE" ]]
}
