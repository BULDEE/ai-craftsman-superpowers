# Core Concepts

Understanding these concepts will help you get the most out of AI Craftsman Superpowers.

## The Craftsman Philosophy

> "Weeks of coding can save hours of planning."

A craftsman doesn't just write code—they:

1. **Understand** the problem before solving it
2. **Challenge** assumptions and explore alternatives
3. **Design** before implementing
4. **Test** to prove correctness
5. **Refactor** to maintain quality

This plugin encodes these practices into repeatable skills.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AI CRAFTSMAN SUPERPOWERS                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │  CORE PACK  │  │SYMFONY PACK │  │ REACT PACK  │  │  AI PACK   │ │
│  │             │  │             │  │             │  │            │ │
│  │ /craftsman: │  │ /scaffold:  │  │ /scaffold:  │  │/craftsman: │ │
│  │   design    │  │   entity    │  │   component │  │   rag      │ │
│  │   debug     │  │   usecase   │  │   hook      │  │   mlops    │ │
│  │   test      │  │             │  │             │  │   agent-   │ │
│  │   plan      │  │             │  │             │  │   design   │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘ │
│         │                │                │                │        │
│         ↓                ↓                ↓                ↓        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    KNOWLEDGE LAYER                           │   │
│  │  principles.md │ patterns.md │ canonical/* │ anti-patterns/* │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     MCP SERVERS                              │   │
│  │              knowledge-rag (RAG search)                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Concepts

### 1. Skills

**What**: Modular expertise invoked by name (`/design`, `/debug`, etc.)

**Why**: Focused context, consistent process, maintainable code.

**How**: Each skill has:
- A trigger phrase (e.g., `/design`)
- Mandatory phases to follow
- Domain-specific knowledge
- Bias protection

```
/craftsman:design = DDD expertise
/craftsman:debug  = Systematic investigation (ReAct)
/craftsman:test   = Test strategy (Fowler methodology)
```

### 2. Packs

**What**: Collections of skills, agents, and knowledge for a specific domain.

**Available Packs**:

| Pack | Domain | Skills |
|------|--------|--------|
| Core | Universal | design, debug, test, refactor, plan, scaffold |
| Symfony | PHP/DDD | scaffold entity, scaffold usecase |
| React | Frontend | scaffold component, scaffold hook |
| AI | ML/RAG | rag, mlops, agent-design |

### 3. Knowledge

**What**: Curated reference material that informs Claude's responses.

**Types**:
- **Principles**: SOLID, DRY, YAGNI, KISS
- **Patterns**: Design patterns, DDD patterns
- **Canonical**: Golden examples to follow
- **Anti-patterns**: What NOT to do

### 4. Agents (11 total)

**What**: Specialized AI agents — 4 reviewers (read-only analysis) and 7 craftsmen (implementation).

**Reviewers** (code analysis):
- `symfony-reviewer` — Symfony/DDD best practices
- `security-pentester` — Security vulnerability detection
- `react-reviewer` — React patterns and hooks
- `ai-engineer` — RAG/MLOps/Agent best practices

**Craftsmen** (implementation, v1.5.0):
- `team-lead` — Orchestrator (Sonnet, never codes)
- `backend-craftsman` — PHP/Symfony expert
- `frontend-craftsman` — React/TS expert (65 Vercel best practices)
- `architect` — DDD validation (read-only)
- `ai-engineer` — RAG, LLM, MCP design
- `api-craftsman` — API Platform 4, REST/HATEOAS, OpenAPI
- `ui-ux-director` — UX, WCAG 2.1 AA
- `doc-writer` — Technical documentation (Haiku, cost-optimized)

### 5. Hooks (8 events)

**What**: Automated validation running at key lifecycle events.

**Command hooks** (shell scripts): validate code rules, detect biases, record metrics.
**Agent hooks** (Haiku model): semantic DDD analysis, Sentry error context, project structure analysis, final architecture review.

See [Hooks Reference](../reference/hooks.md) for details.

### 6. MCP Servers & Channels

**What**: External services that extend Claude's capabilities.

**knowledge-rag** (optional) — Semantic search over indexed PDFs:

```
User: "What are the MLOps principles?"
       ↓
Claude calls: search_knowledge("MLOps principles")
       ↓
MCP Server: Returns relevant chunks from indexed PDFs
       ↓
Claude: Answers with grounded, accurate information
```

**Sentry** (channel, v1.4.0) — Error context injection from Sentry when editing files with known issues. Configured via `plugin.json` channels.

## The Bias Protection System

Based on DISC profiling, the plugin guards against cognitive biases:

| Bias | Symptom | Protection |
|------|---------|------------|
| Acceleration | "Let's just code it" | STOP → Spec first |
| Dispersion | Jumping between topics | STOP → Finish current task |
| Scope Creep | "Let's also add..." | STOP → Is it in scope? |
| Over-optimization | "Let's abstract..." | STOP → Measure first |

Configure your biases in `.craft-config.yml`:

```yaml
profile:
  biases:
    - acceleration
    - scope_creep
```

## The Knowledge Hierarchy

When rules conflict, this order applies:

```
1. Explicit user instruction     (highest priority)
2. Project CLAUDE.md
3. Global ~/.claude/CLAUDE.md
4. Pack knowledge
5. Core knowledge
6. RAG search results            (lowest priority)
```

## External Resources

### Understanding DDD
- [Domain-Driven Design Quickly](https://www.infoq.com/minibooks/domain-driven-design-quickly/) - Free ebook
- [DDD Reference](https://www.domainlanguage.com/ddd/reference/) - Eric Evans

### Understanding Clean Architecture
- [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) - Uncle Bob
- [Clean Architecture Book](https://www.oreilly.com/library/view/clean-architecture-a/9780134494272/)

### Understanding Testing
- [Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html) - Martin Fowler
- [TDD By Example](https://www.oreilly.com/library/view/test-driven-development/0321146530/) - Kent Beck

## Next Steps

Ready to go deeper?

- [Beginner Guide](../guides/beginner.md) - Full walkthroughs
- [Skills Reference](../reference/skills.md) - All skills documented
