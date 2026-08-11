---
model: opus
description: "Bounded goal-driven loop over the craftsman verify gate. Use for ratchet campaigns, red-to-green test runs, violation burn-down: any task shaped as act, verify, repeat until a Done-when condition holds. Every iteration re-verifies; the loop stops on green, on no-progress, or when the budget is spent."
effort: high
disable-model-invocation: true
---

# /craftsman:loop - Bounded Verification Loop

## Outcome Contract

- **Outcome**: the loop card's verify command green, or an explicit stop verdict (no_progress or budget spent) with the remaining gap named.
- **Done when**: a stop condition fired, the final verify output is shown, and the iteration ledger reports what changed on each pass.
- **Evidence**: the verify command's output per iteration, and the diff each iteration produced.

## Philosophy

The loop doctrine behind Claude Code is gather context, act, verify, repeat,
and its first rule is: reach for a workflow before an agent. This skill is
the "repeat" layer on top of the `/craftsman:workflow` pipeline, never a
replacement for it. The judge is the plugin's existing gate (tests, ratchet,
rules engine), so the loop inherits exactly the verdict the hooks and CI
already enforce. What the loop adds is cadence and a stop condition; it adds
no new authority.

## Loop Card

Built first, shown to the user before any iteration runs.

| Field | Meaning | Default |
|-------|---------|---------|
| goal | one sentence, outcome form | required |
| verify | one command whose exit code is the verdict | required |
| max_iterations | hard cap on passes | 5 |
| stop_on | green, no_progress (2 identical failures), budget | all three |
| escalate | the question a human answers when the loop stops red | required |

Rules the card cannot override:

- The verify command is the ONLY judge. No iteration may weaken it: editing
  the test, raising a ratchet budget, or relaxing a rule to get to green is
  entombing the regression, not fixing it.
- One iteration is the smallest change that could flip the verdict, then a
  full verify. Batching acts between verifies turns the loop into a blind
  batch edit.
- No new scope inside the loop. A discovery becomes a ledger note for the
  next pipeline run, never a new goal mid-loop.

## Process

1. **Card**: build the loop card from the user's brief. Missing verify
   command: ask; never invent one.
2. **Baseline**: run verify once, record the starting verdict and failure
   set. A loop without a red baseline has nothing to fix: stop and say so.
3. **Iterate**: act (one atomic change), run verify, append one ledger line:
   `iteration N: <verdict> - <what changed> - <delta vs previous>`.
4. **Stop** on the first of: verify green (success), two consecutive
   iterations with an identical failure set (no_progress), max_iterations
   reached (budget).
5. **Deliver**: final verdict, the full ledger, the remaining gap when red,
   and the card's escalation question when the loop stopped short of green.

## Cross-Turn Cadence

For work that must recur across turns or wait on external state (a CI run, a
long build, a deploy), this skill only defines the card; the cadence belongs
to the native loop runner. Hands off to: the user types `/loop` with the
loop card pasted as the prompt, choosing the interval or letting it
self-pace. In-session iteration above is the default; the native runner is
for cadence a single session turn cannot hold open.

## Delivery Is Not Optional

The loop ends with a verdict every time: green, no_progress, or budget
spent. A loop that ends silently teaches the user to distrust the command,
so never let the last action be a tool call; the ledger and the verdict are
the report.

## Bias Protection

**Acceleration:** skipping verify between acts to "save iterations" makes
the final verdict belong to nobody. One act, one verify, no exceptions.

**Scope creep:** the loop optimizes exactly one verdict. Everything else it
notices is ledger material for the next `/craftsman:plan`.

**Comprehension debt:** a green loop the user never read still shipped
changes. The ledger names every diff so the human can read what the loop
did, and the escalate field exists because stopping red is a human decision,
not a failure of the loop.
