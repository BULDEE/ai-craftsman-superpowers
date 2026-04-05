#!/usr/bin/env bash
# =============================================================================
# Tests for /craftsman:workflow command
# Validates frontmatter, content structure, and step definitions.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORKFLOW_CMD="$ROOT_DIR/commands/workflow.md"

echo ""
echo "=== Workflow Command Tests ==="

# --- Frontmatter ---

if [[ -f "$WORKFLOW_CMD" ]]; then
    log_pass "workflow.md exists"
else
    log_fail "workflow.md missing"
    test_summary
fi

if head -1 "$WORKFLOW_CMD" | grep -q "^---$"; then
    log_pass "has YAML frontmatter"
else
    log_fail "missing YAML frontmatter"
fi

if grep -q '^description:' "$WORKFLOW_CMD"; then
    log_pass "has description field"
else
    log_fail "missing description field"
fi

if grep -q '^effort:' "$WORKFLOW_CMD"; then
    log_pass "has effort field"
else
    log_fail "missing effort field"
fi

effort_val=$(grep '^effort:' "$WORKFLOW_CMD" | head -1 | sed 's/effort: *//')
if [[ "$effort_val" =~ ^(quick|medium|heavy)$ ]]; then
    log_pass "effort is valid: $effort_val"
else
    log_fail "invalid effort value: $effort_val" "must be quick|medium|heavy"
fi

# --- No name field (per plugin convention) ---

if ! grep -q '^name:' "$WORKFLOW_CMD"; then
    log_pass "no name field (correct per plugin convention)"
else
    log_fail "has name field (should not per plugin convention)"
fi

# --- Pipeline Steps ---

for step in design spec plan implement test verify commit; do
    if grep -qi "### Step.*: $step" "$WORKFLOW_CMD"; then
        log_pass "pipeline step defined: $step"
    else
        log_fail "pipeline step missing: $step"
    fi
done

# --- Modes ---

if grep -q '\-\-from' "$WORKFLOW_CMD"; then
    log_pass "--from flag documented"
else
    log_fail "--from flag not documented"
fi

if grep -q '\-\-skip' "$WORKFLOW_CMD"; then
    log_pass "--skip flag documented"
else
    log_fail "--skip flag not documented"
fi

# --- Gate Pattern ---

if grep -q 'Y/skip/stop' "$WORKFLOW_CMD"; then
    log_pass "gate confirmation pattern present (Y/skip/stop)"
else
    log_fail "missing gate confirmation pattern"
fi

# --- Progress Tracking ---

if grep -q 'Pipeline Progress' "$WORKFLOW_CMD"; then
    log_pass "progress tracking section present"
else
    log_fail "missing progress tracking section"
fi

# --- Error Handling ---

if grep -q 'Error Handling' "$WORKFLOW_CMD"; then
    log_pass "error handling section present"
else
    log_fail "missing error handling section"
fi

# --- Bias Protection ---

if grep -q 'Bias Protection' "$WORKFLOW_CMD"; then
    log_pass "bias protection section present"
else
    log_fail "missing bias protection section"
fi

# --- Skill Invocations ---

for skill in design spec plan test verify git; do
    if grep -q "/craftsman:$skill" "$WORKFLOW_CMD"; then
        log_pass "invokes /craftsman:$skill"
    else
        log_fail "missing invocation of /craftsman:$skill"
    fi
done

# --- Line count ---

line_count=$(wc -l < "$WORKFLOW_CMD")
if [[ $line_count -lt 500 ]]; then
    log_pass "under 500 lines ($line_count lines)"
else
    log_fail "over 500 lines ($line_count lines)" "consider splitting per ADR-0012"
fi

test_summary
