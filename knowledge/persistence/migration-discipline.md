---
type: methodology
title: "Migration Discipline - Schema Changes Are Code"
description: "Migrations are the highest-risk code you ship: they run once, in production, with data you cannot regenerate. Treat them with more discipline than feature code, not less."
tags: [persistence, migrations, expand-contract]
rules: [DB002]
status: stable
---
# Migration Discipline - Schema Changes Are Code

Migrations are the highest-risk code you ship: they run once, in production, with data you cannot regenerate. Treat them with more discipline than feature code, not less.

## Non-negotiables

- **Every up has a down.** A migration without a rollback path is a one-way door installed during an emergency (enforced as DB002). If a change is genuinely irreversible (dropping data), the down() documents the restore procedure and the migration ships with a backup step.
- **Migrations are immutable once merged.** Fix a bad migration with a new migration, never by editing history teammates already ran.
- **Migrations are reviewed and tested like code.** Run up + down + up against a realistic dataset in CI or staging before production.

## Expand-contract (parallel change)

The only safe pattern for changing a schema under traffic. Never rename or change a column in one step:

1. **Expand**: add the new column/table alongside the old. Code writes to both, reads from old.
2. **Migrate**: backfill data; switch reads to new; keep writing both.
3. **Contract**: once verified (metrics, not hope), stop writing old; a later migration drops it.

Each step is independently deployable and reversible. The deploy and the migration are never coupled in one atomic moment.

## Zero-downtime checklist

- Additive first: new columns nullable or defaulted, so old code keeps working.
- No long locks: batch backfills, `CREATE INDEX CONCURRENTLY` (or the engine's equivalent).
- Destructive operations (DROP, NOT NULL tightening) only after a full release cycle with the new path verified.

## Legacy signal

A repository whose migrations directory tells the story of the schema is maintainable. One that mutates the schema manually ("just ran it in psql") is a legacy rescue waiting to happen: bring it under `/craftsman:legacy` before touching the data model.
