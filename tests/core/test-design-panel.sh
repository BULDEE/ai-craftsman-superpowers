#!/usr/bin/env bash
# =============================================================================
# Adversarial Design Panel tests (ADR-0026).
# Gates only: these tests MUST never spawn a real Haiku subprocess. Every case
# below exits before `haiku_verify` is reachable (gate off, recursion guard,
# missing design file) or inspects the script text.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

PANEL="$ROOT_DIR/hooks/design-panel.sh"
DESIGN="/tmp/craftsman-panel-design-$$.md"
echo "# Design: User aggregate with email VO" > "$DESIGN"

echo "=== Adversarial design panel (gates) ==="

EXIT_CODE=0
OUT=$(CLAUDE_PLUGIN_OPTION_agent_hooks=false bash "$PANEL" "$DESIGN" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 && -z "$OUT" ]]; then
    log_pass "agent_hooks=false: silent exit 0"
else
    log_fail "gate" "exit=$EXIT_CODE out=$OUT"
fi

EXIT_CODE=0
OUT=$(CRAFTSMAN_HEADLESS_VERIFY=1 CLAUDE_PLUGIN_OPTION_agent_hooks=true bash "$PANEL" "$DESIGN" 2>&1) || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 && -z "$OUT" ]]; then
    log_pass "recursion guard: silent exit 0"
else
    log_fail "recursion guard" "exit=$EXIT_CODE out=$OUT"
fi

EXIT_CODE=0
bash "$PANEL" /nonexistent-design.md >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "missing design file: non-blocking exit 0"
else
    log_fail "missing file" "exit=$EXIT_CODE"
fi

EXIT_CODE=0
bash "$PANEL" >/dev/null 2>&1 || EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "no argument: non-blocking exit 0"
else
    log_fail "no argument" "exit=$EXIT_CODE"
fi

if grep -q "panel: 3 Haiku calls" "$PANEL"; then
    log_pass "cost announcement present in script"
else
    log_fail "cost display" "missing announcement"
fi

if grep -q "LENS" "$PANEL" && \
   grep -q "yagni" "$PANEL" && \
   grep -q "invariants" "$PANEL" && \
   grep -q "feasibility" "$PANEL"; then
    log_pass "three lenses declared (yagni, invariants, feasibility)"
else
    log_fail "lenses" "missing one of the three lenses"
fi

rm -f "$DESIGN"
test_summary
