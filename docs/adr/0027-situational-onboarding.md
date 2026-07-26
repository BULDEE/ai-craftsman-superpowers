# ADR-0027: Situational Onboarding - Observation First, Help Maximized

## Status

Accepted

## Date

2026-07-26

## Context

The plugin ships as a premium quality gate, assuming a senior craftsman audience: it enforces strict standards, assumes deep knowledge of Clean Architecture and DDD, and provides rules-first documentation. But the goal is to let non-experts produce secure, evolvable, debt-free code. A long onboarding questionnaire induces abandonment after 4-5 questions (the "wizard fatigue" phenomenon). Yet much of what setup asks is observable from the repository itself: stack, conventions, codemap, and signals of maturity (git history, presence of tests, presence of CI).

The plugin already generates project-specific conventions from git history (ADR-0022). `/craftsman:setup` already gathers global preferences once per machine. The question becomes: how can we maximize help (reducing jargon, appending doctrine on blocks, guiding beginners) while preserving exigency (the rules remain strict), and do so without ceremony?

## Decision

Implement situational onboarding in two stages: global workshop profile (once) and project-aware init (once per repo):

1. **Global workshop profile** (`/craftsman:setup --global`): Asked once per machine, written to `~/.claude/.craft-config.yml`. Gathers stacks and preferred tools (proposed by `tooling_detect` suggestion tables, e.g., "PHP testing: PHPUnit / Pest / Symphony?" defaults to PHPUnit if declared in composer.json). Power users can skip this and override it per project.

2. **Project init** (existing setup flow, extended): First reads observable signals without asking:
   - Stack (PHP/TypeScript/Python/Bash detection from file presence)
   - Conventions (git commit style, layout, test location via ADR-0022 machinery)
   - Codemap (top-level directories and layer structure)
   - Legacy signal: commit count (threshold: 20+ commits = "existing"), presence of tests (yes/no), presence of CI (yes/no)

   Then asks at most FOUR plain-language situational confirmations (not technical vocabulary):

   | # | Question | Derived from | Drives |
   |---|----------|--------------|--------|
   | 1 | "Existing project or new one?" | Prefilled from commit count + test absence signal | Ratchet baseline mode (photograph vs zero-tolerance) + legacy relaxations |
   | 2 | "Prototype or heading to production?" | None (user judgement) | Strictness (moderate vs strict) |
   | 3 | "Solo or team?" | None | CI templates proposal, doctrine export proposal |
   | 4 | "Prefer maximum help or maximum autonomy?" | None | Guided mode on/off |

   Derived config is SHOWN before writing (existing setup contract). `--quick` bypasses all confirmations (existing power-user escape hatch).

3. **Guided mode**: New config key `guided: true`. Gate exigency is UNCHANGED (same rules, same severity); help is MAXIMIZED:
   - Extended auto-fix where safe (e.g., add `declare(strict_types=1)` to a PHP file that lacks it)
   - Every block appends its OKF doctrine pointer with plain-language one-liner (e.g., "PHP001: Use `declare(strict_types=1)` at file top. [Why: strict types catch mismatches early. Learn more: knowledge/php/strict-types.md]")
   - Block messages use no jargon; expert-mode messages unchanged

## Consequences

### Positive

- Onboarding is not ceremony: everything observable stays observed (no questions about stack when we can see it). Only judgment calls (existing vs greenfield, prototype vs production) are asked.
- Guidance arrives at the moment of friction (on a gate block), not in setup wizard that users abandon. The gate teaches, reducing the need for separate training.
- Non-experts receive maximum help; experts are undisturbed (exigency is unchanged, guided mode is opt-out).
- Four-question hard cap prevents scope creep: once a project is initialized, no more questions.
- Ratchet baseline mode is derived from the legacy signal; no extra question needed.

### Negative

- "Existing project or new one?" prefilled from observation is a heuristic. A repo with 5 commits but production intent will self-correct in question 2; a repo with 200 commits and "I just scaffolded this" will be misclassified initially but remains fixable via `.craft-config.yml` override.
- Guided mode adds text to every block. On high-violation sessions, this increases noise. Expert users should disable guided mode; it is not mandatory.
- The doctrine pointers assume the knowledge bundle exists (ADR-0024). If `knowledge/` is missing or out of sync, links may not resolve. The existence check and graceful degradation are the responsibility of `knowledge_lookup.py`.

### Neutral

- Legacy mode does not weaken the gate: it relaxes directory-level strictness for existing code, but touched files are still ratcheted (ADR-0025).
- Guided mode is a per-project setting and can be toggled on/off at any time via config.

## Alternatives Considered

### Alternative 1: Longer wizard (8-10 situational questions)

Capture more context (testing framework, ORM choice, team size, security posture). Rejected: abandonment rises sharply after question 4. Everything beyond the four essential judgments should be observable or deferrable to config overrides.

### Alternative 2: Laxer beginner preset

Create a "beginner mode" with relaxed rules and lower strictness across the board. Rejected: produce mediocre code and label it "beginner safe," conditioning users to lower standards. The point is to help without lowering exigency. Guided mode increases help; it never decreases strictness.

### Alternative 3: No onboarding, all manual config

Require users to write `.craft-config.yml` by hand. Rejected: defeats the goal of letting non-experts produce good code. Observable signals must be observed (not redeclared), and guidance must be automatic (not opt-in).

## References

- ADR-0019 (established tooling first): tooling detection and optional features
- ADR-0020 (human review): gate design and severity levels
- ADR-0021 (budgets): cost models and cost-aware features
- ADR-0022 (project conventions): observational signal detection
- ADR-0024 (OKF knowledge bundle): knowledge routing and doctrine pointers
- ADR-0025 (structural ratchet): baseline mode decision from legacy signal
- hooks/lib/conventions.py: signal detection for stack, layout, tests, CI
- hooks/lib/tooling_detect.py: tool suggestion tables per stack
- knowledge_lookup.py: doctrine routing and guided-mode message synthesis
