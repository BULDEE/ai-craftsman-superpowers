---
type: methodology
title: "Query Boundaries - Reads Are Not Writes"
description: "The write model protects invariants; reads just need shaped data, fast. Forcing reads through aggregates produces N+1 storms and bloated repositories; letting writes bypass aggrega"
tags: [persistence, cqrs, n-plus-one, read-models]
rules: [DB001, DB003]
status: stable
---
# Query Boundaries - Reads Are Not Writes

The write model protects invariants; reads just need shaped data, fast. Forcing reads through aggregates produces N+1 storms and bloated repositories; letting writes bypass aggregates corrupts state. Keep the two paths distinct.

## The split (CQRS-lite, no bus required)

- **Writes**: Application service loads ONE aggregate via its repository, calls behavior, saves. Command-Query Separation (qual-004) at the architecture scale.
- **Reads**: dedicated read models/query services return DTOs shaped for the consumer. They may run SQL joins, denormalized views, or search indexes directly in Infrastructure: no aggregate hydration, no business rules.

A read model is allowed to be "ugly efficient" precisely because it can never mutate anything.

## N+1 - the default bug of ORM code

A query inside a loop (DB003) multiplies one intent into N round trips:

```
foreach ($orders as $order) {
    $customer = $customerRepository->ofId($order->customerId());  // N calls
}
```

Fixes, in order of preference:

1. Shape the read as a read model: one join, one query, one DTO list.
2. Batch: collect ids, one `WHERE id IN (...)` call.
3. Eager-load the association when the ORM owns the mapping.

Detection: DB003 flags the pattern at write time; Level 2 static analysis and slow-query logs confirm at runtime. Trust measurements over intuition (make it work, right, fast: in that order).

## Contracts with the schema

- Name your columns (DB001: no `SELECT *`). A read model that lists its columns fails loudly at migration time instead of silently shipping nulls.
- Pagination is part of the contract: unbounded reads are a production incident with a delay timer.
- Read models are rebuildable: their tables/views/indexes can be dropped and re-projected without data loss.
