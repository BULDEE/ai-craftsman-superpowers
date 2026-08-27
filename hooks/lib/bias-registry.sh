#!/usr/bin/env bash
# =============================================================================
# Bias Pattern Registry (ADR-0030) - per-language bias patterns, owned by data.
#
# The engine knows the SHAPE of the pattern set and none of its content.
# Adding the twentieth language is adding a twentieth conf file under
# hooks/lib/bias-patterns/, with no edit here and none in bias-detector.sh.
#
# A conf file declares:
#   BIAS_REGISTERED_LANGS+=("de")
#   BIAS_DE_MODE="curated"        # or "signal"
#   BIAS_DE_ACCELERATION="..."    # zero or more of the four categories
#
# curated: context-aware regex, precision earned, warns directly (systemMessage).
# signal:  recall-oriented lexeme alternation; a hit produces an adjudication
#          note for the main model, never a direct warning.
#
# Sourced by a `set -uo pipefail` hook: every indirect read is ${!name:-} so a
# category a language does not declare reads as empty, never as an unbound
# variable. Bash 3.2: no associative arrays anywhere.
# =============================================================================

BIAS_REGISTERED_LANGS=()

# Language tags are BCP 47 (RFC 5646): "fr", and equally "fr-CA", "pt-BR",
# "zh-Hant". A bare language subtag is a valid tag on its own, so the shipped
# files stay "fr" and "zh"; a region or script subtag is added only when a
# dialect actually diverges, which is a question of evidence, not of naming.
#
# A tag is not a bash identifier. `BIAS_FR-CA_MODE=x` parses as a command, not
# an assignment, so a conf named fr-CA.conf registered NOTHING and said nothing
# about it: the hook still exited 0 and the language was simply absent. Silent
# absence is the exact failure this feature exists to remove, so the suffix is
# derived here, and _bias_registry_audit below refuses to let a broken conf
# pass unnoticed.
_bias_var_suffix() {
    printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

# A registered tag whose MODE never landed means its conf declared variables
# under a different suffix than its tag, or failed to parse. Report it on
# stderr the way lang-registry.sh reports a missing python3, and drop the tag
# so no caller reads a half-registered language as a working one.
_bias_registry_audit() {
    local lang suffix mode_variable kept=()
    for lang in ${BIAS_REGISTERED_LANGS[@]+"${BIAS_REGISTERED_LANGS[@]}"}; do
        suffix=$(_bias_var_suffix "$lang")
        mode_variable="BIAS_${suffix}_MODE"
        if [[ -n "${!mode_variable:-}" ]]; then
            kept+=("$lang")
            continue
        fi
        echo "craftsman: bias pattern file for '$lang' declared no BIAS_${suffix}_MODE, so that language is NOT loaded" >&2
    done
    BIAS_REGISTERED_LANGS=(${kept[@]+"${kept[@]}"})
    return 0
}

# bias_registry_init <directory> - source every *.conf, deterministically ordered.
# Re-init resets state: a second call with a different directory must not
# serve the first directory's patterns.
bias_registry_init() {
    local directory="$1" pattern_file lang
    # Unset every variable a previous init registered, then the list itself.
    for lang in ${BIAS_REGISTERED_LANGS[@]+"${BIAS_REGISTERED_LANGS[@]}"}; do
        local suffix
        suffix=$(_bias_var_suffix "$lang")
        unset "BIAS_${suffix}_MODE" \
              "BIAS_${suffix}_ACCELERATION" "BIAS_${suffix}_SCOPE_CREEP" \
              "BIAS_${suffix}_OVER_OPT" "BIAS_${suffix}_DOMAIN_MODELING" 2>/dev/null || true
    done
    BIAS_REGISTERED_LANGS=()

    [[ -d "$directory" ]] || return 0
    for pattern_file in "$directory"/*.conf; do
        [[ -f "$pattern_file" ]] || continue
        # shellcheck source=/dev/null
        source "$pattern_file"
    done
    _bias_registry_audit
    return 0
}

# bias_combined_pattern <CATEGORY> <mode>
# Prints the |-joined alternation across every language of that mode.
# Returns 1 with NO output when no language contributes: an empty pattern
# handed to grep -E matches every prompt, so absence must be a distinct,
# checkable state and never an empty string.
bias_combined_pattern() {
    local category="$1" mode="$2"
    local lang suffix mode_variable pattern_variable pattern combined=""
    for lang in ${BIAS_REGISTERED_LANGS[@]+"${BIAS_REGISTERED_LANGS[@]}"}; do
        suffix=$(_bias_var_suffix "$lang")
        mode_variable="BIAS_${suffix}_MODE"
        [[ "${!mode_variable:-}" == "$mode" ]] || continue
        pattern_variable="BIAS_${suffix}_${category}"
        pattern="${!pattern_variable:-}"
        [[ -z "$pattern" ]] && continue
        if [[ -n "$combined" ]]; then
            combined="${combined}|${pattern}"
        else
            combined="$pattern"
        fi
    done
    [[ -z "$combined" ]] && return 1
    printf '%s' "$combined"
    return 0
}
