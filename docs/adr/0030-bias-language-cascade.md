# ADR-0030: Bias Detection Language Cascade

## Status

Accepted. Design approved 2026-08-26; implementation to follow this record.

## Date

2026-08-26

## Context

`hooks/bias-detector.sh` detects cognitive biases (acceleration, scope creep,
over-optimization, domain modeling without design) in user prompts, FR/EN
only, through four hardcoded regex variables. Issue #10 asks for a third
language; PR #11 answers by editing those variables inline plus three more
files. Every further language repeats a four-file touch, needs a bilingual
author able to write context-aware patterns, and lands unreviewable by a
maintainer who does not speak it.

The trajectory is also typologically wrong, not merely expensive. Half of the
languages worth supporting cannot be served by word-boundary regex at any
cost: CJK and Thai write without spaces (segmentation is itself an NLP
problem, and substring matches inside unrelated compounds fire constantly);
agglutinative morphology (Turkish, Korean) stacks the whole bias signal into
one inflected word ("yapıverelim": "let's just quickly do it"). And
`grep -i` beyond ASCII is locale-dependent, measured on macOS BSD grep
2.6.0: `RÉFLÉCHIR` matches `réfléchir` under `fr_FR.UTF-8` and does not
under `LC_ALL=C` (CI runners, minimal shells); explicit case variants match
under both.

The goal is every language at non-exponential cost, not three languages.

## Decision

A two-stage cascade. Stage 1 is a deterministic, data-driven signal net in
the hook; stage 2 is the main model adjudicating in context. No second model
is ever invoked.

### Stage 1: signal net (hook, <10ms, all languages)

One pattern file per language under `hooks/lib/bias-patterns/<lang>.conf`,
loaded by a new `hooks/lib/bias-registry.sh`. Files are shell-sourced (no
python3, no new process on the prompt path) and declare one mode each:

- **curated**: context-aware regex exactly as today, earning the right to
  warn directly. EN and FR (moved, byte-identical), ES (PR #11's content,
  recycled).
- **signal**: a plain alternation of bias lexemes (快点, 빨리, schnell,
  hızlı, быстро, รีบ, nhanh, ...). Recall-oriented; precision is explicitly
  not required of it. Authoring one is translating a word list: minutes of
  work, reviewable without native fluency, the "good first issue" shape
  issue #10 wanted.

```bash
# hooks/lib/bias-patterns/de.conf
BIAS_REGISTERED_LANGS+=("de")
BIAS_DE_MODE="signal"
BIAS_DE_ACCELERATION="schnell|sofort|keine [Zz]eit|mach einfach"
BIAS_DE_SCOPE_CREEP="und (auch|außerdem)|wo wir (gerade|schon) dabei sind"
BIAS_DE_OVER_OPT="generisch|abstrahier|konfigurierbar|zukunftssicher"
BIAS_DE_DOMAIN_MODELING="[Ee]ntität|[Aa]ggregat|Value[- ]Object"
```

Registry contract:

- `bias_registry_init <dir>` sources every `*.conf`; iteration state lives in
  `BIAS_REGISTERED_LANGS`, values are read through bash 3.2 indirect
  expansion (`${!varname}`); no associative arrays.
- `bias_combined_pattern <CATEGORY> <mode>` prints the joined alternation and
  returns non-zero when no language declares the category. The caller skips
  the grep entirely on non-zero: an empty pattern handed to `grep -E`
  matches every prompt, and a dedicated test re-introduces that bug to prove
  the guard fails red.
- Case variants are declared explicitly (`[Ee]ntität`, `(быстро|Быстро)`);
  `grep -i` is never trusted beyond ASCII because its case folding is
  locale-dependent (measured above). Signal matching is plain substring,
  correct for unsegmented scripts (CJK/Thai substring matches verified on
  BSD grep under both UTF-8 and C locales) and an accepted FP source
  elsewhere.

### Stage 2: main-model adjudication (semantic, zero marginal cost)

Per category: a curated match emits today's warning through `systemMessage`,
unchanged. A signal match emits no verdict; the hook prints an adjudication
note as plain stdout, which UserPromptSubmit adds to the conversation as
context the model can see (per the official hooks reference, the
UserPromptSubmit JSON schema carries only `blockPrompt`, `blockPromptReason`
and `systemMessage`; there is no `additionalContext` field for this event,
and plain stdout is the documented context channel):

