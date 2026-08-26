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

# bias_registry_init <dir> - source every *.conf, deterministically ordered.
# Re-init resets state: a second call with a different directory must not
# serve the first directory's patterns.
bias_registry_init() {
    local dir="$1" conf lang
    # Unset every variable a previous init registered, then the list itself.
    for lang in ${BIAS_REGISTERED_LANGS[@]+"${BIAS_REGISTERED_LANGS[@]}"}; do
        local up
        up=$(printf '%s' "$lang" | tr '[:lower:]' '[:upper:]')
        unset "BIAS_${up}_MODE" \
              "BIAS_${up}_ACCELERATION" "BIAS_${up}_SCOPE_CREEP" \
              "BIAS_${up}_OVER_OPT" "BIAS_${up}_DOMAIN_MODELING" 2>/dev/null || true
    done
    BIAS_REGISTERED_LANGS=()

    [[ -d "$dir" ]] || return 0
    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue
        # shellcheck source=/dev/null
        source "$conf"
    done
    return 0
}

# bias_combined_pattern <CATEGORY> <mode>
# Prints the |-joined alternation across every language of that mode.
# Returns 1 with NO output when no language contributes: an empty pattern
# handed to grep -E matches every prompt, so absence must be a distinct,
# checkable state and never an empty string.
bias_combined_pattern() {
    local category="$1" mode="$2"
    local lang up mode_var pat_var pat combined=""
    for lang in ${BIAS_REGISTERED_LANGS[@]+"${BIAS_REGISTERED_LANGS[@]}"}; do
        up=$(printf '%s' "$lang" | tr '[:lower:]' '[:upper:]')
        mode_var="BIAS_${up}_MODE"
        [[ "${!mode_var:-}" == "$mode" ]] || continue
        pat_var="BIAS_${up}_${category}"
        pat="${!pat_var:-}"
        [[ -z "$pat" ]] && continue
        if [[ -n "$combined" ]]; then
            combined="${combined}|${pat}"
        else
            combined="$pat"
        fi
    done
    [[ -z "$combined" ]] && return 1
    printf '%s' "$combined"
    return 0
}
