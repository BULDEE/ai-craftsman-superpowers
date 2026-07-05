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

structural_check_file() {
    local file="$1"
    local lang="$2"
    command -v python3 >/dev/null 2>&1 || return 0
    [[ -f "$_STRUCTURAL_PY" && -f "$file" ]] || return 0

    local line rule msg
    while IFS='|' read -r rule msg; do
        [[ -z "$rule" ]] && continue
        add_violation "$rule" "$msg"
    done < <(python3 "$_STRUCTURAL_PY" "$file" "$lang" 2>/dev/null)
}
