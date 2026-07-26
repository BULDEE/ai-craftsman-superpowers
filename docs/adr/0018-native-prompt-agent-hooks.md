# ADR-0018: Native Prompt and Agent Hooks (Supersedes ADR-0009)

## Status

Accepted - Supersedes [ADR-0009](0009-command-hooks-over-agent-hooks.md)

## Date

2026-07-26

## Context

ADR-0009 (2026-03) replaced `"type": "agent"` hooks with bash command wrappers because `hooks.json` had no conditional execution: agent hooks launched before any gate could run, and users with `agent_hooks: false` saw hook errors on every Write/Edit.

The wrapper approach fixed the errors but carried documented negatives: verification runs in the main conversation (context and token cost on the main model), checks are sequential, and model tiering is lost.

Claude Code has since removed the original blocker and added the missing pieces:

- The `if` field provides conditional execution directly in `hooks.json`.
- `prompt` hooks send the payload to a pinned model (e.g. Haiku) for a yes/no decision, with a 30s default timeout.
- `agent` hooks spawn a subagent with Read/Grep/Glob to verify conditions outside the main context.
- `async` and `asyncRewake` allow non-blocking verification that can still wake the main thread on failure (exit code 2).
- Hook failures no longer surface as raw "hook error" noise when gated correctly.

## Decision

Replace the bash wrapper hooks (`agent-ddd-verifier.sh`, `agent-sentry-context.sh`, `agent-final-review.sh`, `subagent-quality-gate.sh`) with native hook types in v4.0.0:

- **DDD semantic verification** (PostToolUse on Write|Edit for domain files): `"type": "agent"` with a verification prompt scoped to layer violations, aggregate boundaries, and controller leaks. The subagent reads the file itself; nothing is injected into the main context except a verdict.
- **Cheap classification decisions** (is this a violation, is this commit message conventional): `"type": "prompt"` pinned to `claude-haiku-4-5-20251001`.
- **Gating**: the `if` field plus plugin option checks. The bash pre-gates disappear.
- `post-write-check.sh` (regex Level 1) and the rules engine remain `command` hooks: deterministic checks stay deterministic (no model in the loop for what a regex can decide).

This restores the model tiering of ADR-0010: Haiku for verification, the main model for construction.

## Consequences

### Positive

- Verification leaves the main context entirely; token cost moves to Haiku-priced subagent calls.
- Checks run in parallel subagents instead of sequentially in the main thread.
- The `agent_hooks` cost disclaimer in `plugin.json` becomes accurate and small.
- Roughly four bash wrapper scripts and their gating logic are deleted.

### Negative

- `agent` hooks are marked experimental; behavior may shift between Claude Code releases. Mitigation: the deterministic `command` hooks remain the enforcement backbone; agent hooks are advisory semantics on top.
- Requires the Haiku model to be available on the user's plan for `prompt` hooks; degrade by skipping, never by erroring.

### Neutral

- ADR-0009's analysis was correct for its time; this reversal is driven by platform capability, not by a flaw in that decision.

## Alternatives Considered

### Alternative 1: Keep bash wrappers, add native hooks only for new checks

Rejected: perpetuates the main-context token cost that ADR-0009 itself listed as a negative, and splits verification across two mechanisms.

### Alternative 2: Move all validation, including regex, to agent hooks

Rejected: model-based checks are non-deterministic and cost tokens; a regex that decides `strict_types` presence must stay a regex. Determinism first, semantics on top.

## References

- ADR-0009 (superseded), ADR-0010 (model tiering), ADR-0016 (clean break)
- Hooks documentation (types, `if`, async): https://code.claude.com/docs/en/hooks
