#!/usr/bin/env bash
# =============================================================================
# Tests for routing table library
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-test-rt-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"
pack_loader_init 2>/dev/null || true

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Routing Table Tests ==="

source "$ROOT_DIR/hooks/lib/routing-table.sh"

# Test: routing_table produces output
output=$(routing_table)
if [[ -n "$output" ]]; then
    log_pass "routing_table produces non-empty output"
else
    log_fail "routing_table should produce output"
fi

# Test: output contains CRAFTSMAN COMMANDS header
if echo "$output" | grep -q "CRAFTSMAN COMMANDS"; then
    log_pass "output contains CRAFTSMAN COMMANDS header"
else
    log_fail "output should contain CRAFTSMAN COMMANDS header"
fi

# Test: core commands always present
for cmd in debug team design spec plan challenge refactor legacy git healthcheck verify; do
    if echo "$output" | grep -q "/craftsman:${cmd}"; then
        log_pass "core command /craftsman:${cmd} present"
    else
        log_fail "core command /craftsman:${cmd} should be present"
    fi
done

# Test: routing mentions trigger contexts (not just command names)
if echo "$output" | grep -q "Bug.*error.*crash"; then
    log_pass "routing contains trigger context for debug"
else
    log_fail "routing should contain trigger context for debug"
fi

# Test: output contains do-not-auto-execute instruction
if echo "$output" | grep -qi "do NOT auto-execute\|propose to user"; then
    log_pass "routing contains non-execution instruction"
else
    log_fail "routing should instruct not to auto-execute"
fi

# Test: the table says which of its commands the model can call (#48).
#
# Fifteen of the twenty-two skills are locked with disable-model-invocation,
# and a flat list of commands "to suggest" read as a dispatch table for the
# model. Two tables now, partitioned from the frontmatter itself: every route
# is checked against the SKILL.md it names, so a skill that changes policy
# cannot end up in the wrong table.
skill_locked() {
    local file="$ROOT_DIR/skills/$1/SKILL.md" candidate
    if [[ ! -f "$file" ]]; then
        for candidate in "$ROOT_DIR"/packs/*/commands/"$1".md; do
            [[ -f "$candidate" ]] && { file="$candidate"; break; }
        done
    fi
    [[ -f "$file" ]] || return 0
    awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$file" \
        | grep -q '^disable-model-invocation:[[:space:]]*true'
}

if echo "$output" | grep -q "^Invoke yourself (Skill tool)" \
    && echo "$output" | grep -q "^Suggest to the user, who types it"; then
    log_pass "the table is two tables: invoke yourself, suggest to the user"
else
    log_fail "the table is two tables: invoke yourself, suggest to the user"
fi

INVOCABLE_SECTION="$(echo "$output" | awk '/^Invoke yourself/{f=1;next} /^Suggest to the user/{f=0} f')"
TYPED_SECTION="$(echo "$output" | awk '/^Suggest to the user/{f=1;next} /^SYNERGY/{f=0} f')"
MISPLACED=""
while IFS= read -r line; do
    [[ "$line" == "- "* ]] || continue
    name="${line##*/craftsman:}"; name="${name%% *}"; name="${name%%(*}"
    skill_locked "$name" && MISPLACED="${MISPLACED} ${name}"
done <<< "$INVOCABLE_SECTION"
if [[ -z "${MISPLACED// /}" ]]; then
    log_pass "no locked skill is listed as something the model can invoke"
else
    log_fail "no locked skill is listed as something the model can invoke" "locked but listed:${MISPLACED}"
fi
MISPLACED=""
while IFS= read -r line; do
    [[ "$line" == "- "* ]] || continue
    name="${line##*/craftsman:}"; name="${name%% *}"; name="${name%%(*}"
    skill_locked "$name" || MISPLACED="${MISPLACED} ${name}"
done <<< "$TYPED_SECTION"
if [[ -z "${MISPLACED// /}" ]]; then
    log_pass "no model-invocable skill is hidden in the user-typed table"
else
    log_fail "no model-invocable skill is hidden in the user-typed table" "invocable but listed:${MISPLACED}"
fi
if echo "$INVOCABLE_SECTION" | grep -q "/craftsman:debug" && echo "$TYPED_SECTION" | grep -q "/craftsman:refactor"; then
    log_pass "debug is invocable and refactor is user-typed, as their frontmatter says"
else
    log_fail "debug is invocable and refactor is user-typed, as their frontmatter says"
fi

echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
