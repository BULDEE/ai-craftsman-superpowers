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

## Roadmap

- [v4.0.0 Roadmap - The Self-Learning Craftsman System](./v4-roadmap.md) - decided direction, phases, and breaking changes

## Architecture Decisions

All major decisions are documented as ADRs (Architecture Decision Records):

- [ADR-0001: Skills over Prompts](./adr/0001-skills-over-prompts.md)
- [ADR-0002: Ollama over OpenAI for Local RAG](./adr/0002-ollama-over-openai.md)
- [ADR-0003: SQLite over pgvector](./adr/0003-sqlite-over-pgvector.md)
- [ADR-0004: 3P Agent Pattern](./adr/0004-3p-agent-pattern.md)
- [ADR-0005: Knowledge-First Architecture](./adr/0005-knowledge-first-architecture.md)
- [ADR-0006: Project-Specific Knowledge](./adr/0006-project-specific-knowledge.md)
- [ADR-0007: Commands over Skills](./adr/0007-commands-over-skills.md) (superseded by ADR-0017)
- [ADR-0008: Inline SQLite over Bash Expansion](./adr/0008-inline-sqlite-over-bash-expansion.md)
- [ADR-0009: Command Hooks over Agent Hooks](./adr/0009-command-hooks-over-agent-hooks.md) (superseded by ADR-0018)
- [ADR-0010: Model Tiering](./adr/0010-model-tiering.md)
- [ADR-0011: Context Fork Strategy](./adr/0011-context-fork-strategy.md)
- [ADR-0012: Progressive Disclosure](./adr/0012-progressive-disclosure.md)
- [ADR-0013: Workflow Orchestrator](./adr/0013-workflow-orchestrator.md)
- [ADR-0014: Quick Setup Mode](./adr/0014-quick-setup-mode.md)
- [ADR-0015: Core Knowledge Taxonomy](./adr/0015-core-knowledge-taxonomy.md)

### v4.0.0 decisions (2026-07)

- [ADR-0016: v4 Clean Break - Native-First on Claude Code >= 2.1.218](./adr/0016-v4-clean-break-native-first.md)
- [ADR-0017: Skills over Commands](./adr/0017-skills-over-commands.md)
- [ADR-0018: Native Prompt and Agent Hooks](./adr/0018-native-prompt-agent-hooks.md)
- [ADR-0019: Established Tooling First - No Substitution](./adr/0019-established-tooling-first.md)
- [ADR-0020: Instinct Promotion with Human Review](./adr/0020-instinct-promotion-human-review.md)
- [ADR-0021: Context Budgets and Kill Switches](./adr/0021-context-budgets-and-kill-switches.md)
- [ADR-0022: Setup by Observation](./adr/0022-setup-by-observation.md)
- [ADR-0023: Deterministic Verification Loop](./adr/0023-deterministic-verification-loop.md)

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
