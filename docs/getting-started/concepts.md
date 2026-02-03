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
│  │ /design     │  │ /craft      │  │ /craft      │  │ /craft rag │ │
│  │ /debug      │  │   entity    │  │   component │  │ /craft     │ │
│  │ /test       │  │ /craft      │  │ /craft hook │  │   mlops    │ │
│  │ /refactor   │  │   usecase   │  │             │  │ /craft     │ │
│  │ /plan       │  │             │  │             │  │   agent    │ │
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
/design = DDD expertise
/debug  = Systematic investigation (ReAct)
/test   = Test strategy (Fowler methodology)
```

### 2. Packs

**What**: Collections of skills, agents, and knowledge for a specific domain.

**Available Packs**:

| Pack | Domain | Skills |
|------|--------|--------|
| Core | Universal | design, debug, test, refactor, plan |
| Symfony | PHP/DDD | entity, usecase |
| React | Frontend | component, hook |
| AI | ML/RAG | rag, mlops, agent |

### 3. Knowledge

**What**: Curated reference material that informs Claude's responses.

**Types**:
- **Principles**: SOLID, DRY, YAGNI, KISS
- **Patterns**: Design patterns, DDD patterns
- **Canonical**: Golden examples to follow
- **Anti-patterns**: What NOT to do

### 4. Agents

**What**: Specialized reviewers that audit code against standards.

**Available Agents**:
- `architecture-reviewer` - Clean Architecture compliance
- `symfony-reviewer` - Symfony/DDD best practices
- `react-reviewer` - React patterns and hooks
- `ai-reviewer` - RAG/MLOps/Agent best practices

### 5. MCP Servers

**What**: External services that extend Claude's capabilities.

**Current**: `knowledge-rag` - Semantic search over indexed PDFs

```
User: "What are the MLOps principles?"
       ↓
Claude calls: search_knowledge("MLOps principles")
       ↓
MCP Server: Returns relevant chunks from indexed PDFs
       ↓
Claude: Answers with grounded, accurate information
```

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
