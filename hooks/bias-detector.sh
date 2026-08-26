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
# Bias Patterns - loaded from hooks/lib/bias-patterns/<lang>.conf (ADR-0030).
# The detector knows the categories; the languages live in data.
# =============================================================================

LIB_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/hooks/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/bias-registry.sh"
bias_registry_init "${CRAFTSMAN_BIAS_PATTERNS_DIR:-$LIB_DIR/bias-patterns}"

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

# Check each curated category. bias_combined_pattern returns non-zero when no
# language declares a category, and the grep MUST be skipped then: an empty
# pattern matches every prompt.
if pat=$(bias_combined_pattern ACCELERATION curated); then
    echo "$PROMPT" | grep -iEq "$pat" && warn_acceleration || true
fi
if pat=$(bias_combined_pattern SCOPE_CREEP curated); then
    echo "$PROMPT" | grep -iEq "$pat" && warn_scope_creep || true
fi
if pat=$(bias_combined_pattern OVER_OPT curated); then
    echo "$PROMPT" | grep -iEq "$pat" && warn_over_optimization || true
fi

# Workflow enforcement: warn if domain modeling without /craftsman:design
if pat=$(bias_combined_pattern DOMAIN_MODELING curated) && echo "$PROMPT" | grep -iEq "$pat"; then
    design_used=false
    if [[ -f "$SESSION_STATE" ]]; then
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
