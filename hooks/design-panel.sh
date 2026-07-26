#!/usr/bin/env bash
# =============================================================================
# Adversarial Design Panel (ADR-0026)
# Three headless Haiku contradictors attack a design BEFORE code exists.
# Invoked by /craftsman:design phase Challenge. Never automatic, never blocking:
# the panel always exits 0, its objections are advisory input for the designer.
# =============================================================================
set -uo pipefail

# Recursion guard: never convene the panel from inside a verification subprocess
[[ -n "${CRAFTSMAN_HEADLESS_VERIFY:-}" ]] && exit 0

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/haiku-verify.sh"

DESIGN_FILE="${1:-}"
[[ -z "$DESIGN_FILE" || ! -f "$DESIGN_FILE" ]] && exit 0

DESIGN_CONTENT=$(head -c 8000 "$DESIGN_FILE")
echo "panel: 3 Haiku calls" >&2

_panel_lens() {
    local lens_name="$1" lens_prompt="$2"
    local verdict
    verdict=$(haiku_verify "You are an adversarial design reviewer. ${lens_prompt} Reply with at most 5 numbered objections, each one line, most severe first; reply NO_OBJECTIONS if the design holds. DESIGN: ${DESIGN_CONTENT}") || return 0
    [[ -z "$verdict" ]] && return 0
    echo "LENS ${lens_name}:"
    echo "$verdict"
}

_panel_lens "yagni" "Attack this design for over-engineering: unnecessary abstraction, speculative generality, features nobody asked for, simpler alternatives dismissed without reason."
_panel_lens "invariants" "Attack this design's domain model: invariants that cannot be protected, aggregate boundaries that force multi-aggregate transactions, missing value objects, anemic entities."
_panel_lens "feasibility" "Attack this design's feasibility: hidden performance cliffs (N+1, unbounded reads), operational blind spots, failure modes without recovery, integration points that will not work as drawn."

exit 0
