# ADR-003: Progressive Disclosure for Skills

## Status

Accepted

## Date

2025-02-04

## Context

Skills can contain large amounts of content: instructions, templates, examples. Loading all content upfront consumes tokens and may not be needed.

Claude Code supports progressive disclosure through:
1. **Frontmatter**: Always loaded for skill selection
2. **SKILL.md body**: Loaded when skill is invoked
3. **Supporting files**: Loaded on demand via references

## Decision

### Structure for Large Skills (>300 lines)

```
skill-name/
├── SKILL.md          # Core instructions (<500 lines)
├── reference.md      # Detailed documentation
├── examples.md       # Usage examples
└── templates/        # Code templates
    ├── php.md
    └── typescript.md
```

### SKILL.md References

```markdown
## Additional Resources

For detailed patterns, see [reference.md](reference.md).
For examples, see [examples.md](examples.md).
```

### Current Implementation

Our skills range from 63-340 lines. We apply progressive disclosure for:

| Skill | Lines | Action |
|-------|-------|--------|
| git | 340 | Consider splitting |
| refactor | 304 | Consider splitting |
| agent-design | 303 | Keep (specialized) |
| Others | <300 | No action needed |

## Rationale

### Why 500 lines limit?
- Claude Code documentation recommends "Keep SKILL.md under 500 lines"
- Ensures core instructions fit in context
- Forces clear separation of concerns

### Why not split everything?
- Small skills benefit from single-file simplicity
- Overhead of loading multiple files
- Maintenance complexity

## Consequences

### Positive
- Reduced token usage
- Faster skill loading
- Cleaner skill structure

### Negative
- More files to maintain
- References must be kept in sync
- Potential for missing context

## References

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills#add-supporting-files)
