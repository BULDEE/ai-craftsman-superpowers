# ADR-0011: Context Fork Strategy

## Status

Accepted, amended 2026-08-10 by
[ADR-0028](./0028-review-runs-in-the-main-session.md), which removes `challenge`
from the forking set. The three benefits claimed below did not hold for a skill
that delivers a verdict to the user: the fork dropped the attachments and the
conversation it needed for scope, and one run in two returned nothing while
Claude Code reported `Command completed`. The rest of the table stands.

## Date

2025-02-04

## Context

Claude Code supports running skills in isolated contexts using `context: fork`. This creates a subagent with its own context, separate from the main conversation.

We need to decide which skills should run in forked contexts.

## Decision

Use `context: fork` for skills that:
1. Perform standalone analysis (don't need conversation history)
2. May produce large outputs (avoid context pollution)
3. Benefit from fresh perspective (unbiased analysis)

### Skills with context: fork

| Skill | Agent Type | Reason |
|-------|------------|--------|
| `debug` | general-purpose | Investigation is self-contained |
| `refactor` | general-purpose | Changes are isolated |
| `plan` | Plan | Planning is comprehensive task |
| `mlops` | Explore | Audit explores codebase |

A skill that delivers a verdict to the user does not belong here: see ADR-0028.
Any addition to this table must clear `tests/core/test-turn-budget.sh`, which
refuses a fork into an agent that can return nothing.

### Skills WITHOUT context: fork

| Skill | Reason |
|-------|--------|
| `design` | Needs user interaction for phases |
| `test` | Works with current code context |
| `git` | Operates on current changes |
| `verify` | Quick checks on current state |
| Scaffolding skills | Write files in current context |

## Agent Type Selection

When using `context: fork`, select appropriate agent:

- **general-purpose**: Default for most tasks
- **Plan**: For planning-specific tasks
- **Explore**: For read-only codebase analysis

## Consequences

### Positive
- Cleaner main conversation context
- Skills can use full context budget
- Unbiased analysis without prior context

### Negative
- No access to conversation history
- Results must be summarized back
- Slight latency increase

## References

- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents)
- [ADR-0010: Model Tiering](./0010-model-tiering.md)
