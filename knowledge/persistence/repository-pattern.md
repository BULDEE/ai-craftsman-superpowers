# Repository Pattern - The Persistence Boundary

The Repository is the only door between the domain and storage. Domain code speaks in aggregates; storage speaks in rows, documents, or vectors. The Repository translates, in both directions, and nothing else crosses.

## The contract

- **Interface in Domain, implementation in Infrastructure.** `UserRepositoryInterface` lives next to the aggregate it serves; `DoctrineUserRepository` (or `PrismaUserRepository`) lives in Infrastructure. Enforced by LAYER001/LAYER004.
- **One repository per aggregate root.** Not per table, not per entity. If `Order` owns `OrderLine`, there is no `OrderLineRepository`: lines are reached through their root.
- **Collection semantics.** `save(Order $order)`, `ofId(OrderId $id)`, `matching(Specification $spec)`. No `updateStatusColumn()` methods: the repository persists state the aggregate already changed.
- **Return aggregates, never rows.** Hydration happens inside the implementation. A repository that returns an array of columns is a query builder wearing a costume.

## Hydration rules

- Rebuild aggregates through their factory or a dedicated reconstitution path, never through public setters (which must not exist: php-005).
- Partial hydration is a smell that usually means the read belongs in a read model (see query-boundaries.md), not in the repository.

## What a repository never does

| Never | Because | Where it belongs |
|-------|---------|------------------|
| Business rules | Domain logic in Infrastructure is unreachable by tests and other adapters | Aggregate methods |
| Formatting/serialization for HTTP | Couples storage to delivery | Presentation |
| Cross-aggregate transactions | Breaks aggregate consistency boundaries | Application service + domain events |
| Caching decisions | Hidden state invalidation bugs | Decorator in Infrastructure |

## Testing

- Contract test the interface once, run it against every implementation (in-memory for unit speed, real store for integration).
- The in-memory implementation is production code quality: it is what most of your test pyramid runs on.
