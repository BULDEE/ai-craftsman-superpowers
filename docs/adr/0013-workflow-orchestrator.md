# ADR-0013: Flexible Workflow Orchestrator

## Status

Accepted

## Date

2026-04-05

## Context

Competitor analysis (Claude Buddy v5) revealed that guided sequential workflows lower onboarding friction. Their 7-step linear pipeline (foundation -> spec -> plan -> tasks -> implement -> commit -> docs) is intuitive for newcomers.

However, our philosophy is "the craftsman chooses their tools." A rigid pipeline contradicts our core identity.

We needed a middle ground: structured guidance without forced compliance.

## Decision

Add `/craftsman:workflow` as a **flexible orchestrator** with a 7-step pipeline:

```
design -> spec -> plan -> implement -> test -> verify -> commit
```

Key design choices:

1. **Flexible entry point:** `--from <step>` allows starting at any step
2. **Skippable steps:** `--skip <step>` allows bypassing steps
3. **Gate pattern:** Each step asks `[Y/skip/stop]` before proceeding
4. **No enforcement:** The orchestrator suggests, never blocks
5. **Step 4 (implement) is free-form:** No skill invoked, craftsman codes freely
6. **Step 6 (verify) recommended but skippable:** Consistent with existing `/craftsman:verify`

### Why Not Rigid?

- Our users are senior developers who know when to skip design (bug fix)
- Rigid pipelines create friction for experienced users
- Our hooks already enforce quality (real-time validation), so the pipeline doesn't need to

### Why Not Just Documentation?

- A command provides discoverability (routing table, autocomplete)
- Progress tracking gives structure without rigidity
- Gate pattern creates natural checkpoints

## Consequences

### Positive
- Lower onboarding friction for new users
- Structured methodology for complex features
- Compatible with existing skills (each step invokes existing commands)
- No new infrastructure needed (pure command markdown)

### Negative
- One more command to maintain
- Risk of being ignored by experienced users (acceptable)
- Progress tracking limited to session scope

## References

- Competitor analysis: Claude Buddy v5 sequential workflow
- [ADR-0007: Commands over Skills](0007-commands-over-skills.md)
