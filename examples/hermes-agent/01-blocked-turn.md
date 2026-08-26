# Example: a Hermes agent turn, blocked, routed and released

What actually happens when a Hermes agent with the craftsman plugin tries to
conclude a coding turn. Every payload and directive below is the real wire
format; `demo.sh` in this directory replays the gate half of it on your
machine.

## Turn 1: the agent concludes with a violation in place

The agent wrote `src/config.ts` with an `any` and considers itself done.
Hermes fires `pre_verify`; the plugin scans everything the turn produced
(worktree, new files, commits since the branch point, whatever tool wrote
them) and answers:

```json
{"decision": "block",
 "reason": "The craftsman gate rejects this change, so it is not finished:\nsrc/config.ts:1 TS001 - 'any' type found - use proper types or 'unknown'\nFix these and say what you ran to prove it."}
```

Hermes turns that into a synthetic user message. The agent never gets to say
"done"; it gets a file, a line, a rule and an instruction.

## Turn 2: the fix, and what got learned

The agent replaces the `any` with a real type and concludes again. The gate
finds nothing and stays silent: the turn ends. Because the first attempt was
blocked on `TS001` and the next attempt cleared it, the plugin records both
facts:

| table | row |
|-------|-----|
| violations | `TS001`, critical, `source=hermes` |
| corrections | `TS001`, `fixed`, `source=hermes`, context `hermes attempt 1` |

On the first turn of a later session, that history comes back as context:

```
[craftsman] Correction history on this machine, most-fixed rules first:
Recently fixed: TS001(3x) | Recurring violations: TS001(4x)
Avoid reintroducing these; the gate will refuse the turn.
```

## Turn 3 (variant): a structural finding routes to a method

If the finding is structural rather than local, a nesting depth, a god file,
a ratchet regression, the directive adds a route:

```
These include structural findings: load the craftsman 'refactor' skill and
apply its method instead of patching inline.
```

The agent loads `craftsman-refactor` (Mikado method, behaviour-preserving
steps, with the referenced knowledge bundled in the skill) instead of
hammering the same inline patch into the wall of `max_verify_nudges`.

## The properties this buys

- **No silent bad turn**: a gate that cannot run blocks; a timeout blocks; an
  exception blocks. Silence always means "scanned and clean".
- **No self-service rule changes**: a turn whose diff touches
  `.craft-rules.yml` or the gate's own files is refused whatever else it
  contains.
- **Advice without loops**: advisory findings surface once, on the first
  attempt, and never block, so they cannot burn the nudge budget.

Install: [docs/guides/hermes-quickstart.md](../../docs/guides/hermes-quickstart.md).
