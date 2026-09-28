# Knowledge Reference

Built-in knowledge that informs Claude's responses.

## Knowledge Hierarchy

```
Priority (highest to lowest):
1. Explicit user instruction
2. Project CLAUDE.md
3. Global ~/.claude/CLAUDE.md
4. Pack knowledge
5. Core knowledge
```

---

## Core Knowledge

Located in `knowledge/`

### principles.md

Universal software engineering principles:

- **SOLID**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It

### patterns.md

Design patterns reference:

- **Creational**: Factory, Builder, Singleton
- **Structural**: Adapter, Decorator, Facade
- **Behavioral**: Strategy, Observer, Command
- **DDD**: Entity, Value Object, Aggregate, Repository, Domain Event

### microservices-patterns.md

10 essential microservices patterns:

1. Service Registry
2. Circuit Breaker
3. API Gateway
4. Saga Pattern
5. Event Sourcing
6. CQRS
7. Bulkhead
8. BFF (Backend for Frontend)
9. Database per Service
10. Externalized Configuration

### event-driven.md

Event-Driven Architecture patterns (Martin Fowler):

1. Event Notification
2. Event-Carried State Transfer
3. Event Sourcing
4. CQRS

---

## Symfony Pack Knowledge

Located in `packs/symfony/knowledge/`

### canonical/

Golden examples to copy:

- `Entity.php` - Proper DDD entity structure
- `ValueObject.php` - Immutable value object
- `Repository.php` - Repository interface
- `UseCase.php` - Application use case

### anti-patterns/

What NOT to do:

- `AnemicDomain.php` - Entity without behavior
- `GodService.php` - Service with too many responsibilities
- `LeakyAbstraction.php` - Domain exposing infrastructure

---

## React Pack Knowledge

Located in `packs/react/knowledge/`

### canonical/

- `Component.tsx` - Proper component structure
- `Hook.tsx` - TanStack Query hook pattern
- `BrandedType.ts` - Domain primitive typing

### anti-patterns/

- `AnyType.tsx` - Using `any` instead of proper types
- `PropDrilling.tsx` - Excessive prop passing
- `GiantComponent.tsx` - Component doing too much

---

## AI Pack Knowledge

Located in `packs/ai-ml/knowledge/`

### rag-architecture.md

RAG (Retrieval-Augmented Generation):

- **Ingestion Pipeline**: Extract → Clean → Chunk → Embed → Store
- **Retrieval Pipeline**: Query → Embed → Search → Rerank → Top-K
- **Generation Pipeline**: Context + Query → Prompt → LLM

Key concepts:
- Chunking strategies (fixed, semantic, recursive)
- Embedding models comparison
- Distance metrics (cosine, euclidean)
- Quality metrics (precision, recall, faithfulness)

### vector-databases.md

Vector database fundamentals:

- What vectors represent
- Similarity search vs exact match
- Index types (Flat, IVF, HNSW, PQ)
- Database comparison (pgvector, Pinecone, Qdrant, Chroma)
- pgvector quick start

### mlops-principles.md

6 MLOps principles:

1. **Automation**: Manual → Pipeline → CI/CD → CT
2. **Versioning**: Code, data, model, config
3. **Experiment Tracking**: Params, metrics, artifacts
4. **Testing**: Unit, integration, model, regression
5. **Monitoring**: System, model, data drift
6. **Reproducibility**: Seeds, environment, configs

### agent-3p-pattern.md

3P Agent Architecture:

- **Perceive**: Input processing, NLU, context retrieval
- **Plan**: Goal decomposition, tool selection
- **Perform**: Execution, result capture, state update

Components:
- Intelligence Engine
- Tools registry
- Memory (working, short-term, long-term)
- Environment

---

## Using Knowledge

### In Skills

Skills reference knowledge:

```markdown
## Context

Load knowledge from:
- `knowledge/principles.md`
- `packs/ai-ml/knowledge/rag-architecture.md`
```

### In Conversation

Ask Claude to use knowledge:

```
> Explain the Circuit Breaker pattern from my knowledge base

> Apply the 3P pattern to design this agent
```

### Via the Lookup

Find the concepts that answer a rule or a tag, instead of searching an index:

```bash
bash "$(craftsman-path bin/craftsman-helper)" knowledge by-rule LAYER004
bash "$(craftsman-path bin/craftsman-helper)" knowledge by-tag persistence
```

---

## Adding Knowledge

### To the Core Bundle

1. Create a markdown file under `knowledge/` with frontmatter: `type` is the one required key, and `tags` and `rules` are what the lookups match on
2. Check that the lookup finds it:

```bash
bash "$(craftsman-path bin/craftsman-helper)" knowledge list
bash "$(craftsman-path bin/craftsman-helper)" knowledge by-rule LAYER001
```

If `craftsman-path` is not on PATH, use `<installed plugin root>/bin/craftsman-helper` directly.

### To a Pack

1. Create a markdown file in `packs/<pack>/knowledge/` (the pack's `pack.yml` declares `knowledge: ["knowledge/"]`); nothing is registered in `plugin.json`
2. Reference it from the pack's skills or agents: the lookup above reads the core `knowledge/` bundle only

### No RAG Index

There is no index to rebuild. The `knowledge-rag` server and its index-build step were removed in v4.0.0 ([ADR-0024](../adr/0024-okf-knowledge-bundle.md), [MCP servers](mcp-servers.md)): the bundle is plain markdown read by a deterministic rule-to-concept lookup.

---

## Knowledge Best Practices

1. **Keep it concise**: Reference, not textbook
2. **Include examples**: Show, don't just tell
3. **Update regularly**: Knowledge ages
4. **Cite sources**: Enable verification
5. **Organize by topic**: Easy to find and reference
