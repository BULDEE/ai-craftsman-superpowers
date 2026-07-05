# Security Policy

## Overview

The **ai-craftsman-superpowers** plugin is designed with security as a priority. This document details what the plugin does and does NOT do.

## What This Plugin Does

### Commands (25 total)

Commands are **prompt templates** that guide Claude's behavior. They:

- ✅ Read files to understand context
- ✅ Write/edit code files when instructed
- ✅ Search codebase with Glob/Grep
- ❌ Do NOT execute arbitrary code
- ❌ Do NOT access network resources
- ❌ Do NOT modify system files

### Agents (12 total)

Agents include **5 specialized reviewers** (read-only analysis) and **7 craftsman agents** (implementation):

**Reviewers** (read-only):
- ✅ Read code for analysis
- ✅ Output review findings
- ❌ Do NOT modify code automatically

**Craftsmen** (implementation):
- ✅ Read, write, and edit code when instructed
- ✅ Follow domain-specific best practices
- ✅ Operate within Claude Code's permission system

### Hooks (7 scripts, 8 events, 4 agent hooks)

Hooks execute **shell scripts** and **agent prompts** at specific lifecycle events:

| Hook | Event | What It Does | Security |
|------|-------|--------------|----------|
| `session-start.sh` | SessionStart | Initialization, config loading | READ-ONLY |
| `pre-write-check.sh` | PreToolUse | Layer validation before write | READ-ONLY |
| `post-write-check.sh` | PostToolUse | Code rule enforcement after write | READ-ONLY |
| `bias-detector.sh` | UserPromptSubmit | Cognitive bias detection | READ-ONLY |
| `file-changed.sh` | FileChanged | Tracks file modifications | READ-ONLY |
| `pre-push-verify.sh` | PreToolUse | Validates git push commands | READ-ONLY |
| `session-metrics.sh` | SessionEnd | Records session summary to SQLite | WRITE (local DB only) |
| DDD verifier agent | PostToolUse | Semantic architecture check | READ-ONLY |
| Sentry context agent | PostToolUse | Error context from Sentry MCP | READ-ONLY (via MCP) |
| Project analyzer agent | InstructionsLoaded | Architectural context map | READ-ONLY |
| Final reviewer agent | Stop | Architecture validation (strict mode) | READ-ONLY |

#### Hook Security Guarantees

All hooks in this plugin:

- ✅ Command hooks exit 0 (warn) or 2 (block violations) - never exit 1
- ✅ Agent hooks use Haiku model with timeouts (20-30s)
- ✅ Only read from stdin (JSON input from Claude Code)
- ✅ Only output to stdout/stderr (structured JSON)
- ✅ Metrics writes go to local SQLite only (`${CLAUDE_PLUGIN_DATA}/metrics.db`)
- ❌ Do NOT modify source files
- ❌ Do NOT execute network requests (except Sentry agent via MCP channel)
- ❌ Do NOT spawn subprocesses
- ❌ Do NOT access environment variables (except `$CLAUDE_PLUGIN_ROOT`, `$CLAUDE_PLUGIN_DATA`, `$CLAUDE_PLUGIN_OPTION_*`)

## Optional Features

### RAG Knowledge Base (Disabled by Default)

The optional RAG system requires explicit setup and:

- Uses local Ollama (no external API calls)
- Stores embeddings locally in `knowledge/.cache/`
- Does NOT send data to external services

## Permissions Required

| Permission | Required | Reason |
|------------|----------|--------|
| File read | Yes | Code analysis and context gathering |
| File write | Yes | Code generation (user-initiated) |
| Shell execution | Yes | Validation hooks (read-only) |
| Network | Conditional | See network access table below |

### Network Access (full disclosure)

