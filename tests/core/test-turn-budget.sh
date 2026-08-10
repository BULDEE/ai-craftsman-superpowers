#!/usr/bin/env bash
# =============================================================================
# An agent that runs out of turns must still deliver.
#
# `/craftsman:challenge` forked into `craftsman:architect`, which declared
# `maxTurns: 20`. When the cap is reached the agent loop stops wherever it is,
# and if the last action was a tool call the caller receives nothing at all: no
# report, no error, no partial. Claude Code then substitutes the literal string
# "Command completed" for the missing result and returns `shouldQuery: false`,
# so the session prints that and falls silent.
#
# Measured on 38 recorded runs of this one agent: 15 delivered, 23 did not.
# Every truncated subagent transcript on the machine was this agent, every one
# stopped at exactly 20 turns with `stop_reason: tool_use`, and no other agent
# type ever did. The cap was not the whole defect - an agent that spends its
# budget reading and keeps none for writing fails at any cap - so this suite
# asserts the contract, not the number.
#
# The second invariant here is `isolation: worktree` on a read-only agent. A
# worktree is a clean checkout of a commit: `git status --porcelain` inside one
# is empty while the repository it came from is dirty. An agent asked to review
# `git diff HEAD` from inside one reviews a tree where that diff does not
# exist, and it pays worktree setup for a directory it never writes to.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

FIXTURE_DIR="$CLAUDE_PLUGIN_DATA/turn-budget-fixtures"
mkdir -p "$FIXTURE_DIR"

frontmatter() {
    awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$1"
}

# The phrase is the contract, not decoration: it is the one instruction that
# turns "I ran out of budget" into "I shipped what I had".
BUDGET_CLAUSE='never let your final action be a tool call'

declares_max_turns() {
    frontmatter "$1" | grep -q '^maxTurns:[[:space:]]*[0-9]'
}

# Returns 0 when the agent carries the delivery contract.
has_budget_contract() {
    grep -q '^## Turn Budget' "$1" && grep -qi "$BUDGET_CLAUSE" "$1"
}

declared_tools() {
    frontmatter "$1" | awk '/^tools:/{inside=1;next}
                            inside && /^[[:space:]]*-[[:space:]]/{sub(/^[[:space:]]*-[[:space:]]*/,"");print;next}
                            inside{exit}'
}

# Returns 0 when the agent cannot write to the filesystem.
is_read_only() {
    ! declared_tools "$1" | grep -qE '^(Write|Edit|NotebookEdit)$'
}

isolates_in_worktree() {
    frontmatter "$1" | grep -q '^isolation:[[:space:]]*worktree'
}

AGENT_FILES=$(find "$ROOT_DIR/agents" "$ROOT_DIR/packs" -name '*.md' -path '*agents*' 2>/dev/null \
    | while read -r f; do [[ -L "$f" ]] || echo "$f"; done | sort)

echo ""
echo "=== Every capped agent carries the delivery contract ==="

CAPPED_CHECKED=0
for agent_file in $AGENT_FILES; do
    declares_max_turns "$agent_file" || continue
    CAPPED_CHECKED=$((CAPPED_CHECKED + 1))
    rel="${agent_file#"$ROOT_DIR"/}"
    cap="$(frontmatter "$agent_file" | sed -n 's/^maxTurns:[[:space:]]*//p' | head -1)"

    if has_budget_contract "$agent_file"; then
        log_pass "$rel (maxTurns: $cap) reserves budget for its deliverable"
    else
        log_fail "$rel declares maxTurns: $cap" \
            "no '## Turn Budget' section stating '$BUDGET_CLAUSE' - it can end mid-tool-call and return nothing"
    fi
done

if [[ $CAPPED_CHECKED -eq 0 ]]; then
    log_fail "no agent declares maxTurns" "the check above verified nothing"
fi

echo ""
echo "=== The contract check goes RED on an agent that lacks it ==="

# A guard never seen red proves nothing. Feed the same predicates an agent that
# is capped and silent, and an agent that is capped and correct.
cat > "$FIXTURE_DIR/silent.md" <<'FIXTURE'
---
name: silent
description: capped agent with no delivery contract
model: opus
maxTurns: 20
tools:
  - Read
---

# Silent Agent

Read everything, then report.
FIXTURE

cat > "$FIXTURE_DIR/speaks.md" <<'FIXTURE'
---
name: speaks
description: capped agent that reserves budget
model: opus
maxTurns: 20
tools:
  - Read