> Bias signal (acceleration): lexeme "빨리" matched in the user's prompt.
> The matcher has no conversation context; you have all of it. If the user is
> genuinely rushing past design, surface the acceleration-bias warning in
> their language. If the match is incidental (quoted text, descriptive use,
> topic discussion), ignore this note silently and never mention it.

One run emits one output format, never both: stdout is parsed as a single
payload, so the curated JSON and the plain-text note are mutually exclusive.
Curated warnings take priority; the signal note is emitted only when no
curated warning fired at all.

`domain_modeling`, from either tier, keeps the existing
`session_state.py check-flag design_used` gate. The lexeme quoted in the note
is extracted with `grep -oE` against the plugin's own alternation, so the
extractable text is constrained to vocabulary the plugin ships: the note is
not an injection channel for user text.

## Consequences

- False-positive economics flip, and that is the unlock: today a false
  positive is a user-visible warning (enough of them and the hook gets
  disabled); a signal-tier false positive is a note the model dismisses
  silently. Stage 1 recall can be cranked high, which is exactly what makes
  per-language authoring cheap.
- The judge has context. "hazlo rápido" after two hours of careful design is
  not acceleration bias; only the main model can know that. Zero added
  latency, zero cost, every language the model reads.
- The hook stays a hook: no network, no python3, no model call, no new
  failure mode on the prompt path. Its security header stays true.
- Curated EN/FR/ES behavior is byte-for-byte preserved; the 23 existing
  bias tests migrate with identical semantics.
- Instruction-decay is answered structurally: doctrine is re-injected at the
  exact moment a trigger fires, instead of fading from a SessionStart
  preamble 100k tokens back.

## Alternatives rejected

1. **Per-language context-aware regex, generalized** (PR #11's direction):
   authoring tax unchanged, unreviewable, typologically impossible for
   CJK/Thai/agglutinative morphology.
2. **Headless Haiku fallback (`haiku_verify`) when regex is silent**:
   economically inverted. Clean prompts are the overwhelming majority and are
   exactly the ones that leave regex silent, so the model would run on ~95%
   of traffic and skip the biased minority. Transport reality is worse:
   a one-token Haiku classification through `claude -p --max-turns 1`
   measures 10.2s and 11.6s wall-clock on an M-series machine, so a 1.5s
   sync timeout kills essentially every call after charging its latency to
   every clean prompt. UserPromptSubmit hooks cannot run async (official
   hooks reference), so the latency cannot be hidden either. A headless
   classifier is also context-blind.
3. **Direct API call from the hook**: breaks the hook's "no network" posture,
   assumes an API key subscription users may not have.
4. **Local lightweight classifier** (fastText-style): the standard production
   answer, and massive over-engineering for an advisory nudge in a bash
   plugin (weights, Python runtime, training data). YAGNI.
5. **SessionStart standing doctrine only**: free and language-open, but decays
   with context distance and never re-surfaces at the trigger moment. Its
   insight (the main model is the judge) is kept; the per-prompt signal is
   the attention mechanism that makes it reliable.

## Test plan

No test ever spawns a model subprocess (same doctrine as
`test-design-panel.sh`): the hook's testable contract ends at the note it
emits.

- `tests/core/test-bias-registry.sh` (new): multi-file aggregation, mode
  separation, add-a-language-without-touching-code via a fixture conf in a
  temp dir, and the empty-category guard proven able to fail.
- `tests/core/test-bias-detector.sh` (rewritten data-driven): fixtures under
  `tests/fixtures/bias/<lang>.cases`, `expect|<category>|<tier>|<prompt>` and
  `silent|<prompt>` lines. Signal languages each carry one positive per
  category landing in the plain-stdout note, one uppercase-initial positive,
  and clean-prompt silent cases. A clean ASCII English prompt fires nothing
  in either tier. A prompt with any curated warning emits the JSON warning
  and no signal note at all (exclusive output formats).

## Rollout

1. `bias-registry.sh` plus EN/FR extraction into curated conf files: pure
   refactor, existing tests stay green unmodified.
2. `es.conf` carrying PR #11's patterns and fixtures, with authorship credit.
3. Signal mode plus the `additionalContext` adjudication path.
4. Seed signal files (de, pt, it, tr, ru, vi, zh, ja, ko, th) marked as
   recall-oriented seed lists; native-speaker refinement becomes the new
   good-first-issue surface.
5. Docs: `docs/reference/hooks.md` bias table, README language claim, CHANGELOG.

Non-goals: no prompt-language routing (both combined patterns simply run:
eight cheap greps at most), no SQLite logging of stage-1 fires until a
consumer exists for the data, no per-language precision guarantee at signal
tier.
