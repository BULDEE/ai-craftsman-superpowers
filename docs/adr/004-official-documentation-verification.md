# ADR-004: Official Documentation Verification Before Assessment

## Status

Accepted

## Date

2025-02-04

## Context

AI capabilities evolve rapidly. Claude Code releases new features frequently (skills, hooks, plugins, MCP servers, LSP integration, etc.). Making assessments about what is "supported" or "not supported" without checking official documentation leads to:

1. **False negatives**: Claiming features don't exist when they do
2. **Outdated advice**: Recommending workarounds for problems that have been solved
3. **Trust erosion**: Users losing confidence in assessments
4. **Wasted effort**: Building solutions for non-existent limitations

**Real-world example**: In February 2025, an assessment incorrectly stated that `model:`, `allowed-tools:`, and `context: fork` frontmatter fields were "not supported" in Claude Code skills, when official documentation clearly showed they were supported since v1.0.33.

## Decision

We implement a **mandatory verification protocol** for any assessment involving AI tool capabilities:

### 1. Official Sources First

Before claiming any feature exists or doesn't exist, MUST consult:

| Tool | Official Documentation |
|------|------------------------|
| Claude Code | https://code.claude.com/docs/en/ |
| Claude API | https://docs.anthropic.com/en/docs/ |
| Claude Desktop | https://support.claude.com/ |
| Anthropic News | https://www.anthropic.com/news |

### 2. Verification Checklist

```markdown
## Capability Assessment Checklist

- [ ] Checked official documentation (not just blog posts or tutorials)
- [ ] Verified documentation date (features may be new)
- [ ] Tested in actual environment if possible
- [ ] Distinguished between "not documented" vs "confirmed not supported"
- [ ] Noted version requirements if applicable
```

### 3. Uncertainty Protocol

When official documentation is unclear:

1. **State uncertainty explicitly**: "Documentation doesn't clearly specify..."
2. **Suggest verification**: "Consider testing this directly..."
3. **Avoid definitive negative claims**: Don't say "doesn't work" without evidence

### 4. Source Citation

All capability assessments MUST include source links:

```markdown
## Sources
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
```

## Consequences

### Positive

- Accurate assessments based on authoritative sources
- Reduced false negatives about capabilities
- Better user trust through verifiable claims
- Keeps pace with rapid AI tool evolution

### Negative

- Slower initial assessment (requires documentation lookup)
- More tool calls for web fetching documentation
- Documentation may lag behind actual capabilities

### Neutral

- Shifts responsibility from memory to verification
- Creates paper trail of sources consulted

## Alternatives Considered

### Alternative 1: Trust Model Knowledge

Rely on training data knowledge about tools.

**Rejected**: Training data has cutoff dates and may be outdated. AI tools evolve faster than training cycles.

### Alternative 2: Conservative "Unknown" Defaults

Default to "unknown" for all capability questions.

**Rejected**: Too unhelpful. Users need actionable guidance, not constant uncertainty.

### Alternative 3: Community Sources Only

Use StackOverflow, blog posts, GitHub issues as primary sources.

**Rejected**: Community sources may be outdated or incorrect. Official docs are authoritative.

## References

- [Claude Code Documentation](https://code.claude.com/docs/en/)
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Anthropic Documentation](https://docs.anthropic.com/)
- [Claude Release Notes](https://support.claude.com/en/articles/12138966-release-notes)