| Feature | Default | Destination | Data sent |
|---------|---------|-------------|-----------|
| Regex + static analysis hooks (Level 1-3) | On | None | Nothing. Fully offline |
| Agent hooks (4 Haiku agents) | On (`agent_hooks: true`) | Anthropic API (via Claude Code) | Edited file content for semantic analysis. ~4 calls per Write/Edit, ~$0.15-0.30/session. Disable with `agent_hooks: false` |
| Sentry context agent | Off (needs `sentry_org`/`sentry_project`) | Sentry API (via MCP, read-only) | File paths to query matching errors |
| Knowledge RAG MCP server | No-op unless `ai-ml` pack active | npm registry (one-time install), local Ollama | Nothing to third parties. Embeddings computed and stored locally |

With `agent_hooks: false` and no Sentry config, the plugin runs fully offline.

## Reporting Vulnerabilities

If you discover a security vulnerability:

1. **Do NOT** open a public issue
2. Email: security@buldee.com (or contact@buldee.com)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact

We will respond within 48 hours and work with you on disclosure.

## Audit Trail

| Version | Date | Auditor | Notes |
|---------|------|---------|-------|
| 1.0.0 | 2025-02-03 | Internal | Initial security review |
| 1.1.0 | 2025-02-04 | Internal | Skills migrated to commands, hooks hardened |
| 1.2.0 | 2026-03-28 | Internal | 3-level validation, blocking hooks (exit 2), SQLite metrics |
| 1.3.0 | 2026-03-28 | Internal | Agent hooks (Haiku), correction learning, env var fix |
| 1.4.0 | 2026-03-28 | Internal | Sentry MCP channel, channel lifecycle library |
| 1.5.0 | 2026-03-28 | Internal | 7 craftsman agents, Agent Teams support, enriched reviewers |
| 2.0.0 | 2026-03-28 | Internal | Agent Teams, /craftsman:start onboarding, /craftsman:ci command |
| 2.1.0 | 2026-03-29 | Internal | Rules engine, CI adapters, circuit breaker, pack template variants |
| 2.2.0 | 2026-03-29 | Internal | SQL injection fix (metrics-query.py), schema validation, atomic commits, monorepo sampling |

## Third-Party Dependencies

### Core hooks: zero dependencies

The hook system (validation, rules engine, metrics, bias detection) uses only system tools:

- `bash` (system)
- `jq` (optional, for JSON parsing)
- `grep` (system)
- `python3` (system, for parameterized SQL queries and YAML parsing)

No npm packages, no external binaries, no network calls in the hook path.

### Knowledge RAG MCP server: npm dependencies (opt-in)

`plugin.json` declares one MCP server (`knowledge-rag`, launched via `packs/ai-ml/mcp/knowledge-rag/start.mjs`). Its behavior:

- **`ai-ml` pack NOT active (default):** runs a no-op MCP server using Node.js builtins only. Zero tools exposed, zero installs, zero network.
- **`ai-ml` pack active:** on first launch, runs `npm install` in the plugin directory to fetch its dependencies (`@modelcontextprotocol/sdk`, `better-sqlite3` with native compilation, `pdf-parse`, `tsx`), then builds and starts the server. Embeddings use local Ollama; no data leaves the machine.

The auto-install is scoped to the plugin's own directory and only triggers when you explicitly enable the `ai-ml` pack. Review `start.mjs` before enabling if your environment restricts package installation.

## Code Verification

Before installing, you can verify the hooks:

```bash
# Clone and inspect
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
cd ai-craftsman-superpowers

# Review the hook scripts (executable code also lives in ci/, packs/*/hooks/,
# and packs/ai-ml/mcp/knowledge-rag/start.mjs - review those too)
cat hooks/bias-detector.sh
cat hooks/post-write-check.sh

# Verify no external network calls in hooks
grep -rn "curl\|wget" hooks/ --include='*.sh'
# Expected: exactly one match - healthcheck.sh curls http://localhost:11434
# (local Ollama availability probe, 2s timeout, no data sent). Nothing external.
```

## Supported Versions

| Version | Supported |
|---------|-----------|
| 3.x | ✅ Active development |
| 2.x | ⚠️ Security fixes only |
| < 2.0 | ❌ |
