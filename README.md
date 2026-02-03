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

### AI Pack (Optional)

| Skill | Purpose |
|-------|---------|
| `/craft rag` | Design RAG pipelines (Ingestion, Retrieval, Generation) |
| `/craft mlops` | Audit ML projects for production readiness |
| `/craft agent` | Design AI agents using 3P pattern (Perceive/Plan/Perform) |

**Knowledge base:**
- RAG Architecture (3 pipelines, chunking, embeddings)
- Vector Databases (pgvector, Pinecone, comparison)
- MLOps Principles (6 principles, checklist)
- Agent 3P Pattern (cognitive architecture)

**Agent:** AI/ML Reviewer - Reviews AI code for production best practices

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

### SOLID Principles

| Principle | Application |
|-----------|-------------|
| **S**ingle Responsibility | One reason to change per class |
| **O**pen/Closed | Extend behavior without modifying existing code |
| **L**iskov Substitution | Subtypes must be substitutable for their base types |
| **I**nterface Segregation | Many specific interfaces > one general interface |
| **D**ependency Inversion | Depend on abstractions, not concretions |

### Pragmatism over Dogmatism

Craftsman ≠ Purist. We optimize for **working software** and **developer experience**, not academic purity.

| Dogmatic | Pragmatic (our choice) | Why |
|----------|------------------------|-----|
| `final` on all entities | No `final` on Doctrine entities | Breaks proxy/lazy loading |
| Pure PHP config only | Attributes/Annotations | 10x better DX, colocation with code |
| Always abstract | Concrete first, abstract when needed | YAGNI - abstraction has a cost |
| 100% test coverage | Critical paths covered | Diminishing returns past 80% |
| Pure DDD everywhere | DDD for complex domains only | CRUD doesn't need aggregates |

**The rule:** If a "best practice" adds complexity without proportional value, skip it.

### Core Principles

1. **Design before code** - Understand, challenge, then implement
2. **Test-first** - If you can't write the test, you don't understand the requirement
3. **Systematic debugging** - No random fixes, find root cause first
4. **YAGNI** - Build what's needed, not what might be needed
5. **Clean Architecture** - Dependencies point inward
6. **Make it work, make it right, make it fast** - In that order

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
