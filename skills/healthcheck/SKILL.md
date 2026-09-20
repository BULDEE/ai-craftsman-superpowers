---
model: haiku
description: "Run a comprehensive diagnostic of your Craftsman plugin installation and runtime. Use when troubleshooting plugin issues, after setup, or when session-start reports warnings."
effort: low
disable-model-invocation: true
---

# /craftsman:healthcheck - Plugin Diagnostic


> The commands below call `craftsman-path`, which prints an absolute path
> inside this installation. The plugin's `bin/` is on PATH in the Claude Code
> Bash tool; on a host where it is not, call it by its full path
> (`<plugin root>/bin/craftsman-path`). Do not use `${CLAUDE_PLUGIN_ROOT}` in a
> skill body: a skill is text handed to a model, the host expands nothing there,
> and Claude Code does not export that variable to the Bash tool.

## Outcome Contract

- **Outcome**: a diagnostic of the plugin installation and runtime, with each failing check tied to a fix.
- **Done when**: every check reports ok, warn, or error; each non-ok check names the action that resolves it.
- **Evidence**: the healthcheck output itself, with counts.

Run a full health check of your AI Craftsman Superpowers installation.

## Process

1. Run the healthcheck script using the Bash tool:

```bash
source "$(craftsman-path hooks/lib/config.sh)" && \
source "$(craftsman-path hooks/lib/pack-loader.sh)" && \
pack_loader_init 2>/dev/null && \
source "$(craftsman-path hooks/lib/healthcheck.sh)" && \
hc_json
```

2. Parse the JSON output and present each check with its status:
   - `ok` → display with checkmark
   - `warn` → display with warning and actionable message
   - `error` → display with error and fix instructions

3. Format as a clear diagnostic report:

```
╭─ Craftsman Healthcheck ─────────────────────╮
│                                              │
│  [check name]     [status icon] [message]   │
│  ...                                         │
│                                              │
│  Status: ALL GREEN / N issues found          │
╰──────────────────────────────────────────────╯
```

4. If any checks fail, provide specific fix instructions:
   - missing deps → `brew install <dep>` (macOS) or `apt-get install <dep>` (Linux)
   - missing config → `Run /craftsman:setup`
   - Knowledge DB empty → `/craftsman:knowledge sync`
   - Channels open → `/craftsman:healthcheck` will show cooldown status
