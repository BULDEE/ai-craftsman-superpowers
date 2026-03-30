# ADR-0008: Inline SQLite Queries Over Shell Expansion in Commands

## Status

Accepted

## Date

2026-03-30

## Context

Plugin commands (`challenge`, `debug`, `metrics`) use `!`bash ...`` shell expansion to execute `scripts/metrics-read.sh` during prompt loading. This syntax is executed by the Claude Code harness **before** the interactive conversation starts, meaning:

1. **No interactive permission prompt** — the harness applies a strict allow/deny policy. If the bash pattern is not pre-authorized in the user's `settings.json`, the command fails immediately with `Shell command permission check failed`.
2. **No plugin-level permission declaration** — the `plugin.json` manifest has no `permissions` field. A plugin cannot request bash permissions at install time.
3. **Friction for users** — every user must manually add a bash permission rule before using `/craftsman:challenge`, `/craftsman:debug`, or `/craftsman:metrics`.

This is a blocking issue for plugin adoption: commands fail on first use with no way to fix it without manual configuration.

## Decision

Replace all `!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-read.sh" <query>`` expansions with **inline instructions** that ask Claude to execute the SQLite query itself via the standard Bash tool during the conversation.

The standard Bash tool runs **inside** the interactive conversation loop, where Claude Code can prompt the user for permission normally (and offer "Always allow").

The metrics database path (`~/.claude/plugins/data/craftsman/metrics.db`) and queries are embedded directly in the command markdown.

## Consequences

### Positive

- Commands work out-of-the-box for all users — zero manual permission configuration
- Permission is requested interactively on first use (standard Claude Code UX)
- No additional infrastructure (no MCP server, no build step, no npm install)
- Removes a runtime dependency on `metrics-read.sh` from commands (simpler plugin surface)

### Negative

- SQL queries are duplicated between `metrics-read.sh` (used by hooks) and command markdown files
- Slightly more verbose command prompts
- Claude must interpret the query results itself (no pre-formatting by the script)

### Neutral

- `metrics-read.sh` is retained for use by hooks and CI scripts, which run outside the conversation and have their own permission model
- The metrics database schema and path remain unchanged

## Alternatives Considered

### Alternative 1: MCP Server for Metrics

Wrap `metrics-read.sh` in a dedicated MCP server (Node.js or Python). Plugin MCP servers are auto-started by Claude Code and don't require bash permissions.

**Rejected because:**
- Adds a runtime dependency (Node.js or Python + MCP SDK)
- Requires either `npm install && npm run build` by users, or committing compiled `dist/` to git
- Overkill for 7 read-only SQLite queries
- The existing `knowledge-rag` MCP server already demonstrates this friction (dist/ not committed, broken for fresh installs)

### Alternative 2: Commit dist/ for a Node MCP Server

Build the MCP server and commit the compiled JavaScript to the repository.

**Rejected because:**
- Compiled artifacts in git are a maintenance burden
- Increases repo size unnecessarily
- Still requires Node.js runtime on user's machine

### Alternative 3: Python MCP Server (no build)

Use Python with stdlib `sqlite3` to avoid a build step.

**Rejected because:**
- Still requires `pip install mcp` or manual protocol implementation
- Adds Python package dependency for users
- More complexity than the inline approach for the same result

### Alternative 4: Document Required Permissions

Keep `!`bash ...`` and document the permission rules users must add.

**Rejected because:**
- Friction at install time — bad UX for a plugin
- Users who skip the README get a cryptic error
- Not scalable if more scripts are added

## References

- Claude Code plugin manifest schema: no `permissions` field exists
- `scripts/metrics-read.sh`: 7 named queries over `~/.claude/plugins/data/craftsman/metrics.db`
- Affected commands: `challenge.md`, `debug.md`, `metrics.md`
