#!/usr/bin/env bash
# =============================================================================
# Nothing may point at a skill it cannot start.
#
# /craftsman:workflow told the model "Invoking /craftsman:design..." for four
# steps, and five agents declared skills in frontmatter, while sixteen of the
# twenty-two skills carry disable-model-invocation: true. The model has no legal
# path to those: the Skill tool answers "cannot be used with Skill tool due to
# disable-model-invocation" and the workflow dies mid-pipeline. Nothing caught
# it because no test crossed a reference with its target's invocation policy.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Frontmatter only: a fenced example of a locked skill in the body is prose,
# not a declaration, and must not read as one.
frontmatter() {
    awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$1"
}

skill_file() {
    echo "$ROOT_DIR/skills/${1#craftsman:}/SKILL.md"
}

skill_is_locked() {
    local target
    target="$(skill_file "$1")"
    [[ -f "$target" ]] || return 1
    frontmatter "$target" | grep -q '^disable-model-invocation:[[:space:]]*true'
}

# The agent a skill forks into, if any. An agent declaring such a skill would
# fork into itself.
skill_bound_agent() {
    local target
    target="$(skill_file "$1")"
    [[ -f "$target" ]] || return 0
    frontmatter "$target" | sed -n 's/^agent:[[:space:]]*//p' | head -1
}

agent_declared_skills() {
    awk '/^skills:/{inside=1;next}
         inside && /^[[:space:]]*-[[:space:]]/{sub(/^[[:space:]]*-[[:space:]]*/,"");print;next}
         inside{exit}' "$1"
}

echo ""
echo "=== Agent frontmatter only declares skills the agent can start ==="

AGENT_FILES=$(find "$ROOT_DIR/agents" "$ROOT_DIR/packs" -name '*.md' -path '*agents*' 2>/dev/null | sort)
DECLARED_TOTAL=0

for agent_file in $AGENT_FILES; do
    agent_name="$(frontmatter "$agent_file" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
    [[ -n "$agent_name" ]] || agent_name="$(basename "$agent_file" .md)"
    rel="${agent_file#"$ROOT_DIR"/}"

    for declared in $(agent_declared_skills "$agent_file"); do
        DECLARED_TOTAL=$((DECLARED_TOTAL + 1))
        target="$(skill_file "$declared")"

        if [[ ! -f "$target" ]]; then
            log_fail "$rel declares $declared" "no such skill: ${target#"$ROOT_DIR"/}"
            continue
        fi
        if skill_is_locked "$declared"; then
            log_fail "$rel declares $declared" \
                "$declared has disable-model-invocation: true - the agent can never start it"
            continue
        fi
        bound="$(skill_bound_agent "$declared")"
        if [[ "${bound#craftsman:}" == "$agent_name" ]]; then
            log_fail "$rel declares $declared" \
                "$declared is bound to agent $bound - declaring it here forks the agent into itself"
            continue
        fi
        log_pass "$rel declares $declared (invocable, no self-fork)"
    done
done

if [[ $DECLARED_TOTAL -eq 0 ]]; then
    log_fail "no agent skill declaration found" "the check above verified nothing"
fi

echo ""
echo "=== No skill claims to invoke a skill the model cannot invoke ==="

INVOKES_TOTAL=0

for skill_md in "$ROOT_DIR"/skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    rel="${skill_md#"$ROOT_DIR"/}"

    claims=$(grep -oE '^\*\*Invokes:\*\*.*/craftsman:[a-z-]+' "$skill_md" \
        | grep -oE '/craftsman:[a-z-]+' | sort -u)

    for claim in $claims; do
        INVOKES_TOTAL=$((INVOKES_TOTAL + 1))
        name="craftsman:${claim#/craftsman:}"

        if [[ ! -f "$(skill_file "$name")" ]]; then
            log_fail "$rel claims to invoke $claim" "no such skill"
        elif skill_is_locked "$name"; then
            log_fail "$rel claims to invoke $claim" \
                "$name is user-invoked only - say 'Hands off to' and print the command instead"
        else
            log_pass "$rel claims to invoke $claim (invocable)"
        fi
    done
done

if [[ $INVOKES_TOTAL -eq 0 ]]; then
    log_fail "no '**Invokes:**' claim found" "the check above verified nothing"
fi

echo ""
echo "=== A forking skill and its bound agent declare the same model ==="

# The platform does not document which model wins when a skill says `model: X`
# and its `agent:`-bound definition says `model: Y`. Ambiguity here means the
# review may silently run a tier below what the docs promise. The only safe
# state is agreement.
agent_file_for() {
    local name="${1#craftsman:}" candidate
    for candidate in "$ROOT_DIR/agents/$name.md" "$ROOT_DIR"/packs/*/agents/"$name".md; do
        [[ -f "$candidate" ]] && { echo "$candidate"; return 0; }
    done
    return 1
}

FORKS_CHECKED=0
for skill_md in "$ROOT_DIR"/skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    skill_fm="$(frontmatter "$skill_md")"
    echo "$skill_fm" | grep -q '^context:[[:space:]]*fork' || continue
    bound="$(echo "$skill_fm" | sed -n 's/^agent:[[:space:]]*//p' | head -1)"
    [[ -n "$bound" ]] || continue

    FORKS_CHECKED=$((FORKS_CHECKED + 1))
    rel="${skill_md#"$ROOT_DIR"/}"
    skill_model="$(echo "$skill_fm" | sed -n 's/^model:[[:space:]]*//p' | head -1)"

    agent_md="$(agent_file_for "$bound")" || {
        log_fail "$rel forks into $bound" "no agent definition found"
        continue
    }
    agent_model="$(frontmatter "$agent_md" | sed -n 's/^model:[[:space:]]*//p' | head -1)"

    if [[ -n "$skill_model" && "$skill_model" == "$agent_model" ]]; then
        log_pass "$rel and $bound agree on model: $skill_model"
    else
        log_fail "$rel forks into $bound" \
            "skill declares model '$skill_model', agent declares '$agent_model' - precedence is undocumented, they must agree"
    fi
done

if [[ $FORKS_CHECKED -eq 0 ]]; then
    log_fail "no forking skill found" "the check above verified nothing"
fi

echo ""
echo "=== /craftsman:team stays model-invocable ==="

if skill_is_locked "craftsman:team"; then
    log_fail "craftsman:team is locked" \
        "the workflow orchestrator is documented as able to start it"
else
    log_pass "craftsman:team is model-invocable"
fi

# Interactive, and TeamCreate spawns teammates into the live session. A fork
# would strand both.
if frontmatter "$(skill_file craftsman:team)" | grep -q '^context:[[:space:]]*fork'; then
    log_fail "craftsman:team runs in a fork" \
        "it asks the user questions and calls TeamCreate - both need the main session"
else
    log_pass "craftsman:team runs in the main session"
fi

test_summary
