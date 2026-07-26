# ADR-0016: v4.0.0 Clean Break - Native-First on Claude Code >= 2.1.218

## Status

Accepted

## Date

2026-07-26

## Context

Between v3.0.0 and v3.9.0, Claude Code shipped primitives that the plugin re-implements in bash:

- Commands merged into skills, with `context: fork`, `agent:` binding, dynamic context injection, `allowed-tools` pre-approval, and invocation control (`disable-model-invocation`, `user-invocable`).
- Native hook types `prompt`, `agent`, and `mcp_tool`, plus the `if` conditional field, `async`/`asyncRewake`, and `updatedInput`.
- Plugin-level `.lsp.json`, `monitors/`, `bin/`, `settings.json` (main-thread agent activation), and `${CLAUDE_PLUGIN_DATA}`.
- New hook events: `PostToolBatch`, `TaskCompleted`, `TeammateIdle`, `StopFailure`, `PermissionDenied`, `DirectoryAdded`.

Maintaining compatibility with older Claude Code versions forces a lowest-common-denominator architecture: bash wrappers emulating native features, duplicated gating logic, and main-context token waste. An audit against Claude Code 2.1.220 (2026-07) and a comparative review of the ECC project confirmed the bespoke layers are now strictly worse than the native equivalents.

## Decision

v4.0.0 is a clean break:

- **Minimum supported Claude Code version: 2.1.218** (first version with synchronous forked skills, `background: false`).
- **No backward compatibility** with 3.x plugin config or older Claude Code versions. `.craft-config.yml` carries a `v: 4` marker; older configs are migrated by `/craftsman:setup`, not silently supported.
- Legacy layers are removed, not deprecated: flat `commands/*.md` files, `output-styles/`, and bash wrappers that emulate agent hooks.
- Every capability that has a native primitive uses the native primitive. Bash remains only where no primitive exists (rules engine, metrics, CI adapters).

## Consequences

### Positive

- Less code to maintain: the bash emulation layers disappear.
- Reliability: native primitives are tested and evolved by Anthropic, not by us.
- The plugin stops paying main-context tokens for work that belongs in subagents.
- A single documented target version makes support and debugging tractable.

### Negative

- Users on Claude Code < 2.1.218 must upgrade before installing v4 (3.9.x remains available and frozen).
- A major-version migration guide is required (see MIGRATION.md).

### Neutral

- Version badge and marketplace metadata must state the minimum Claude Code version.

## Alternatives Considered

### Alternative 1: Dual-mode compatibility layer

Detect the Claude Code version at session start and select legacy or native code paths. Rejected: doubles the test matrix, keeps every legacy file alive, and the detection itself is fragile across versions.

### Alternative 2: Gradual deprecation across 3.x minors

Ship native paths alongside legacy ones with warnings. Rejected: the two architectures differ structurally (commands vs skills, wrappers vs native hooks); coexistence means shipping both trees in full.

## References

- Claude Code changelog: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- Skills documentation: https://code.claude.com/docs/en/skills
- Hooks documentation: https://code.claude.com/docs/en/hooks
- ADR-0017, ADR-0018, ADR-0019, ADR-0023 (native primitives adopted by v4)
