---
name: healthcheck
description: "Run a comprehensive diagnostic of your Craftsman plugin installation and runtime. Use when troubleshooting plugin issues, after setup, or when session-start reports warnings."
effort: quick
---

# /craftsman:healthcheck — Plugin Diagnostic

Run a full health check of your AI Craftsman Superpowers installation.

## Process

1. Run the healthcheck script using the Bash tool:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh" && \
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/pack-loader.sh" && \
pack_loader_init 2>/dev/null && \
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/healthcheck.sh" && \
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
   - Ollama down → `ollama serve`
   - Knowledge DB empty → `/craftsman:knowledge sync`
   - Channels open → `/craftsman:healthcheck` will show cooldown status
