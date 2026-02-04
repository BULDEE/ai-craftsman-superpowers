# ADR-001: Model Tiering Strategy

## Status

Accepted

## Date

2025-02-04

## Context

Claude Code supports multiple models (Haiku, Sonnet, Opus) with different capabilities and costs. Skills can specify which model to use via the `model:` frontmatter field.

We need to decide how to assign models to skills for optimal balance between:
- **Quality**: Complex tasks need more capable models
- **Speed**: Simple tasks benefit from faster models
- **Cost**: More capable models are more expensive

## Decision

We implement a **tiered model strategy** based on task complexity:

### Tier 1: Haiku (Fast, Simple)
- `verify` - Quick validation checks
- `git` - Standard git operations

### Tier 2: Sonnet (Balanced, Default)
- `design` - Domain modeling (structured process)
- `test` - Test writing
- `spec` - Specification writing
- `component` - React component scaffolding
- `entity` - DDD entity scaffolding
- `usecase` - Use case scaffolding
- `hook` - React hook scaffolding
- `debug` - Systematic debugging (with fork)
- `refactor` - Code refactoring (with fork)

### Tier 3: Opus (Complex, Critical)
- `challenge` - Architecture review (needs deep analysis)
- `plan` - Strategic planning (complex reasoning)
- `parallel` - Agent orchestration (coordination)
- `rag` - RAG pipeline design (architectural)
- `mlops` - ML infrastructure audit (specialized)
- `agent-design` - AI agent architecture (complex)

## Rationale

### Why Haiku for verify/git?
- Tasks are procedural, not creative
- Speed matters for developer flow
- Quality requirements are lower (check commands, not generate code)

### Why Sonnet as default?
- Good balance of quality and speed
- Sufficient for most development tasks
- Cost-effective for high-frequency operations

### Why Opus for critical skills?
- Architecture decisions have long-term impact
- Code review requires deep understanding
- Planning needs comprehensive reasoning
- Worth the extra cost for quality

## Context: Fork Usage

Some skills also use `context: fork` for isolation:
- `debug` - Investigation should not pollute main context
- `refactor` - Changes are self-contained
- `challenge` - Review should be independent
- `plan` - Planning benefits from fresh context
- `mlops` - Audit is a standalone task

## Consequences

### Positive
- Better quality for critical tasks
- Faster response for simple operations
- Cost optimization

### Negative
- More configuration to maintain
- Users may not understand model differences
- Model availability may vary

## References

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Model Comparison](https://docs.anthropic.com/en/docs/models-overview)
