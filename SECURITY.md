# Security Policy

## Overview

The **ai-craftsman-superpowers** plugin is designed with security as a priority. This document details what the plugin does and does NOT do.

## What This Plugin Does

### Commands (22 total)

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

### Hooks (6 scripts, 8 events, 4 agent hooks)

Hooks execute **shell scripts** and **agent prompts** at specific lifecycle events:

| Hook | Event | What It Does | Security |
|------|-------|--------------|----------|
| `session-start.sh` | SessionStart | Initialization, config loading | READ-ONLY |
| `pre-write-check.sh` | PreToolUse | Layer validation before write | READ-ONLY |
| `post-write-check.sh` | PostToolUse | Code rule enforcement after write | READ-ONLY |
| `bias-detector.sh` | UserPromptSubmit | Cognitive bias detection | READ-ONLY |
| `file-changed.sh` | FileChanged | Tracks file modifications | READ-ONLY |
| `session-metrics.sh` | SessionEnd | Records session summary to SQLite | WRITE (local DB only) |
| DDD verifier agent | PostToolUse | Semantic architecture check | READ-ONLY |
| Sentry context agent | PostToolUse | Error context from Sentry MCP | READ-ONLY (via MCP) |
| Project analyzer agent | InstructionsLoaded | Architectural context map | READ-ONLY |
| Final reviewer agent | Stop | Architecture validation (strict mode) | READ-ONLY |

#### Hook Security Guarantees

All hooks in this plugin:

- ✅ Command hooks exit 0 (warn) or 2 (block violations) — never exit 1
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
| Network | No | Plugin works fully offline |

## Reporting Vulnerabilities

If you discover a security vulnerability:

1. **Do NOT** open a public issue
2. Email: security@buldee.com (or contact@woprrr.dev)
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

## Third-Party Dependencies

This plugin has **zero runtime dependencies**. Hooks use only:

- `bash` (system)
- `jq` (optional, for JSON parsing)
- `grep` (system)

No npm packages, no external binaries, no network calls.

## Code Verification

Before installing, you can verify the hooks:

```bash
# Clone and inspect
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
cd ai-craftsman-superpowers

# Review hooks (the only executable code)
cat hooks/bias-detector.sh
cat hooks/post-write-check.sh

# Verify no network calls
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing
```

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.5.x | ✅ |
| 1.4.x | ✅ |
| 1.3.x | ✅ |
| 1.2.x | ✅ |
| 1.1.x | ✅ |
| 1.0.x | ✅ |
| < 1.0 | ❌ |
