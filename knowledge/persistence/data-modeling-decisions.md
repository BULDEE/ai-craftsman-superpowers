# Data Modeling Decisions - Choosing Storage from the Domain

Storage choice is an architecture decision, and it is derived from the aggregate design, not from fashion. Model the domain first; the aggregates then tell you what the storage must guarantee.

## The decision drivers

| Driver | Question | Pushes toward |
|--------|----------|---------------|
| Consistency boundary | Must these facts change atomically? | The aggregate defines the transaction; any store that can commit one aggregate atomically works |
| Query shape | Do reads follow the write model, or cut across it? | Cross-cutting reads → read models/CQRS, not a different primary store |
| Relationships | Are links navigated both ways, with integrity enforced? | Relational |
| Schema volatility | Does the shape change per record or per tenant? | Document |
| Similarity search | Is "find things like this" a domain operation? | Vector index alongside (not instead of) the system of record |
| Volume/latency | Hot path counters, sessions, queues? | Key-value cache as a projection, never as truth |

## Rules of thumb

- **Relational is the default.** It is the only option that enforces integrity you did not write yourself. You leave it for a measured reason, not a hypothetical one (YAGNI applies to polyglot persistence).
- **One system of record per aggregate.** Caches, search indexes, and vector stores are projections: rebuildable from the source of truth, allowed to be stale, never written to directly by the domain.
- **Vector stores are read models.** Embeddings are derived data. The pipeline that builds them is infrastructure; losing the index must cost you a rebuild, never data.
- **Event sourcing is a commitment, not an optimization.** Choose it when the history IS the domain (accounting, audit-mandated flows), not to "keep options open". Snapshots, upcasting, and GDPR erasure come with it.

## Anti-patterns

- Picking NoSQL to "move fast" and reinventing joins and transactions in application code within a quarter.
- Sharing one database between services/bounded contexts: the schema becomes an uncontracted public API.
- Letting the ORM shape the aggregates (one entity per table, public setters for hydration): the domain must shape the mapping, not the reverse.

## Where this lands in the plugin

`/craftsman:design` ends with a persistence mapping (aggregate → storage guarantee). The validators enforce the boundary (LAYER004, DB001-DB003); this document explains what to decide before the boundary exists.
