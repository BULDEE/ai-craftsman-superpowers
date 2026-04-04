#!/usr/bin/env bash
# =============================================================================
# Bias Detection Hook for Claude Code
# Detects cognitive biases in prompts and displays non-blocking warnings.
#
# SECURITY: This script only reads stdin and outputs warnings to stdout.
#           It does NOT modify files, execute commands, or access network.
# =============================================================================
set -uo pipefail

# Non-blocking: if hook crashes, pass silently
trap 'exit 0' ERR

SESSION_STATE="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"

# Read the prompt from stdin (JSON format from Claude Code)
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "$INPUT")

# If we couldn't parse JSON, use the raw input
if [[ -z "$PROMPT" ]]; then
    PROMPT="$INPUT"
fi

# Exit early if no prompt
[[ -z "$PROMPT" ]] && exit 0

# =============================================================================
# Bias Patterns (case-insensitive, bilingual FR/EN)
# =============================================================================

# Acceleration bias: rushing without thinking
# Context-aware: requires imperative verb context or explicit rush indicators
# Reduced false positives: "quick fix" alone won't trigger, "just do it quick" will
ACCELERATION_PATTERNS="(fais.{0,10}vite|code direct|pas le temps|no time|just do it|skip the (design|test|review)|hurry up|asap|do it now|juste code|sans (réfléchir|tester|design))"

# Scope creep: adding features beyond scope
# Context-aware: requires action verb + addition pattern
SCOPE_CREEP_PATTERNS="(et (aussi|en plus) (ajoute|fais|met|ajoutons)|tant qu'on y est|while we're at it.*(add|change|also)|also add|let's also (add|do|change)|and also (add|do|implement)|ajoutons aussi|rajoute)"

# Over-optimization: premature abstraction
# Context-aware: requires explicit generalization intent
OVER_OPT_PATTERNS="(abstraire|généraliser|make it (abstract|configurable|generic|extensible)|future[- ]proof|pour (le futur|plus tard)|rends[- ]?(le )?(configurable|générique|abstrait))"

# Workflow enforcement: domain modeling without /craftsman:design
# FR: crée une entité|value object|agrégat
# EN: create entity|value object|aggregate
DOMAIN_MODELING_PATTERNS="(create (a |an |the )?(entity|value object|aggregate|domain event|domain service)|crée (une |un |l'?)?(entité|value object|agrégat|événement de domaine))"

# =============================================================================
# Detection & Warnings
# =============================================================================

WARNINGS=""

add_warning() {
    if [[ -n "$WARNINGS" ]]; then
        WARNINGS="${WARNINGS} | $1"
    else
        WARNINGS="$1"
    fi
}

warn_acceleration() {
    add_warning "Acceleration bias: You may be rushing. Consider: What behavior is expected? Should we use /craftsman:design first? What test would verify this works?"
}

warn_scope_creep() {
    add_warning "Scope Creep bias: Adding features beyond scope. Is this in the original requirement? Should this be a separate task? YAGNI."
}

warn_over_optimization() {
    add_warning "Over-Optimization bias: Premature abstraction. Do we have 3+ use cases? Make it work first. Concrete code > complex abstraction."
}

warn_missing_design() {
    add_warning "Workflow: Domain modeling without /craftsman:design. Run /craftsman:design to model the domain properly before creating entities."
}

# Check each pattern
echo "$PROMPT" | grep -iEq "$ACCELERATION_PATTERNS" && warn_acceleration || true
echo "$PROMPT" | grep -iEq "$SCOPE_CREEP_PATTERNS" && warn_scope_creep || true
echo "$PROMPT" | grep -iEq "$OVER_OPT_PATTERNS" && warn_over_optimization || true

# Workflow enforcement: warn if domain modeling without /craftsman:design
if echo "$PROMPT" | grep -iEq "$DOMAIN_MODELING_PATTERNS"; then
    design_used=false
    if [[ -f "$SESSION_STATE" ]]; then
        LIB_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/hooks/lib"
        design_used=$(python3 "$LIB_DIR/session_state.py" check-flag "$SESSION_STATE" design_used 2>/dev/null) || design_used=false
    fi
    if [[ "$design_used" != "true" ]]; then
        warn_missing_design
    fi
fi

# Output structured JSON if warnings were collected
if [[ -n "$WARNINGS" ]]; then
    jq -n --arg msg "$WARNINGS" '{
        systemMessage: $msg
    }'
fi

# Always exit 0 (warning only, never block)
exit 0
