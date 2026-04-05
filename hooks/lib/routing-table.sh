#!/usr/bin/env bash
# =============================================================================
# Routing Table — Dynamic command suggestion for Claude's context
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
- Git commit, branch, merge, workflow → /craftsman:git
- Check plugin health, diagnose issues → /craftsman:healthcheck
- Before claiming work is done → /craftsman:verify
- Full development cycle, new feature, guided methodology → /craftsman:workflow
- First time setup, quick onboarding → /craftsman:setup --quick"
}

_register_pack_routes() {
    local packs="$1"
    local routes=""
    if echo "$packs" | grep -q "ai-ml"; then
        routes="${routes}
- Manage knowledge base, add/sync documents → /craftsman:knowledge
- Design RAG pipeline, semantic search → /craftsman:rag
- Design AI agent, autonomous workflow → /craftsman:agent-design
- ML pipeline audit, production readiness → /craftsman:mlops"
    fi
    if echo "$packs" | grep -q "symfony"; then
        routes="${routes}
- Scaffold PHP entity, use case, repository → /craftsman:scaffold"
    fi
    if echo "$packs" | grep -q "react"; then
        routes="${routes}
- Scaffold React component, hook, branded type → /craftsman:scaffold"
    fi
    echo "$routes"
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
    echo "CRAFTSMAN COMMANDS — Suggest these when context matches (do NOT auto-execute, propose to user):${routes}${sp_note}"
}
