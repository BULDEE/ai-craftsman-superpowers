---
model: haiku
description: "Run a comprehensive diagnostic of your Craftsman plugin installation and runtime. Use when troubleshooting plugin issues, after setup, or when session-start reports warnings."
effort: low
disable-model-invocation: true
---

# /craftsman:healthcheck - Plugin Diagnostic


> The diagnostic is one command, `craftsman-healthcheck`. The plugin's `bin/`
> is on PATH in the Claude Code Bash tool; on a host where it is not, call it
> by its full path (`<plugin root>/bin/craftsman-healthcheck`). Do not use
> `${CLAUDE_PLUGIN_ROOT}` in a skill body: a skill is text handed to a model,
> the host expands nothing there, and Claude Code does not export that
> variable to the Bash tool.

## Outcome Contract

- **Outcome**: a diagnostic of the plugin installation and runtime, with each failing check tied to a fix.
- **Done when**: every check reports ok, warn, or error; each non-ok check names the action that resolves it.
- **Evidence**: the healthcheck output itself, with counts.

Run a full health check of your AI Craftsman Superpowers installation.

## Process

1. Run this command with the Bash tool, exactly as written, as your FIRST
   action:

```bash
craftsman-healthcheck
```

   It prints one JSON array and nothing else. Run it verbatim: do not source
   libraries yourself, do not look for plugin files in the user's project
   (this command lives in the installation and resolves its own paths), and
   do not invent checks. If it is not found, the plugin's `bin/` is not on
   PATH: call it by full path rather than replacing it with a diagnosis of
   your own. Report a failure of this command as the finding it is.

2. Present every check the JSON contains, with the status the JSON gives it
   and the message the JSON gives it:
   - `ok` → checkmark
   - `warn` → warning sign, and the message names the action that clears it
   - `error` → error sign, and the message names the fix

   The report is a reading of that JSON and nothing else. Never raise a
   `warn` or an `error` to ok, never write "ALL GREEN" while any check is not
   ok, never add a check the JSON does not contain, and never restate a
   message as a count you inferred (a session rendered `lsp: warn, none
   installed` as "LSP ok, 4 servers active" and called the whole report ALL
   GREEN, 2026-09-20). A diagnostic that flatters the installation is worse
   than no diagnostic: the user acts on it.

3. Format as a clear diagnostic report:

```
╭─ Craftsman Healthcheck ─────────────────────╮
│                                              │
│  [check name]     [status icon] [message]   │
│  ...                                         │
│                                              │
│  Status: N ok, M warnings, K errors          │
╰──────────────────────────────────────────────╯
```

4. If any checks fail, provide specific fix instructions:
   - missing deps → `brew install <dep>` (macOS) or `apt-get install <dep>` (Linux)
   - missing config → `Run /craftsman:setup`
   - Knowledge DB empty → `/craftsman:knowledge sync`
   - Channels open → `/craftsman:healthcheck` will show cooldown status
