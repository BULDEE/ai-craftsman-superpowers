# ADR-0022: Setup by Observation - Generated Conventions and Codemap

## Status

Accepted

## Date

2026-07-26

## Context

`/craftsman:setup` configures the plugin by asking the user questions (stack, strictness, packs), with `--quick` applying defaults (ADR-0014). But most answers already exist in the repository: the git history shows the commit convention, the tree shows the layout and test placement, the code shows the dominant patterns.

Separately, review agents (`architect`, `legacy-surgeon`) re-explore the repository from scratch on every invocation, spending their subagent budget on discovering structure that has not changed since the last run.

ECC demonstrates both remedies: a conventions skill generated from repository analysis ("500 analyzed commits"), and cached codemaps injected into agents.

## Decision

Two generated artifacts, both produced by `/craftsman:setup` in v4.0.0:

1. **Project conventions skill**: setup analyzes the git log (commit style, prefixes in use) and the tree (layout, test location, naming patterns, dominant frameworks), then generates `.claude/skills/project-conventions/SKILL.md` with `user-invocable: false`. The file records its generation date and inputs. Setup still asks only what observation cannot determine (strictness preference, pack opt-ins). Regeneration is explicit (`/craftsman:setup --refresh`), never silent.

2. **Codemap**: a compact structural map of the repository (directories, key modules, entry points, dependency direction) generated at setup and refreshed at SessionStart when the tree changed (cached by content hash). Review skills inject it via dynamic context (`` !`craftsman-codemap` ``), so forked reviewers start with the map instead of exploring cold.

Both artifacts count against the context budgets of ADR-0021.

## Consequences

### Positive

- Setup time drops; answers derived from evidence instead of user recall.
- Generated conventions are visible, editable files: the user corrects the skill, not a hidden inference.
- Forked reviewers spend their budget on judgment instead of rediscovery.
- Conventions skill is shareable with the team via git.

### Negative

- Generation heuristics can misread unconventional repositories; mitigated by the artifacts being plain editable markdown and setup showing what it inferred before writing.
- Codemap freshness adds a cache-invalidation concern (content-hash based, worst case a stale map for one session).

### Neutral

- Monorepos get one codemap per registered working directory.

## Alternatives Considered

### Alternative 1: Full questionnaire (status quo)

Rejected: asks the user to restate facts the repository states better, and the answers go stale as the repo evolves.

### Alternative 2: Live exploration by each agent (status quo for reviewers)

Rejected: repeated cost per invocation, and each agent rediscovers a slightly different picture; a shared map gives reviewers a consistent baseline.

## References

- ADR-0014 (quick setup mode, extended by observation)
- ADR-0021 (budgets applied to generated artifacts)
- ECC conventions-skill generation and codemaps (reviewed 2026-07)