---

# Speaking Agent

## Turn Budget

Emit the deliverable before the budget ends.
Never let your final action be a tool call.
FIXTURE

if declares_max_turns "$FIXTURE_DIR/silent.md" && ! has_budget_contract "$FIXTURE_DIR/silent.md"; then
    log_pass "capped agent without the contract is rejected"
else
    log_fail "capped agent without the contract passed" \
        "the contract check cannot fail, so its green means nothing"
fi

if has_budget_contract "$FIXTURE_DIR/speaks.md"; then
    log_pass "capped agent with the contract is accepted"
else
    log_fail "capped agent with the contract was rejected" "the check rejects everything"
fi

echo ""
echo "=== A read-only agent never isolates into a worktree ==="

READONLY_CHECKED=0
for agent_file in $AGENT_FILES; do
    is_read_only "$agent_file" || continue
    READONLY_CHECKED=$((READONLY_CHECKED + 1))
    rel="${agent_file#"$ROOT_DIR"/}"

    if isolates_in_worktree "$agent_file"; then
        log_fail "$rel is read-only and declares isolation: worktree" \
            "a worktree is a clean checkout - uncommitted work is absent from it, and the agent never writes anyway"
    else
        log_pass "$rel is read-only and reviews the real working tree"
    fi
done

if [[ $READONLY_CHECKED -eq 0 ]]; then
    log_fail "no read-only agent found" "the check above verified nothing"
fi

echo ""
echo "=== The worktree check goes RED on a read-only agent that isolates ==="

cat > "$FIXTURE_DIR/isolated-reader.md" <<'FIXTURE'
---
name: isolated-reader
description: read-only agent isolated into a worktree
model: opus
isolation: worktree
tools:
  - Read
  - Grep
---

# Isolated Reader
FIXTURE

cat > "$FIXTURE_DIR/isolated-writer.md" <<'FIXTURE'
---
name: isolated-writer
description: writing agent isolated into a worktree
model: opus
isolation: worktree
tools:
  - Read
  - Write
  - Edit
---

# Isolated Writer
FIXTURE

if is_read_only "$FIXTURE_DIR/isolated-reader.md" && isolates_in_worktree "$FIXTURE_DIR/isolated-reader.md"; then
    log_pass "read-only agent in a worktree is detected"
else
    log_fail "read-only agent in a worktree went undetected" \
        "the worktree check cannot fail, so its green means nothing"
fi

if ! is_read_only "$FIXTURE_DIR/isolated-writer.md"; then
    log_pass "a writing agent keeps its worktree isolation"
else
    log_fail "writing agent read as read-only" "the check would strip isolation from agents that need it"
fi

echo ""
echo "=== No skill forks into an agent that can return nothing ==="

agent_file_for() {
    local name="${1#craftsman:}" candidate
    for candidate in "$ROOT_DIR/agents/$name.md" "$ROOT_DIR"/packs/*/agents/"$name".md; do
        [[ -f "$candidate" ]] && { echo "$candidate"; return 0; }
    done
    return 1
}

# `context: fork` hands the whole user turn to a subagent. When that subagent
# returns nothing, Claude Code prints "Command completed" and stops: no error
# reaches the user, and no retry is possible. A fork is therefore only legal
# into an agent that is contractually incapable of silence.
FORK_OFFENDERS=""
for skill_md in "$ROOT_DIR"/skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    skill_fm="$(frontmatter "$skill_md")"
    echo "$skill_fm" | grep -q '^context:[[:space:]]*fork' || continue
    bound="$(echo "$skill_fm" | sed -n 's/^agent:[[:space:]]*//p' | head -1)"
    [[ -n "$bound" ]] || continue
    rel="${skill_md#"$ROOT_DIR"/}"

    agent_md="$(agent_file_for "$bound")" || {
        log_fail "$rel forks into $bound" "no agent definition found"
        continue
    }
    if has_budget_contract "$agent_md"; then
        log_pass "$rel forks into $bound, which always delivers"
    else
        FORK_OFFENDERS="$FORK_OFFENDERS $rel"
        log_fail "$rel forks into $bound" \
            "$bound has no delivery contract - a silent return surfaces as 'Command completed' and the turn ends"
    fi
done

if [[ -z "$FORK_OFFENDERS" ]]; then
    log_pass "no skill forks into a silent agent"
fi

test_summary
