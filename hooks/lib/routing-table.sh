#!/usr/bin/env bash
# =============================================================================
# Routing Table - Dynamic command suggestion for Claude's context
#
# Generates a context-aware routing block that instructs Claude when to
# suggest each craftsman command. Adapts to loaded packs.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/routing-table.sh"
#   routing_table   # Returns the routing block string
# =============================================================================

_register_core_routes() {
    echo "
- Bug, error, crash, test failure, unexpected behavior → /craftsman:debug
- 2+ independent tasks, multi-agent work, backend+frontend feature → /craftsman:team
- New entity, value object, aggregate, domain modeling → /craftsman:design
- Before coding a feature, new component → /craftsman:spec (TDD)
- Multi-step feature, migration, large refactoring → /craftsman:plan
- Code review, PR review, architecture audit → /craftsman:challenge
- Improving existing code, tech debt, code smells → /craftsman:refactor
- Inherit/tame legacy, untested code, characterization tests, strangler migration → /craftsman:legacy
- Git commit, branch, merge, workflow → /craftsman:git
- Check plugin health, diagnose issues → /craftsman:healthcheck
- Before claiming work is done → /craftsman:verify
- Full development cycle, new feature, guided methodology → /craftsman:workflow
- First time setup, quick onboarding → /craftsman:setup --quick"
}

# Suggestions a pack contributes, read from its own manifest.
#
# This matched pack names as literals, so a pack the engine had not been taught
# about never appeared in the routing table however many commands it shipped.
# A pack declares them itself:
#
#   routes:
#     - trigger: "Design RAG pipeline, semantic search"
#       command: "/craftsman:rag"
_register_pack_routes() {
    # Called with no argument by a caller that loaded no pack. Under `set -u`
    # an unguarded $1 aborts the whole function, and routing_table then emits
    # nothing at all: the core routes disappear along with the pack ones.
    local packs="${1:-}"
    local routes="" pack_dir manifest trigger command
    [[ -z "$packs" ]] && { echo ""; return 0; }
    for pack_dir in "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"/packs/*/; do
        manifest="${pack_dir}pack.yml"
        [[ -f "$manifest" ]] || continue
        # Only packs the stack admitted, same gate as dispatch and doctrine.
        echo "$packs" | grep -q "$(basename "${pack_dir%/}")" || continue
        while IFS=$'\t' read -r trigger command; do
            [[ -z "$trigger" || -z "$command" ]] && continue
            routes="${routes}
- ${trigger} → ${command}"
        done <<< "$(_pack_route_pairs "$manifest")"
    done
    echo "$routes"
}

# trigger<TAB>command, one route per line.
_pack_route_pairs() {
    awk '
        /^routes:/ { inside = 1; next }
        inside && /^[a-zA-Z]/ { inside = 0 }
        inside && /trigger:/ {
            line = $0
            sub(/^[^:]*:[[:space:]]*"?/, "", line); sub(/"[[:space:]]*$/, "", line)
            trigger = line
        }
        inside && /command:/ {
            line = $0
            sub(/^[^:]*:[[:space:]]*"?/, "", line); sub(/"[[:space:]]*$/, "", line)
            if (trigger != "") { print trigger "\t" line; trigger = "" }
        }
    ' "$1" 2>/dev/null
}

_detect_superpowers_synergy() {
    if [[ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers" ]] || \
       [[ -d "${HOME}/.claude/plugins/superpowers" ]]; then
        echo "
SYNERGY: Superpowers plugin detected. Craftsman quality gates activate automatically on Superpowers workflows.
- Use Superpowers for workflow: brainstorming → writing-plans → subagent-driven-development
- Craftsman hooks validate every Write/Edit in real-time (Level 1-3 quality gates)
- Correction learning tracks patterns across subagent work
- Use /craftsman:challenge after implementation for architecture review"
    fi
}

routing_table() {
    local packs
    packs=$(pack_loaded 2>/dev/null || echo "")
    local routes=""
    routes="${routes}$(_register_core_routes)"
    routes="${routes}$(_register_pack_routes "$packs")"
    local sp_note=""
    sp_note=$(_detect_superpowers_synergy)
    echo "CRAFTSMAN COMMANDS - Suggest these when context matches (do NOT auto-execute, propose to user):${routes}${sp_note}"
}
