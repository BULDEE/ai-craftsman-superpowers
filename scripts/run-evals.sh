#!/usr/bin/env bash
# =============================================================================
# The eval suite, run deliberately.
#
# Not part of tests/run-tests.sh, and that is the whole point of a separate
# entry point: every case here is a real model call on the caller's account
# (the eval documentation says so plainly), while tests/run-tests.sh must stay
# free and offline so it can run on every write. What this measures is the half
# tests/ cannot reach: whether the routing table and the skill descriptions
# make the model pick the skill a situation calls for.
#
# Usage:
#   bash scripts/run-evals.sh              # the routing suite, with the baseline arm
#   bash scripts/run-evals.sh --fast       # one run per case, no baseline arm, cheapest
#   bash scripts/run-evals.sh --case routing-debug
#   bash scripts/run-evals.sh --json out.json --threshold 0.8    # what CI would do
#
# Any option after the first is passed through to `claude plugin eval`.
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

# Pinned, because a model rollout must not read as a plugin regression. The
# same reason the latency benchmark pins its basket.
MODEL="${CRAFTSMAN_EVAL_MODEL:-claude-sonnet-5}"
# 0.8 on the routing suite: a routing table is advice, not a gate, so the model
# may reasonably answer without starting the skill. Below 4 runs in 5 it is not
# steering anything. The reasoning per suite is in evals/README.md.
THRESHOLD="${CRAFTSMAN_EVAL_THRESHOLD:-0.8}"
# A ceiling, not a budget: past it nothing further starts and the result is
# marked partial, which gates nothing. Measured while the suite was written:
# $0.77 for a case that does a turn of real work, $0.08 for one answered
# directly, and the default two-arm run doubles whatever the cases cost.
MAX_COST="${CRAFTSMAN_EVAL_MAX_COST:-25}"

if ! command -v claude >/dev/null 2>&1; then
    echo "scripts/run-evals.sh: the claude CLI is not on PATH, and the suite is only real when it runs it." >&2
    exit 1
fi

ARGS=(--trust-plugin --no-publish --model "$MODEL" --threshold "$THRESHOLD" --max-cost-usd "$MAX_COST")

if [[ "${1:-}" == "--fast" ]]; then
    shift
    # One run per arm and no baseline: for iterating on a grader, never for a
    # verdict. One run of a non-deterministic agent tells you little.
    ARGS+=(--runs 1 --ablation none)
    echo "fast mode: 1 run per case, no baseline arm. Not a verdict, an iteration."
fi

echo "evals: model ${MODEL}, threshold ${THRESHOLD}, cost ceiling ${MAX_COST} USD"
echo "every case is a model call on your account; results land in evals/results/"
exec claude plugin eval . "${ARGS[@]}" "$@"
