#!/usr/bin/env bash
# =============================================================================
# Team templates must only name agents that exist.
#
# Three templates spawned "architecture-reviewer", an agent this repository has
# never shipped, and the docs described it in detail. Nothing caught it because
# nothing compared the two lists.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo ""
echo "=== Team templates reference real agents ==="

KNOWN=$(for f in "$ROOT_DIR"/agents/*.md "$ROOT_DIR"/packs/*/agents/*.md; do
    [[ -f "$f" ]] || continue
    grep -m1 "^name:" "$f" | sed 's/^name:[[:space:]]*//'
done | sort -u)

if [[ -z "$KNOWN" ]]; then
    log_fail "no agent declares a name" "the comparison below would pass vacuously"
    test_summary
fi

TEMPLATE_COUNT=0
for template in "$ROOT_DIR"/teams/templates/*.yml; do
    [[ -f "$template" ]] || continue
    TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
    name="$(basename "$template")"

    referenced=$(grep -oE "^[[:space:]]+- agent: [a-z0-9-]+" "$template" \
        | sed 's/.*: //' | sort -u)

    if [[ -z "$referenced" ]]; then
        log_fail "$name" "declares no agent, so the template spawns nobody"
        continue
    fi

    unknown=""
    while IFS= read -r agent; do
        [[ -n "$agent" ]] || continue
        printf '%s\n' "$KNOWN" | grep -qx "$agent" || unknown="${unknown} ${agent}"
    done <<< "$referenced"

    if [[ -z "$unknown" ]]; then
        log_pass "$name: every agent it names exists"
    else
        log_fail "$name" "names agents that do not exist:${unknown}"
    fi
done

if [[ $TEMPLATE_COUNT -gt 0 ]]; then
    log_pass "found ${TEMPLATE_COUNT} team template(s) to check"
else
    log_fail "no team template found" "the loop above verified nothing"
fi

# The same name has to work from the docs a reader copies out of.
echo ""
echo "=== The agent reference documents no agent that is missing ==="

DOC="$ROOT_DIR/docs/reference/agents.md"
if [[ -f "$DOC" ]]; then
    missing=""
    while IFS= read -r heading; do
        agent="${heading##\#\#\# }"
        [[ "$agent" =~ ^[a-z0-9-]+$ ]] || continue
        printf '%s\n' "$KNOWN" | grep -qx "$agent" || missing="${missing} ${agent}"
    done < <(grep -E "^### [a-z0-9-]+$" "$DOC")

    if [[ -z "$missing" ]]; then
        log_pass "every agent given its own section is a real agent"
    else
        log_fail "docs/reference/agents.md" "documents agents that do not exist:${missing}"
    fi
else
    log_fail "docs/reference/agents.md missing" "nothing to check"
fi

test_summary
