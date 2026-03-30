# ADR-0009: Command Hooks Over Agent Hooks for PostToolUse Gates

## Status

Accepted

## Date

2026-03-30

## Context

The PostToolUse `Write|Edit` hook group contained 3 hooks:
1. `post-write-check.sh` (type `command`) — regex/static analysis validation
2. DDD architecture verifier (type `agent`, model haiku)
3. Sentry error context (type `agent`, model haiku)

The 2 agent hooks included an "AGENT HOOKS GATE" in their prompt: the agent would check `CLAUDE_PLUGIN_OPTION_agent_hooks` and return empty if `false`. However, this gate was ineffective because:

1. **Agent hooks launch before the gate executes** — if the agent fails to start (model unavailable, timeout, API error), the gate never runs and the hook errors immediately.
2. **`hooks.json` has no conditional execution** — there is no `enabled`, `condition`, or `if` field. All hooks in a matcher group always run.
3. **Users with `agent_hooks: false` still see errors** — two "PostToolUse:Edit hook error" messages on every Write/Edit, even though they explicitly disabled agent hooks.

This caused a broken experience for every user who disabled agent hooks (or had no access to the Haiku model).

## Decision

Replace the 2 `"type": "agent"` hooks with `"type": "command"` hooks that wrap the gate logic in bash scripts (`agent-ddd-verifier.sh`, `agent-sentry-context.sh`).

Each wrapper script:
1. Checks `CLAUDE_PLUGIN_OPTION_agent_hooks` — exits 0 silently if `false`
2. Checks additional prerequisites (file extension, Sentry config, circuit breaker state)
3. If all gates pass, emits a `systemMessage` JSON payload with the verification request for the main conversation Claude to handle

## Consequences

### Positive

- Zero errors when `agent_hooks=false` — the bash gate exits before any agent/API call
- Zero errors when Haiku model is unavailable — no sub-agent is spawned
- Sentry circuit breaker check runs in bash (cheap) instead of inside an agent (expensive)
- Same gating logic, deterministic execution order

### Negative

- When `agent_hooks=true`, verification runs in the main conversation context instead of a dedicated Haiku sub-agent — uses the main model's context window and tokens
- No parallel sub-agent execution — DDD and Sentry checks are sequential within the main conversation
- Loss of model tiering (Haiku for hooks, Opus/Sonnet for main) — all work uses the main model

### Neutral

- The verification prompts are simplified (no ReAct loop with Read/Grep/Glob tools) since command hooks output static context rather than spawning interactive agents
- `post-write-check.sh` (the regex/static analysis hook) is unchanged

## Alternatives Considered

### Alternative 1: Keep Agent Hooks With Better Error Handling

Wrap agent hooks in try/catch at the hooks.json level.

**Rejected because:** `hooks.json` has no error handling primitives. Agent hook failures always surface as "hook error" to the user.

### Alternative 2: Generate hooks.json Dynamically Based on Config

A setup script reads `agent_hooks` and generates `hooks.json` with or without agent entries.

**Rejected because:** adds build-step complexity, hooks.json must be regenerated on every config change, fragile for plugin updates.

### Alternative 3: Use PreToolUse Command Hook as Gate

Add a command hook before the agent hooks that blocks execution if `agent_hooks=false`.

**Rejected because:** hooks within the same matcher group run independently — one hook cannot cancel another. A blocking exit (code 2) would block the Write/Edit itself, not just the agent hooks.

## References

- ADR-0008: Inline SQLite over bash expansion (related permission issue)
- `hooks/hooks.json`: PostToolUse Write|Edit matcher group
- `hooks/agent-ddd-verifier.sh`, `hooks/agent-sentry-context.sh`: replacement command hooks
