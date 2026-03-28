#!/usr/bin/env bash
# =============================================================================
# Bias Detection Hook for Claude Code
# Detects cognitive biases in prompts and displays non-blocking warnings.
#
# SECURITY: This script only reads stdin and outputs warnings to stdout.
#           It does NOT modify files, execute commands, or access network.
# =============================================================================
set -euo pipefail

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
# FR: vite, rapide, rapidement, pas le temps, code direct
# EN: no time, just do it, skip, quick, hurry, asap, urgent
ACCELERATION_PATTERNS="(vite|rapide|rapidement|pas le temps|no time|just do it|code direct|skip|quick|hurry|asap|urgent)"

# Scope creep: adding features beyond scope
# FR: et aussi, tant qu'on y est, ajoutons, en plus
# EN: while we're at it, also add, let's also, and also
SCOPE_CREEP_PATTERNS="(et aussi|tant qu'on y est|ajoutons|en plus|while we're at it|also add|let's also|and also)"

# Over-optimization: premature abstraction
# FR: abstraire, généraliser
# EN: generalize, abstract, make it configurable, future-proof
OVER_OPT_PATTERNS="(abstraire|généraliser|generalize|abstract|make it configurable|future-proof)"

# Workflow enforcement: domain modeling without /craftsman:design
# FR: crée une entité|value object|agrégat
# EN: create entity|value object|aggregate
DOMAIN_MODELING_PATTERNS="(create (a |an |the )?(entity|value object|aggregate|domain event|domain service)|crée (une |un |l'?)?(entité|value object|agrégat|événement de domaine))"

# =============================================================================
# Detection & Warnings
# =============================================================================

warn_acceleration() {
    cat << 'EOF'

⚠️  BIAS DETECTED: Acceleration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You may be rushing. Consider:
  • What behavior is expected?
  • Should we use /craftsman:design first?
  • What test would verify this works?

EOF
}

warn_scope_creep() {
    cat << 'EOF'

⚠️  BIAS DETECTED: Scope Creep
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Adding features beyond scope. Consider:
  • Is this in the original requirement?
  • Should this be a separate task?
  • YAGNI: You Aren't Gonna Need It

EOF
}

warn_over_optimization() {
    cat << 'EOF'

⚠️  BIAS DETECTED: Over-Optimization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Premature abstraction detected. Consider:
  • Do we have 3+ use cases for this?
  • Make it work → make it right → make it fast
  • Concrete code > complex abstraction

EOF
}

warn_missing_design() {
    cat << 'EOF'

⚠️  WORKFLOW SUGGESTION: Domain Modeling
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You are creating domain objects without running /craftsman:design first.
Consider:
  • Run /craftsman:design to model the domain properly
  • Define bounded contexts and aggregate boundaries first
  • Identify Value Objects before writing entities

EOF
}

# Check each pattern
echo "$PROMPT" | grep -iEq "$ACCELERATION_PATTERNS" && warn_acceleration || true
echo "$PROMPT" | grep -iEq "$SCOPE_CREEP_PATTERNS" && warn_scope_creep || true
echo "$PROMPT" | grep -iEq "$OVER_OPT_PATTERNS" && warn_over_optimization || true

# Workflow enforcement: warn if domain modeling without /craftsman:design
if echo "$PROMPT" | grep -iEq "$DOMAIN_MODELING_PATTERNS"; then
    design_used=false
    if [[ -f "$SESSION_STATE" ]]; then
        design_used=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
print('true' if state.get('design_used', False) else 'false')
" "$SESSION_STATE" 2>/dev/null) || design_used=false
    fi
    if [[ "$design_used" != "true" ]]; then
        warn_missing_design
    fi
fi

# Always exit 0 (warning only, never block)
exit 0
