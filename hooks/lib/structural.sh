#!/usr/bin/env bash
# =============================================================================
# Structural metrics wrapper - bridges structural_metrics.py to the validator
# pipeline. Provides structural_check_file() for pack validators.
#
# Rules emitted: NEST001, LOC001, GOD001, PARAM001 (severity routed by the
# rules engine; warn-first rollout).
#
# Requires: add_violation() from the orchestrator (post-write-check.sh).
# No-op (fail-open) when python3 is unavailable, mirroring PY002.
# craftsman-ignore: SH001
# =============================================================================

_STRUCTURAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STRUCTURAL_PY="${_STRUCTURAL_DIR}/structural_metrics.py"

# The dialect is read from the registry, which a validator-only harness may
# not have loaded: bring the readers in, and let them build the known
# registry from the manifests on disk when nobody initialised it.
if ! declare -F lang_known_for_file >/dev/null 2>&1; then
    # shellcheck source=./lang-registry.sh
    source "${_STRUCTURAL_DIR}/lang-registry.sh"
fi

# The dialect comes from the registry (`metrics_dialect` in the pack.yml that
# owns the file's language), never from the caller. The two validators used to
# pass their language name, and the extractor accepted it as a spelling of the
# dialect: the capability was declared in the manifest and read by nobody, so
# the manifest could say anything. A language that declares no dialect gets no
# structural metrics, which is what "declares none" means.
structural_check_file() {
    local file="$1"
    local lang="" language
    command -v python3 >/dev/null 2>&1 || return 0
    [[ -f "$_STRUCTURAL_PY" && -f "$file" ]] || return 0
    language=$(lang_known_for_file "$file")
    [[ -n "$language" ]] || return 0
    lang=$(lang_known_capability "$language" metrics_dialect)
    [[ -n "$lang" ]] || return 0

    local line rule msg
    while IFS='|' read -r rule msg; do
        [[ -z "$rule" ]] && continue
        add_violation "$rule" "$msg"
    done < <(python3 "$_STRUCTURAL_PY" "$file" "$lang" 2>/dev/null)
}
