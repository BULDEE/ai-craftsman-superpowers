# Security Policy

## Overview

The **ai-craftsman-superpowers** plugin is designed with security as a priority. This document details what the plugin does and does NOT do.

## What This Plugin Does

### Commands (20 total)

Commands are **prompt templates** that guide Claude's behavior. They:

- ✅ Read files to understand context
- ✅ Write/edit code files when instructed
- ✅ Search codebase with Glob/Grep
- ❌ Do NOT execute arbitrary code
- ❌ Do NOT access network resources
- ❌ Do NOT modify system files

### Agents (5 total)

Agents are **specialized reviewers** that:

- ✅ Read code for analysis
- ✅ Output review findings
- ❌ Do NOT modify code automatically
- ❌ Do NOT have elevated permissions

### Hooks (3 total)

Hooks execute **shell scripts** at specific lifecycle events:

| Hook | Trigger | What It Does | Security |
|------|---------|--------------|----------|
| `bias-detector.sh` | User prompt submission | Reads prompt, outputs warnings | READ-ONLY |
| `post-write-check.sh` | After Write tool | Reads file, validates rules | READ-ONLY |
| `PreToolUse` (echo) | Before Write/Edit | Logs message | NO FILE ACCESS |

#### Hook Security Guarantees

All hooks in this plugin:

- ✅ Exit with code 0 (never block operations)
- ✅ Only read from stdin (JSON input from Claude Code)
- ✅ Only output to stdout/stderr (warnings)
- ❌ Do NOT modify any files
- ❌ Do NOT execute network requests
- ❌ Do NOT spawn subprocesses
- ❌ Do NOT access environment variables (except `$CLAUDE_PLUGIN_DIR`)

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
| 1.1.x | ✅ |
| 1.0.x | ✅ |
| < 1.0 | ❌ |
