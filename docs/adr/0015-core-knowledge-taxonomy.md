# ADR-0015: Core Knowledge Taxonomy (Concepts in Core, Implementations in Packs)

## Status

Accepted

## Date

2026-07-05

## Context

The knowledge base started small and grew unevenly. Domain-Driven Design guidance lived inside the Symfony pack (`packs/symfony/knowledge/ddd-*.md`) even though DDD is language-agnostic, so React, Python, and future packs had no access to it. Meanwhile two overlapping pattern files (`patterns.md` and `design-patterns.md`) duplicated content, and there was no home for Clean Architecture, Hexagonal, TDD, testing strategy, or legacy techniques as first-class core concepts.

Per ADR-0005 (knowledge-first), the knowledge base is the foundation that commands and agents consume. If a concept is agnostic but trapped in one pack, every other pack is impoverished; if a language idiom is promoted to core, the core stops being agnostic. We needed an explicit rule for where each piece of knowledge belongs.

## Decision

Adopt a two-tier taxonomy:

1. **Core (`knowledge/`) holds concepts that are language- and framework-agnostic.** Clean Architecture, Hexagonal, DDD tactical/strategic patterns, SOLID and other principles, TDD, testing strategy, refactoring techniques and campaigns, and legacy techniques. Examples may use a concrete language for illustration, but the ideas must transfer to any stack.

2. **Packs (`packs/<lang>/knowledge/`) hold implementations of those concepts.** Framework and language specifics: Doctrine mappings, API Platform providers/processors, Messenger command buses, Symfony Voters, and the per-language SOLID canonical files.

Applying the rule for this release:

- Promote DDD from the Symfony pack to `knowledge/ddd/`, rewritten agnostic; keep Symfony specifics in `packs/symfony/knowledge/ddd-symfony-implementation.md`.
- Merge `design-patterns.md` into `patterns.md` (one entry per pattern).
- Add the missing core concepts as new files under `knowledge/` (with `legacy/` and `refactoring/` subdirectories, following the existing `anti-patterns/` convention of a directory once there are three or more related files).
- Ship a per-pack SOLID canonical (`canonical/*-solid.*`) plus a cross-language mapping table in `principles.md`.

Deprecated files become stubs pointing at the new location and are removed in v4.0.

## Consequences

### Positive
- Every pack inherits the full agnostic methodology (DDD, Clean Architecture, testing) instead of only Symfony.
- One authoritative file per topic; no more `patterns.md` vs `design-patterns.md` drift.
- A clear, mechanical rule for future contributions: "is this concept or implementation?"
- Cross-links between core files and pack canonicals give commands and agents a coherent knowledge graph.

### Negative
- A one-time migration with deprecation stubs to maintain until v4.0.
- Contributors must judge "concept vs implementation"; the rule reduces but does not eliminate ambiguity.
- Some duplication of illustrative examples between an agnostic core file and its pack implementation (accepted: the framing differs).

## References

- [ADR-0005: Knowledge-First](0005-knowledge-first.md)
- [ADR-0012: Progressive Disclosure](0012-progressive-disclosure.md)
- Roadmap: `docs/roadmap-v3.6-v4.0.md` (v3.6.0 Knowledge Foundation)
