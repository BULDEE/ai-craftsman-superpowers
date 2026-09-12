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
- Iterate until green: ratchet campaign, red-test burn-down, bounded fix loop → /craftsman:loop
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

# Which table a route belongs to (#48).
#
# A skill with `disable-model-invocation: true` starts only when the user types
# `/craftsman:<name>` first in a prompt; the Skill tool refuses it. Fifteen of
# the twenty-two skills are locked that way, and the table used to print all of
# them as one flat list "to suggest", as though it were a dispatch table: a
# model reading fifteen commands it cannot call either tries and fails or learns
# to ignore the block. The frontmatter is the authority, read here rather than
# copied, so a skill that changes its policy moves table on its own.
_route_skill_file() {
    local name="$1" root candidate
    root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    if [[ -f "$root/skills/$name/SKILL.md" ]]; then
        printf '%s' "$root/skills/$name/SKILL.md"
        return 0
    fi
    # A pack command before pack_sync_symlinks has linked it into skills/.
    for candidate in "$root"/packs/*/commands/"$name".md; do
        [[ -f "$candidate" ]] || continue
        printf '%s' "$candidate"
        return 0
    done
    return 1
}

_route_is_model_invocable() {
    local file
    # No skill file at all: not something the model can call.
    file=$(_route_skill_file "$1") || return 1
    ! awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$file" \
        | grep -q '^disable-model-invocation:[[:space:]]*true'
}

_route_command_name() {
    local line="$1"
    line="${line##*/craftsman:}"
    line="${line%% *}"
    printf '%s' "${line%%(*}"
}

routing_table() {
    local packs
    packs=$(pack_loaded 2>/dev/null || echo "")
    local routes=""
    routes="${routes}$(_register_core_routes)"
    routes="${routes}$(_register_pack_routes "$packs")"
    local invocable="" typed="" line name
    while IFS= read -r line; do
        [[ "$line" == "- "* ]] || continue
        name=$(_route_command_name "$line")
        if _route_is_model_invocable "$name"; then
            invocable="${invocable}
${line}"
        else
            typed="${typed}
${line}"
        fi
    done <<< "$routes"
    local sp_note=""
    sp_note=$(_detect_superpowers_synergy)
    echo "CRAFTSMAN COMMANDS - two tables, because the Skill tool refuses a skill locked with disable-model-invocation.
Invoke yourself (Skill tool) when the context matches:${invocable}
Suggest to the user, who types it (do NOT auto-execute, propose to user; the Skill tool refuses these):${typed}${sp_note}"
}
