# ADR-0020: Instinct Promotion With Human Review

## Status

Accepted (amended 2026-09-12: candidate gate and confidence, see Amendment)

## Date

2026-07-26

## Context

The Correction Learning System (differentiator #1) currently stops at observation: violations and corrections are recorded in SQLite, and correction trends are injected at session start. The loop never closes - a pattern the user has corrected twenty times is still only a "trend", not a rule Claude applies by default.

The ECC project's continuous-learning pipeline demonstrates the missing stages: observations are scored into "instincts" (confidence threshold 0.7), and mature instincts are promoted into generated skills. ECC promotes automatically. That design has a failure mode we refuse: a wrongly-inferred instinct, once codified, silently poisons every subsequent session, and nothing in the loop surfaces it for correction.

## Decision

v4.0.0 closes the learning loop with a human gate at the promotion step:

1. **Detection** (existing): violations and corrections recorded in SQLite via `metrics-query.py`.
2. **Candidate extraction** (new): when 3+ corrections share a pattern (same rule, same fix shape, across files), the pattern becomes a *candidate instinct* with a confidence score derived from occurrence count and consistency. (Amended 2026-09-12, see below.)
3. **Review** (new, human): `/craftsman:metrics` lists candidate instincts with evidence (the corrections that produced them). The user approves, edits, or rejects each candidate. Nothing activates without approval.
4. **Codification** (new): an approved instinct is generated as a skill in `.claude/skills/craftsman-learned/<slug>/SKILL.md` with `user-invocable: false`, so it loads as background knowledge when relevant. The generated file records its provenance (source corrections, approval date).
5. **Retirement**: learned skills are listed by `/craftsman:metrics` and can be deleted at any time; a rejected candidate is not re-proposed unless new evidence accumulates.

A configurable cap limits how many learned skills inject per session (see ADR-0021).

## Consequences

### Positive

- The plugin's headline differentiator becomes a complete loop: detect, learn, codify.
- Human review keeps precision high: no false instinct survives to pollute future sessions.
- Provenance in each generated skill makes learned behavior auditable and reversible.
- Learned skills are project-local (`.claude/skills/`), shareable with the team via git.

### Negative

- Requires user attention: candidates queue until reviewed. Mitigation: session-start summary mentions pending candidates without injecting their content.
- Slower codification than ECC's automatic promotion, by design.

### Neutral

- SQLite remains the system of record for metrics; generated skills are a projection of approved knowledge, not a second database.

## Alternatives Considered

### Alternative 1: Automatic promotion above a confidence threshold (ECC model)

Rejected: a false positive at threshold is codified silently. In a quality plugin, a wrong rule enforced consistently is worse than no rule.

### Alternative 2: Keep trend injection only (status quo)

Rejected: trends are advisory text that competes for attention in the session-start budget; codified skills load precisely when relevant and survive context compaction independently.

## Amendment (2026-09-12): the candidate gate reads rejections, and the confidence ranks

Measured on this repository's own database six weeks after the loop shipped
(#45): eight candidates, none reviewed, seven at exactly 0.95, and two of
them (PHP003 at 105 fixed against 167 ignored, PY002 at 54 against 99) were
rules users reject two times out of three. The extraction counted fixes alone,
and `0.5 + 0.05 x occurrences + 0.03 x files` capped at 0.95 saturated at nine
occurrences, so the list had no order to review by.

Step 2 is amended as follows; the human gate (steps 3 to 5) is unchanged.

- A rule is a candidate only when it was fixed MORE often than it was rejected
  (`ignored` or `scoped`; `overridden` and `open` say nothing about agreement).
  A rule rejected as often as it is applied is not a lesson to teach, it is a
  rule to relax (#44).
- A candidate the extraction no longer yields is withdrawn on the next refresh.
  Every earlier criterion was monotonic on an append-only table, so a candidate
  could never lapse; the acceptance bar is the first that can stop holding, and
  a row left behind kept its old score, stayed in the pending count and could be
  approved. A never-reviewed row carries no human decision. Approved and rejected
  rows are decisions and stay.
- The confidence is the Wilson lower bound (95%) of the acceptance rate. It is
  an order, not a bar: 101 fixes and no rejection score 0.96, 18 score 0.82,
  3 score 0.44, and 50 against 50 score 0.40, which would pass any bar that
  lets 3 against none through. The candidacy bar stays the point estimate a
  human can check by counting.

## References

- ADR-0021 (context budgets cap learned-skill injection)
- ECC continuous-learning v2 spec (reviewed 2026-07): hook observation, scoring, promotion pipeline
- CLAUDE.md: Correction Learning System differentiator
