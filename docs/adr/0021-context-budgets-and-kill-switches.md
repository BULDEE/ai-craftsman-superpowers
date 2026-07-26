# ADR-0021: Context Budgets and Per-Hook Kill Switches

## Status

Accepted

## Date

2026-07-26

## Context

The plugin injects context at several points: routing table and correction trends at SessionStart, verification requests after Write/Edit, learned skills (ADR-0020). None of these injections has a size cap, and hooks can only be disabled wholesale (`agent_hooks` option) or by editing `hooks.json`.

Uncapped injection has a real cost: session-start text competes with the user's own context, and a plugin that consumes context indiscriminately trains users to disable it. ECC treats injection budgets as first-class configuration (`ECC_SESSION_START_MAX_CHARS=4000`, `ECC_MAX_INJECTED_INSTINCTS=6`, `ECC_DISABLED_HOOKS=...`); the discipline is right even where the implementation differs.

## Decision

`.craft-config.yml` v4 gains a `context_budget` block and a per-hook disable list, enforced by `hooks/lib/config.sh`:

```yaml
v: 4
context_budget:
  session_start_max_chars: 4000   # routing table + trends + pending-candidate summary, hard cap
  max_learned_skills: 6           # ADR-0020 skills loadable per session
hooks:
  disabled: []                    # e.g. [bias-detector, agent-sentry-context]
```

Enforcement rules:

- Session-start injection truncates at the cap, dropping lowest-priority sections first (trends before routing table).
- Every plugin hook checks the disabled list before doing any work and exits 0 silently when listed.
- Defaults are the values above; `0` disables an injection entirely.
- The config file is validated against a JSON schema (`schemas/craft-config.schema.json`) by CI and by `/craftsman:healthcheck`, which also reports current budget consumption.

## Consequences

### Positive

- The plugin's context footprint is bounded, predictable, and user-tunable.
- Users disable one noisy hook instead of the whole plugin.
- Schema validation catches config typos at healthcheck time instead of as silent misbehavior.

### Negative

- Truncation logic adds a prioritization decision to every injection point.
- One more config surface to document.

### Neutral

- Existing `strictness` and `packs` options are unchanged; budgets compose with them.

## Alternatives Considered

### Alternative 1: Environment variables (ECC model)

Rejected: the plugin's configuration already lives in `.craft-config.yml` with 3-level inheritance; adding an env-var layer would create two sources of truth.

### Alternative 2: No caps, rely on Claude Code compaction

Rejected: compaction manages the conversation as a whole; it cannot express "this plugin may use at most N chars of my session start". Budget ownership belongs to the injector.

## References

- ADR-0020 (learned skills are the largest new injection surface)
- ECC configuration surface (reviewed 2026-07)
