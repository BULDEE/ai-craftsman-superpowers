# AI Craftsman Superpowers - Documentation

> Transform Claude Code into a Senior AI-Augmented Software Craftsman

## Quick Navigation

| Level | Document | Time to Read |
|-------|----------|--------------|
| 🟢 Beginner | [Getting Started](./getting-started/installation.md) | 5 min |
| 🟢 Beginner | [First Steps](./getting-started/first-steps.md) | 10 min |
| 🟡 Intermediate | [Core Concepts](./getting-started/concepts.md) | 15 min |
| 🟡 Intermediate | [Beginner Guide](./guides/beginner.md) | 20 min |
| 🟠 Advanced | [Intermediate Guide](./guides/intermediate.md) | 30 min |
| 🔴 Expert | [Advanced Guide (AI Engineers)](./guides/advanced.md) | 45 min |
| ⚫ Master | [Master Guide (Architects)](./guides/master.md) | 60 min |

## Playbooks

- [Legacy Rescue Playbook](./guides/legacy-rescue.md) - regain control of an untested, inherited codebase with `/craftsman:legacy`

## Reference Documentation

- [Skills Reference](./reference/skills.md) - All available skills and usage
- [Agents Reference](./reference/agents.md) - Code review agents
- [Knowledge Base](./reference/knowledge.md) - Built-in knowledge
- [MCP Servers](./reference/mcp-servers.md) - RAG and integrations

## Architecture Decisions

All major decisions are documented as ADRs (Architecture Decision Records):

- [ADR-0001: Skills over Prompts](./adr/0001-skills-over-prompts.md)
- [ADR-0002: Ollama over OpenAI for Local RAG](./adr/0002-ollama-over-openai.md)
- [ADR-0003: SQLite over pgvector](./adr/0003-sqlite-over-pgvector.md)
- [ADR-0004: 3P Agent Pattern](./adr/0004-3p-agent-pattern.md)
- [ADR-0005: Knowledge-First Architecture](./adr/0005-knowledge-first-architecture.md)

## Philosophy

- [Why This Project Exists](./philosophy/why.md)
- [The AI-Augmented Craftsman Manifesto](./philosophy/manifesto.md)

## Learning Path

```
                    ┌─────────────────────────────────────────┐
                    │         MASTER AI CRAFTSMAN              │
                    │   Designs systems, creates skills,       │
                    │   builds custom MCP servers              │
                    └─────────────────────────────────────────┘
                                      ▲
                    ┌─────────────────────────────────────────┐
                    │         ADVANCED (AI Engineer)           │
                    │   RAG pipelines, MLOps, Agent design     │
                    └─────────────────────────────────────────┘
                                      ▲
                    ┌─────────────────────────────────────────┐
                    │         INTERMEDIATE (Developer)         │
                    │   All skills, custom workflows,          │
                    │   knowledge exploitation                 │
                    └─────────────────────────────────────────┘
                                      ▲
                    ┌─────────────────────────────────────────┐
                    │         BEGINNER                         │
                    │   Basic skills: /design, /debug, /test   │
                    └─────────────────────────────────────────┘
```

## External Resources

### For Beginners
- [What is DDD?](https://martinfowler.com/bliki/DomainDrivenDesign.html) - Martin Fowler
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) - Uncle Bob
- [SOLID Principles](https://www.digitalocean.com/community/conceptual-articles/s-o-l-i-d-the-first-five-principles-of-object-oriented-design) - DigitalOcean

### For AI Engineers
- [RAG Fundamentals](https://www.pinecone.io/learn/retrieval-augmented-generation/) - Pinecone
- [MLOps Principles](https://ml-ops.org/) - MLOps Community
- [Vector Databases Explained](https://www.pinecone.io/learn/vector-database/) - Pinecone

### For Architects
- [Event-Driven Architecture](https://martinfowler.com/articles/201701-event-driven.html) - Martin Fowler
- [Microservices Patterns](https://microservices.io/patterns/) - Chris Richardson
- [CQRS](https://martinfowler.com/bliki/CQRS.html) - Martin Fowler
