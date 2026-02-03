# AI Craftsman Superpowers

> Senior craftsman methodology for AI-assisted development.

Transform Claude Code into a senior software craftsman with battle-tested methodologies: DDD, Clean Architecture, TDD, and systematic workflows.

## What's Included

### Core Pack (Always Enabled)

| Skill | Purpose |
|-------|---------|
| `/design` | DDD design with challenge phases |
| `/debug` | Systematic investigation (ReAct pattern) |
| `/spec` | Specification-first development (BDD/TDD) |
| `/plan` | Structured task planning |
| `/challenge` | Architecture review |
| `/refactor` | Systematic refactoring |
| `/test` | Pragmatic testing (Fowler/Martin) |
| `/git` | Safe git workflow |

### Symfony Pack (Optional)

- `/craft entity` - Scaffold DDD entity with VO, events, tests
- `/craft usecase` - Scaffold use case with command/handler
- Canonical patterns: Entity, Value Object, Repository, UseCase
- Agents: Symfony Reviewer, Security Pentester

### React Pack (Optional)

- `/craft component` - Scaffold React component
- `/craft hook` - Scaffold TanStack Query hook
- Canonical patterns: Branded Types, Components, Query Hooks
- Agent: React Reviewer

## Installation

```bash
claude plugins install git@github.com:woprrr/ai-craftsman-superpowers.git
```

On first run, a setup wizard will configure your profile.

## Configuration

After setup, your config is at `~/.claude/.craft-config.yml`:

```yaml
profile:
  name: "Your Name"
  disc_type: "DI"
  biases:
    - acceleration
    - scope_creep

packs:
  core: true
  symfony: true
  react: true
```

## Scaffold System

Analyze existing code and generate context agents:

```bash
/craft scaffold backend/src/Domain/Gamification/
```

This detects your entities, value objects, services, and generates a context agent for the bounded context.

## Philosophy

> "Weeks of coding can save hours of planning."

This plugin enforces:

1. **Design before code** - Understand, challenge, then implement
2. **Test-first** - If you can't write the test, you don't understand the requirement
3. **Systematic debugging** - No random fixes, find root cause first
4. **YAGNI** - Build what's needed, not what might be needed
5. **Clean Architecture** - Dependencies point inward

## Bias Protection

Configure your cognitive biases and the plugin will guard against them:

- **Acceleration** - "Let's just code it" → STOP, spec first
- **Dispersion** - Topic jumping → Finish current task
- **Scope creep** - "Let's also add..." → Is it in scope?
- **Over-optimization** - "Let's abstract..." → Measure first

## License

Commercial license. One-time purchase, lifetime access.

See [LICENSE.md](LICENSE.md) for terms.

## Support

Issues: [GitHub Issues](https://github.com/woprrr/ai-craftsman-superpowers/issues)
