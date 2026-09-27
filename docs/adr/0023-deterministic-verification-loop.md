# ADR-0023: Deterministic Verification Loop

## Status

Accepted (amended 2026-09-28: push warning, single monitor and evidence source, see Amendment)

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

## Amendment (2026-09-28): what was delivered

The decision above is kept as it was accepted. Three of its four points did
not ship as written, and a reader following it would believe in protections
this plugin does not have (review of main eb54d13, CR-178 M17). What the
consumers actually do:

1. **Test failures wake the model: delivered.** `post-bash-test-verify.sh` is
   wired `async` with `asyncRewake` in `hooks/hooks.json` (PostToolUse and
   PostToolUseFailure). A passing run grants the session's `verified` flag. A
   failing one appends to `test-failures.log` and revokes the flag, and exits 2
   to wake the session only on a regression (the suite was green earlier in
   the session) whose command is the test runner alone.
2. **Task completion requires evidence: delivered, with different evidence.**
   `task-completed-verify.sh` reads the `verified` flag of the session's
   `session-state-<id>.json` (written by `craftsman-helper set-verified` from
   `/craftsman:verify`, or by a passing test run) and counts the lines of the
   session's `session-writes` file. No writes, or a task whose subject starts
   with docs, documentation, readme, changelog or adr, needs no evidence.
   Without it: exit 2 under `strict`, a `systemMessage` warning under
   `moderate`, nothing under `relaxed`. The exemption is that subject pattern,
   not a path rule of the rules engine, and there is no `verifications` table:
   the SQLite schema in `hooks/lib/metrics-db.sh` has none.
3. **Continuous feedback via monitors: not delivered as watchers.**
   `monitors/monitors.json` declares one monitor, `craftsman-test-failures`,
   which tails `test-failures.log`. It starts no analyser: there is no
   `phpstan --watch`, no `vitest --watch`, and no pack-defined watcher.
   Claude Code runs plugin monitors in interactive sessions only.
4. **Push gate: not a gate on Claude Code, Codex or Grok.**
   `pre-push-verify.sh` (PreToolUse, `Bash(git push*)`) prints a warning when
   the session has no `verified` flag and always exits 0: the push is allowed,
   and no file is read. A file written by a shell command is judged by
   `ci/craftsman-ci.sh`, not by this hook. On Hermes the terminal gate
   (`adapters/hermes/pre-tool-call.sh`, `terminal_gate.py`) does refuse a
   `git push` until the last conclusion passed on the tree being published.

Making the push hook block, or shipping analyser watchers, would each be a new
decision with its own ADR; this amendment only aligns the record with the code.

## References

- ADR-0016 (native primitives), ADR-0019 (monitors gated on installed tooling)
- Hooks documentation (`asyncRewake`, `TaskCompleted`): https://code.claude.com/docs/en/hooks
- Monitors: https://code.claude.com/docs/en/plugins-reference#monitors
