# Context Footprint

What the plugin adds to a session's context window, where to measure it, and
which knobs reduce it. Context is the model's attention budget: every token
the plugin injects competes with the user's code for it.

## What the plugin injects

| Surface | When | Shape |
|---------|------|-------|
| SessionStart block | once per session | status line, routing table, learning trends, healthcheck summary |
| Routing table | inside the SessionStart block | one line per suggested command, plus pack routes |
| Hook stderr on violations | only when a gate fires | violation lines for the file just written |
| Async verifier wake-ups | only when Haiku finds a real issue | findings list, capped at 10 lines of 300 chars |
| Skill bodies | only when a skill is invoked | the rendered SKILL.md (ADR-0028 measured challenge at 5k to 8k tokens) |

The design intent is progressive disclosure (ADR-0012) and context budgets
(ADR-0021): the steady-state cost is the SessionStart block; everything else
is pay-per-event.

## How to measure

- `/usage` breaks the session's consumption down by skill, subagent, plugin
  and MCP server: the plugin's real share, not an estimate.
- The `/plugin` Discover tab shows a per-plugin **Context cost** estimate
  before installing.
- `hooks/lib/hook-profile.sh` gates which hooks run per profile; pair a
  reduced profile with `/usage` before and after to see what a hook family
  costs in injected context.

## Knobs

- `CRAFTSMAN_DISABLED_HOOKS`: comma-separated hook names to disable.
- `agent_hooks: false` (plugin option): removes all headless verification
  wake-ups.
- Pack selection (`packs` option): fewer packs, shorter routing table and
  registry.
- Strictness `relaxed`: gates warn instead of block, which also shortens
  violation output.

One rule stays fixed whatever the knobs say: a blocking verdict is never
traded for context savings silently. Disabling a gate is the user's explicit
decision, visible in config, never an optimization the plugin applies on its
own.
