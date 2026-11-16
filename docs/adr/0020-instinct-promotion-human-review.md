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
4. **Codification** (new): an approved instinct is generated as a skill in `.claude/skills/<slug>/SKILL.md` with `user-invocable: false`, so it loads as background knowledge when relevant. The generated file records its provenance (source corrections, approval date).
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
- "Across files" counts FILES. The extraction counted `corrections.file_pattern`,
  a directory glob, so the threshold was a count of directories: a rule fixed in
  twenty files of one directory counted as one, and measured on a real database
  23 PHP001 fixes under one glob produced no candidate at all. It counts
  `corrections.file_path`, the exact file, which only the semantic layer used to
  record; the Level 1 loop now records it too.
- The confidence is the Wilson lower bound (95%) of the acceptance rate. It is
  an order, not a bar: 101 fixes and no rejection score 0.96, 18 score 0.82,
  3 score 0.44, and 50 against 50 score 0.40, which would pass any bar that
  lets 3 against none through. The candidacy bar stays the point estimate a
  human can check by counting.

## References

- ADR-0021 (context budgets cap learned-skill injection)
- ECC continuous-learning v2 spec (reviewed 2026-07): hook observation, scoring, promotion pipeline
- CLAUDE.md: Correction Learning System differentiator

## Amendment (2026-09-13): the skill is written where Claude Code reads

Step 4 named `.claude/skills/craftsman-learned/<slug>/SKILL.md`. Claude Code
loads a project skill from `.claude/skills/<name>/SKILL.md` and from nowhere
deeper (skills reference; measured with `claude -p --debug`: two project
skills on disk, one at each depth, loaded as `project: 1`). Every approval
since this ADR produced a file the model never saw, and the test checked
that the file existed rather than that the consumer loaded it. `approve` now
writes to `.claude/skills/learned-<slug>/`, refuses any other depth by name,
and SessionStart names the files left at the old one with the `mv` to make.

## Amendment (2026-09-14): `scoped` has a writer, and the global tier is named

The 2026-09-12 amendment counted `scoped` as a rejection while no front-end
wrote it. `post-write-check.sh` writes it since 4.10.1 (#73): a rule gone
from a write's findings because its severity resolved to `warn` or `ignore`
for that file records `scoped`, and one the baseline mark held records
`overridden`; only a rule still blocking that is now gone records `fixed`.

The global promotion tier (`instincts.py promote`, `global-candidates`: a
rule approved in two or more independent projects becomes a user-level skill
under `~/.claude/skills/learned-global-<slug>/`) shipped without a home in
this ADR. It is part of this decision: approval stays per project, and only
agreement across projects earns a skill that follows the user.

## Amendment (2026-11-16): a refusal before the write is a finding

The loop learns from a blocking finding that a later write no longer carries.
Post-write was the only place a blocking finding was recorded and left
pending. Since 4.10.2 (a9b0f51, ADR-0029's single gate for every front-end)
the pre-write gate judges every pack rule on a mirror and refuses the write,
so a blocking finding almost never lands. The gate dropped its findings, on
the reading that metrics belonged after the write. Post-write then saw no
blocking finding to answer, and the loop starved without an error. On one
production database, under daily use, blocking findings fell from 2,928 in
July to 8 in November and `fixed` corrections from 176 in August to 3. The
ratio of corrections to recorded blocking findings stayed between 5 and 52
percent: the writer worked, its input was gone. The suite could not see it,
because every case fed post-write a file the gate would have refused, a
sequence no host produces any more.

Decision: a refused finding is recorded as blocking (`violations`,
`blocked=1`) and left pending on its file in the session state, the shape
post-write gives a blocked write. The next accepted write answers it through
`_check_corrections`, unchanged. Four details hold this honest:

- The real file comes from the mirror's own resolution (`write_mirror.py
  --targets`): the payload's cwd, the workspace of each file of a patch. A
  suffix match gave one package's finding to another that held the same
  relative path.
- The key is `session_pending_key`, shared by both hooks, so a file refused in
  a directory that does not exist yet keys as it will once it lands.
- A refusal adds to what the file owes (`record-violation --keep`). A rule a
  second proposal dropped was not answered by a write that landed, and
  replacing the list lost it.
- Warnings stay post-write's: their file lands, and recording them before the
  write as well would count them twice.

A recording that fails says so on the refusal's stderr and never costs the
refusal. The rows go through the metrics queue, one insert per refusal. The
cost is paid on the refusal path only, about 170 ms on one file, measured.

A rejected proposal followed by an accepted write that no longer carries the
rule records `fixed`, even when the accepted write is a different change. This
is the meaning post-write always gave the word: the finding is no longer in
what landed. A cross review asked for provenance to tell a withdrawn proposal
from a repaired file. It is not recorded yet.

`tests/core/test-correction-learning.sh` now runs both hooks in host order for
each write shape (Claude Code `Write` and `Edit`, Codex `apply_patch`, Grok
`search_replace` on a relative path), plus a two-package patch, a payload cwd
apart from the hook's, and a second refusal that drops a rule. It fails on the
code before this amendment and when the recording is removed again.
