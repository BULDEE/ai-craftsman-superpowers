# v4.0.0 Roadmap - The Self-Learning Craftsman System

> Status: **delivered in 4.0.0** (2026-07-26). The decisions below are recorded as ADRs 0016-0023. The 3.9.x line remains available and frozen for Claude Code < 2.1.218.

## Direction

v3 made Claude a disciplined craftsman: rules enforced in real time, zero CI drift, metrics. v4 makes the system **self-learning and native-first**: it observes how your codebase corrects Claude, codifies approved lessons into project skills, and delegates verification to native Claude Code primitives instead of bash emulation.

**v4.0.0 is a clean break**: minimum Claude Code **2.1.218**, no backward compatibility with 3.x config or older Claude Code versions ([ADR-0016](adr/0016-v4-clean-break-native-first.md)). The 3.9.x line stays available and frozen for older installations.

## Phases

| Phase | Scope | ADRs |
|-------|-------|------|
| 1 | `commands/` deleted; all 21 workflows become skills with `context: fork`, agent binding, dynamic context injection, `allowed-tools` | [0017](adr/0017-skills-over-commands.md) |
| 2 | Bash agent-hook wrappers replaced by native `agent`/`prompt` hooks (Haiku-tiered), `if` gating, `updatedInput` auto-fix, `PostToolBatch` | [0018](adr/0018-native-prompt-agent-hooks.md) |
| 3 | Semantic Level 1.5 via `.lsp.json`, activating only on already-installed language servers | [0019](adr/0019-established-tooling-first.md) |
| 4 | Correction learning closes the loop: candidate instincts, human review in `/craftsman:metrics`, generated learned skills; context budgets and per-hook kill switches | [0020](adr/0020-instinct-promotion-human-review.md), [0021](adr/0021-context-budgets-and-kill-switches.md) |
| 5 | Setup by observation: generated project-conventions skill and cached codemap injected into reviewers | [0022](adr/0022-setup-by-observation.md) |
| 6 | Deterministic verification: `asyncRewake` test failures, `TaskCompleted` evidence gate, optional `monitors/` watchers; `bin/`, `${CLAUDE_PLUGIN_DATA}`, config schema, community marketplace submission | [0023](adr/0023-deterministic-verification-loop.md) |

## What stays

- The rules engine, 3-level inheritance, and CI adapters: deterministic checks remain bash, tested, and identical between hooks and CI (zero drift).
- SQLite metrics as the system of record.
- The pack system (symfony, react, python, bash, ai-ml) and its validator interface.
- The `/craftsman:*` namespace: user-facing invocations do not change.

## What disappears

- `commands/*.md` flat files (become `skills/<name>/SKILL.md`).
- `output-styles/` (replaced by plugin `settings.json` agent activation).
- `agent-ddd-verifier.sh`, `agent-sentry-context.sh`, `agent-final-review.sh`, `subagent-quality-gate.sh` bash wrappers (become native hook types).
- Support for Claude Code < 2.1.218.

## Design principles carried through v4

1. **Determinism first, semantics on top**: what a regex or schema can decide never goes through a model; models add the judgment regex cannot make ([ADR-0018](adr/0018-native-prompt-agent-hooks.md)).
2. **The plugin orchestrates, never substitutes**: your stack's established tools (PHPStan, ESLint, language servers, test runners) stay authoritative; the plugin detects, uses, and degrades gracefully ([ADR-0019](adr/0019-established-tooling-first.md)).
3. **Nothing learns without approval**: automatic detection, human-gated codification ([ADR-0020](adr/0020-instinct-promotion-human-review.md)).
4. **Context is a budget, not a landfill**: every injection is capped and every hook individually disableable ([ADR-0021](adr/0021-context-budgets-and-kill-switches.md)).

## Migration

See [MIGRATION.md](../MIGRATION.md) for the 3.x to 4.0.0 breaking-change list and upgrade steps.
