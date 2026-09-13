# Eval suite: does the plugin steer the model to the right skill?

`tests/` proves the gate is deterministic: a rule fires, a severity resolves, a
hook exits 2. None of it measures the half that only a model can answer, which
is whether the routing table and the skill descriptions make Claude pick the
skill a situation calls for. That half has been asserted in the README since the
first release and measured never, and issue #48 is the one that said so.

This suite is the measurement. It runs with `claude plugin eval`, which spends
real model calls on your account, so it is NOT part of `tests/run-tests.sh`:
that suite stays free and offline. Run this one deliberately.

## Run it

```bash
bash scripts/run-evals.sh            # the routing suite, no judge model, delta on
bash scripts/run-evals.sh --fast     # one run per case, no baseline arm
claude plugin eval . --case routing-debug   # one case, verbose
```

## What it costs, measured

Two cases were run while this suite was written, on `claude plugin eval`
2.1.270, and these are their real figures rather than an estimate:

| Case | Runs | Wall clock | Cost |
|---|---|---|---|
| `routing-agent-design` (a design question, 1 turn of real work) | 1 | 96s | $0.77 |
| `routing-none` (the counter-example, answered directly) | 1 | 6s | $0.08 |

The spread between them is the point: a case costs what the work costs, so the
suite's total depends on which cases run, and the default two-arm run doubles
it. The runner sets a `--max-cost-usd` ceiling for that reason. Past the
ceiling nothing further starts and the result is marked `partial: true`, which
is not a verdict: a partial run belongs in no trend and gates nothing.

**The full suite has never been run end to end.** Two cases were verified to
load and grade; the other six are written against the same documented format
and have not been executed.

## What is measured, and what a score means

Every case pairs two graders, which is what the eval documentation prescribes:
one on HOW Claude got there (`tool_used: Skill`, did the right skill fire) and
one on the OUTCOME (a `regex` over the final message). The pairing matters
because the two answer different questions and only one of them is comparable
against the no-plugin baseline: a "the skill fired" grader can never pass
without the plugin, so `claude plugin eval` excludes it from the score in both
arms and reports it as an indicator. The outcome grader is what `Δ` is computed
from.

No `llm` grader in this suite, on purpose. A judge model costs a call per
grader per run and its verdict moves between runs, and everything here can be
settled by a regex or by the transcript. That is the cheapest rung of the
grading ladder, and the rung that does not drift.

## The thresholds, and where they come from

| Suite | Threshold | Why that number |
|---|---|---|
| routing (`tags: [routing]`) | 0.8 | A routing table is advice, not a gate: the model may reasonably answer a debugging question without starting the skill. Below 4 runs in 5 the table is not steering anything. |
| counter-example (`tags: [routing, counter-example]`) | 1.0 | A skill that fires when nothing asked for it is a false positive the user pays for on every unrelated prompt, and `min: 0, max: 0` is a check the model either respects or does not. |

Thresholds come from what the behaviour is worth, not from what the suite first
scored. When a case is raised, the reason goes in this table.

## Keeping it honest

- **Counter-examples are cases.** `routing-none` asserts that no craftsman
  skill fires on a prompt none of them owns, scored in both arms (`arm: both`),
  because a suite of positive cases only measures eagerness.
- **The locked skills are not in scope.** Sixteen of the twenty-two skills carry
  `disable-model-invocation: true`, so the Skill tool refuses them and no eval
  can make one fire. Routing for those is a suggestion printed to the user, and
  `tests/core/test-routing-table.sh` is what checks they sit in the right table.
- **A failure here is usually a description, not a bug.** When
  `tool_used: Skill` fails and `Δ` is near zero, the eval documentation's own
  reading applies: the skill's `description` does not trigger on that phrasing.
  Fix the description, re-run the same suite, do not rewrite the case to match
  the behaviour. A case edited until it passes measures nothing.
- **Results are not committed.** `evals/results/` is generated, and
  `.gitignore` says so.
- **The model is pinned.** `--model claude-sonnet-5` by default, the same
  reason `tests/perf/test-hook-latency.sh` pins its calibration basket: a model
  rollout must not read as a plugin regression. Override with
  `CRAFTSMAN_EVAL_MODEL` when the question IS how a new model behaves.

## What this suite does not measure

Naming it is part of the measurement. It says nothing about whether a rule is
right, whether a blocked write leads to a better fix, or whether a learned
skill helps: those need a golden dataset of verdicts, which the correction loop
does not record yet (it records what the user did, never what was correct). It
covers the six model-invocable skills only; the sixteen locked ones can never
fire from a prompt, and `tests/core/test-routing-table.sh` is what holds them
in the right table.
