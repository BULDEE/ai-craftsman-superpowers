# ADR-0001: Skills over Prompts

## Status

Accepted

## Date

2025-02-03

## Context

When augmenting Claude Code with domain expertise, we had two primary approaches:

1. **Mega-prompts in CLAUDE.md**: Put all instructions in a single file
2. **Modular skills**: Separate skills invoked on-demand

The challenge: How to provide consistent, high-quality guidance without overwhelming the context window or creating prompt fatigue?

## Decision

We chose **modular skills** organized by concern, invoked via `/skill-name` syntax.

Each skill:
- Has a single responsibility
- Contains complete context for its domain
- Follows a mandatory process (phases)
- Includes bias protection

```
/craftsman:design    → DDD entity design with challenge phases
/craftsman:debug     → Systematic debugging (ReAct pattern)
/craftsman:test      → Test strategy (Fowler/Martin methodology)
/craftsman:rag       → RAG pipeline design
```

## Consequences

### Positive

- **Focused context**: Only relevant skill loaded when needed
- **Maintainability**: Each skill is independently updatable
- **Discoverability**: Clear naming reveals capabilities
- **Consistency**: Same process every time
- **Composability**: Skills can reference each other

### Negative

- **Learning curve**: User must know skill names
- **Invocation overhead**: Extra step vs automatic detection
- **Fragmentation risk**: Related knowledge split across files

### Neutral

- Skills can be rigid (TDD) or flexible (patterns)
- User can override skill recommendations

## Alternatives Considered

### Alternative 1: Single CLAUDE.md with Everything

All instructions in one file with conditional sections.

**Rejected because:**
- Context window pollution (always loaded)
- Harder to maintain (monolithic)
- No clear entry points
- Overwhelms the model with irrelevant context

### Alternative 2: Automatic Skill Detection

Model automatically detects which skill to use based on user request.

**Rejected because:**
- Unreliable detection
- User loses control
- Hidden behavior is confusing
- Skill conflicts possible

### Alternative 3: Fine-tuned Model

Custom model trained on our methodology.

**Rejected because:**
- Requires training infrastructure
- Cannot iterate quickly
- Vendor lock-in
- Expensive

## References

- [Claude Code Plugins Documentation](https://docs.anthropic.com/claude-code/plugins)
- [Unix Philosophy: Do One Thing Well](https://en.wikipedia.org/wiki/Unix_philosophy)
- [Prompt Engineering Best Practices](https://www.anthropic.com/index/prompting-guide)
