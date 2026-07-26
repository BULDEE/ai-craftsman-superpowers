# ADR-0023: Deterministic Verification Loop

## Status

Accepted

## Date

2026-07-26

## Context

The plugin's verification story is advisory in places where it should be deterministic:

- `post-bash-test-verify.sh` runs `async: true`; if tests fail after the tool call returns, the result can arrive too late to influence the turn, or be lost entirely.
- `/craftsman:verify` (evidence before completion) is a methodology the model is asked to follow, not a gate the harness enforces.
- Test watchers and analyzers only run when a hook fires; there is no continuous feedback between edits.

Claude Code now provides the missing enforcement primitives: `asyncRewake` (a background hook exiting 2 wakes Claude with stderr as a system reminder), the `TaskCompleted` hook event (can block a task from being marked complete), and plugin `monitors/` (background watchers whose stdout is delivered to Claude as notifications).

## Decision

v4.0.0 wires verification into the harness:

1. **Test failures wake the model**: `post-bash-test-verify.sh` becomes `"async": true, "asyncRewake": true`. A detected test failure exits 2 with the failing output on stderr; Claude is woken with the evidence instead of discovering it next turn.
2. **Task completion requires evidence**: a `TaskCompleted` hook checks for verification evidence (recorded by `/craftsman:verify` in session state) when a task is marked complete. Missing evidence blocks the completion with a reason pointing to `/craftsman:verify`. Strictness follows the existing `strictness` config (block in strict, warn in moderate, off in relaxed).
3. **Continuous feedback via monitors**: `monitors/monitors.json` declares optional watchers (`phpstan --watch`, `vitest --watch`, pack-defined equivalents) that start only when the tool is installed and the pack is active (per ADR-0019). Failures stream to Claude as notifications, replacing per-edit polling for stacks that support watch mode.
4. **Push gate unchanged**: `pre-push-verify.sh` remains the last deterministic gate before code leaves the machine.

## Consequences

### Positive

- "Tests fail silently in the background" becomes impossible: failure is a wake-up, not a log line.
- Evidence-based completion moves from convention to enforcement, aligned with strictness config.
- Watch-mode stacks get feedback between edits with zero hook latency.

### Negative

- `TaskCompleted` blocking can frustrate when verification is legitimately unnecessary (docs-only tasks); mitigated by strictness levels and path-based exemptions in the rules engine.
- Monitors consume background processes; they are opt-in per pack and skipped when tools are absent.

### Neutral

- The SQLite metrics schema gains a `verifications` record so `TaskCompleted` checks read structured evidence instead of parsing transcripts.

## Alternatives Considered

### Alternative 1: Synchronous test verification (drop async)

Rejected: blocks every Bash call on test-suite latency; the previous version moved to async for exactly that reason. `asyncRewake` keeps the non-blocking behavior and restores the lost signal.

### Alternative 2: Stop-hook-only verification

Rejected: `Stop` fires at turn end, after the model has already claimed completion; `TaskCompleted` intercepts the claim itself.

## References

- ADR-0016 (native primitives), ADR-0019 (monitors gated on installed tooling)
- Hooks documentation (`asyncRewake`, `TaskCompleted`): https://code.claude.com/docs/en/hooks
- Monitors: https://code.claude.com/docs/en/plugins-reference#monitors
