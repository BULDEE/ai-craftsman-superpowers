# ADR-0007: Commands Over Skills for User-Invocable Workflows

## Status

**Accepted** - 2025-02-04

## Context

The plugin initially placed all methodological workflows (design, debug, test, etc.) in the `skills/craftsman/*/SKILL.md` directory structure, following the pattern suggested for auto-activated skills.

However, during testing, we discovered that:

1. **Skills in `skills/` directory** are loaded as **auto-activated skills** - they can trigger automatically based on context keywords but are NOT visible in the user's skill list
2. **Commands in `commands/` directory** are loaded as **user-invocable commands** - they appear in `/help` and can be explicitly called with `/craftsman:skillname`

Our methodological workflows (design, debug, plan, test, etc.) are **deliberate methodologies** that users want to:
- Explicitly invoke when starting a structured workflow
- See listed in available commands
- Control when they activate (not auto-trigger unexpectedly)

## Decision

**Migrate all user-invocable skills from `skills/craftsman/*/SKILL.md` to `commands/*.md`.**

### What moves to `commands/`:
- design, debug, test, verify, challenge, plan, refactor, spec, git, parallel
- entity, usecase, component, hook
- rag, mlops, agent-design, source-verify
- agent-create, scaffold (already there)

### What stays in `skills/`:
- `session-init` - Internal non-invocable skill with `disable-model-invocation: true`

### Format change:

**Before (SKILL.md format):**
```yaml
---
name: design
description: |
  Multi-line description with auto-activation keywords...
model: sonnet
allowed-tools:
  - Read
  - Glob
---
```

**After (command format):**
```yaml
---
name: design
description: Single line description for the skill list.
---
```

The `model` and `allowed-tools` fields are removed from frontmatter as they are SKILL.md-specific features for auto-activation. The content of the command remains the same as the skill body.

## Consequences

### Positive
- Users can see all available craftsman methodologies in `/help`
- Explicit invocation gives users control over when to enter structured workflows
- Matches user expectations for a "senior craftsman methodology" plugin
- Aligns with how official plugins (Notion) structure their commands

### Negative
- Auto-activation feature is lost (users must explicitly invoke)
- `model` tiering is no longer enforced at skill level (relies on user context)

### Neutral
- Documentation must be updated to reference commands instead of skills
- README already showed `/craftsman:design` syntax, so user-facing docs are consistent

## Trade-off Justification

For a **methodology plugin**, explicit user control is more valuable than auto-activation:

| Approach | When Better |
|----------|-------------|
| Auto-activation (skills/) | Passive utilities, background checks, formatters |
| User-invocation (commands/) | Deliberate workflows, methodologies, scaffolders |

The craftsman plugin provides **deliberate methodologies** - users should consciously decide "I'm going to design this entity using DDD phases" rather than having it trigger automatically.

## References

- Claude Code Plugin Documentation: https://code.claude.com/docs/en/plugins
- Notion Plugin structure (commands/ pattern): Reference implementation
- Issue: Skills not appearing in user skill list

## Author

Alexandre Mallet (@woprrr) - 2025-02-04
