---
okf_version: "0.2"
---

# Craftsman Knowledge Bundle

Curated engineering doctrine consumed by the craftsman plugin's skills, agents, and quality gate. [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle: every concept is a Markdown file whose frontmatter declares its `type`, `tags`, and the enforcement `rules` it explains. Deterministic lookup: `hooks/lib/knowledge_lookup.py`.

- Architecture: clean-architecture, hexagonal, event-driven, microservices-patterns
- Method: tdd, testing-strategy, verifying-the-instrument, clean-code, principles, refactoring-techniques
- DDD: ddd/ddd-domain-design, ddd/ddd-cqrs-architecture
- Persistence: persistence/repository-pattern, persistence/migration-discipline, persistence/data-modeling-decisions, persistence/query-boundaries
- Security: security/secure-by-design, security/owasp-layer-mapping
- Legacy: legacy/taking-over-legacy, legacy/characterization-testing, legacy/legacy-techniques, legacy/strangler-fig, legacy/communicating-tech-debt
- Refactoring: refactoring/code-smells, refactoring/mikado-method, refactoring/refactoring-campaigns, refactoring/refactoring-katas
- Anti-patterns: anti-patterns/anemic-domain, anti-patterns/god-object, anti-patterns/primitive-obsession, anti-patterns/setter-abuse, anti-patterns/singleton-abuse, anti-patterns/sync-in-async
- Reference: patterns, design-patterns, stack-specifics, tooling-integration, agent-3p-pattern
