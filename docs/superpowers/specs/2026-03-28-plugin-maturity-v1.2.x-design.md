# Plugin Maturity v1.2.x — Design Spec

> **Scope:** Quick wins leveraging native Claude Code plugin features.
> **Predecessor:** Phase 0 (v1.2.0 — Foundations + Semantic Analysis)
> **Successor:** Spec 2 — Semantic Intelligence v1.3.0 (hook type `agent`, `channels`)

**Goal:** Mature the plugin by exploiting underused native Claude Code features (userConfig, SessionStart, FileChanged) and cleaning up technical debt (version duplication).

**Architecture:** Config resolution hierarchy (userConfig global < .craft-config.yml project < craftsman-ignore line). Two new hooks (SessionStart, FileChanged) complement existing PreToolUse/PostToolUse pair. Shared config library consumed by all hooks.

**Tech Stack:** Bash, SQLite, Claude Code Plugin API (userConfig, hook events)

---

## 1. Version Cleanup

### Problem

`version: "1.2.0"` is defined in both `plugin.json` and `marketplace.json`. For plugins with `source: "./"`, plugin.json silently wins. This creates a desync risk on future version bumps.

### Solution

Remove `version` from `marketplace.json > plugins[0]`. plugin.json is the single source of truth.

### Files

- Modify: `.claude-plugin/marketplace.json` — remove `version` key from plugins[0]

---

## 2. userConfig

### Purpose

Allow users to configure the plugin at enable time via Claude Code's native `userConfig` system. Two global parameters control hook behavior.

### Parameters

| Parameter | Type | Values | Default | Purpose |
|-----------|------|--------|---------|---------|
| `strictness` | string | `strict`, `moderate`, `relaxed` | `strict` | Controls which rules block (exit 2) vs warn (exit 0) |
| `stack` | string | `symfony`, `react`, `fullstack`, `other` | `fullstack` | Activates/deactivates rules by language |

### Strictness Matrix

| Strictness | PHP001-004, TS001-003 | LAYER001-003 | Warnings (PHP005, WARN-*) |
|------------|----------------------|--------------|--------------------------|
| `strict` | Block (exit 2) | Block (exit 2) | Warn (exit 0) |
| `moderate` | Warn (exit 0) | Block (exit 2) | Warn (exit 0) |
| `relaxed` | Warn (exit 0) | Warn (exit 0) | Warn (exit 0) |

### Stack Matrix

| Stack | PHP rules | TS rules | Layer rules |
|-------|-----------|----------|-------------|
| `symfony` | Active | Skip | PHP layers only |
| `react` | Skip | Active | TS layers only |
| `fullstack` | Active | Active | All |
| `other` | Skip | Skip | Skip |

### Files

- Modify: `.claude-plugin/plugin.json` — add `userConfig` object

### plugin.json Addition

```json
{
  "userConfig": {
    "strictness": {
      "type": "string",
      "description": "Enforcement level: strict (block violations), moderate (block critical only), relaxed (warn only)",
      "default": "strict"
    },
    "stack": {
      "type": "string",
      "description": "Your tech stack: symfony (PHP only), react (TS only), fullstack (both), other (minimal rules)",
      "default": "fullstack"
    }
  }
}
```

---

## 3. Config Resolution Library

### Purpose

Shared library that resolves effective configuration from three sources with clear precedence:

1. **userConfig** (global, set at plugin activation) — lowest priority
2. **.craft-config.yml** (per-project, set via `/craftsman:setup`) — overrides userConfig
3. **craftsman-ignore** (per-line, inline in code) — highest priority (handled by hooks directly)

### API

```bash
source "${SCRIPT_DIR}/lib/config.sh"

config_strictness    # Returns: strict | moderate | relaxed
config_stack         # Returns: symfony | react | fullstack | other
config_php_enabled   # Returns: 0 (true) or 1 (false)
config_ts_enabled    # Returns: 0 (true) or 1 (false)
config_should_block "PHP001"  # Returns: 0 (block) or 1 (warn)
```

### Resolution Logic

For each parameter:
1. Check `.craft-config.yml` in `$PWD` — if key exists, use it
2. Check `$CLAUDE_USER_CONFIG_<key>` env var — if set, use it
3. Fall back to hardcoded default

### Adaptation Point

The env var name `CLAUDE_USER_CONFIG_<key>` is the expected mechanism for Claude Code to expose userConfig values to command-type hooks. If the actual mechanism differs, only this library needs to change — all hooks consume the API, not the raw env vars.

### Files

- Create: `hooks/lib/config.sh`

### Integration with Existing Hooks

`pre-write-check.sh` and `post-write-check.sh` currently have hardcoded behavior (always block critical rules, always check both PHP and TS). After this change:

- Both hooks source `config.sh`
- Stack filtering: skip PHP checks if `config_php_enabled` returns false, same for TS
- Blocking decision: `config_should_block "$rule"` instead of hardcoded `exit 2`
- craftsman-ignore continues to work as-is (evaluated after config resolution)

---

## 4. SessionStart Hook

### Purpose

Automatically load project context when a Claude Code session begins. Inject a `systemMessage` with the active profile so Claude knows which rules are in effect.

### Behavior

1. Detect project type from filesystem (composer.json, package.json)
2. Read effective config via `config.sh`
3. Initialize metrics DB (idempotent)
4. Check for first-time setup (no `.craft-config.yml`)
5. Output `systemMessage` with active profile

### Project Detection

```bash
detect_project_type() {
  local has_php=false has_ts=false
  [[ -f "${PWD}/composer.json" ]] && has_php=true
  [[ -f "${PWD}/package.json" ]] && has_ts=true
  if $has_php && $has_ts; then echo "fullstack"
  elif $has_php; then echo "symfony"
  elif $has_ts; then echo "react"
  else echo "other"
  fi
}
```

### Config Mismatch Warning

If detected project type does not match configured stack, warn:

```
Config says 'symfony' but package.json detected. Consider 'fullstack'. Run /craftsman:setup to update.
```

### First Session Detection

If `.craft-config.yml` does not exist in `$PWD`:

```
No .craft-config.yml found. Run /craftsman:setup to configure this project.
```

### Output Format

Non-blocking (exit 0 always). JSON systemMessage:

```json
{
  "systemMessage": "Craftsman v1.2.x active | Stack: fullstack | Strictness: strict | PHP rules: ON | TS rules: ON | Metrics: initialized"
}
```

### Files

- Create: `hooks/session-start.sh`
- Modify: `hooks/hooks.json` — add `SessionStart` event

### hooks.json Addition

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\""
        }
      ]
    }
  ]
}
```

---

## 5. FileChanged Hook

### Purpose

Incremental validation when any file changes in the workspace — including external modifications (IDE saves, git operations). Complements the Write/Edit hooks that only cover Claude's writes.

### Comparison with Existing Hooks

| Aspect | PostToolUse (Write\|Edit) | FileChanged |
|--------|--------------------------|-------------|
| Trigger | Claude writes | Any source (IDE, git, user) |
| Enforcement | Blocking (exit 2) | Non-blocking (exit 0 always) |
| Depth | 3 levels (regex + static + architecture) | Level 1 only (regex, <50ms) |
| Role | Gatekeeper | Monitoring |

### Behavior

1. Read file path from stdin JSON
2. Filter: `.php`, `.ts`, `.tsx` only — silent exit 0 for others
3. Check `config_stack()` — skip if language disabled
4. Read file content, run Level 1 regex checks (same rules as post-write-check)
5. Record violations to metrics DB (severity: `info`)
6. Output `systemMessage` if violations found, silent if clean

### Output Format

Non-blocking (exit 0 always). Only outputs when violations detected:

```json
{
  "systemMessage": "FileChanged: src/Domain/User.php — 1 issue detected (PHP002: non-final class). Not blocking — use Write/Edit for enforcement."
}
```

Silent (no output) when file is clean.

### Performance Constraint

Level 1 only (pure regex). No external tool calls. Target: <50ms per file.

### Value Proposition

1. **External regression detection** — git checkout bringing non-compliant code
2. **Complete monitoring** — metrics even for non-Claude changes
3. **Correction learning preparation** — logs file state before/after user intervention (feeds Spec 2)

### Files

- Create: `hooks/file-changed.sh`
- Modify: `hooks/hooks.json` — add `FileChanged` event

### hooks.json Addition

```json
{
  "FileChanged": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/file-changed.sh\""
        }
      ]
    }
  ]
}
```

---

## File Summary

| Action | File | Section |
|--------|------|---------|
| Modify | `.claude-plugin/marketplace.json` | 1. Version Cleanup |
| Modify | `.claude-plugin/plugin.json` | 2. userConfig |
| Create | `hooks/lib/config.sh` | 3. Config Resolution |
| Modify | `hooks/pre-write-check.sh` | 3. Config Integration |
| Modify | `hooks/post-write-check.sh` | 3. Config Integration |
| Create | `hooks/session-start.sh` | 4. SessionStart |
| Create | `hooks/file-changed.sh` | 5. FileChanged |
| Modify | `hooks/hooks.json` | 4 + 5. New events |
| Create | `tests/hooks/test-config.sh` | 3. Config tests |
| Modify | `tests/hooks/test-hooks.sh` | 4 + 5. New hook tests |
| Modify | `tests/run-tests.sh` | Integration |

---

## Testing Strategy

### Config Resolution Tests (test-config.sh)

- Default values when no config exists (strictness=strict, stack=fullstack)
- .craft-config.yml overrides userConfig env var
- userConfig env var overrides default
- config_php_enabled returns false for stack=react
- config_ts_enabled returns false for stack=symfony
- config_should_block returns false for relaxed mode
- config_should_block returns true for LAYER rules in moderate mode

### SessionStart Hook Tests

- Outputs valid JSON systemMessage
- Detects composer.json → symfony
- Detects package.json → react
- Detects both → fullstack
- Warns on config mismatch
- Suggests /craftsman:setup when no .craft-config.yml

### FileChanged Hook Tests

- Ignores non-PHP/TS files (exit 0, no output)
- Detects PHP violations (non-blocking)
- Detects TS violations (non-blocking)
- Respects stack config (skips PHP rules when stack=react)
- Records violations to metrics DB
- Silent when file is clean

### Existing Hook Regression Tests

- pre-write-check still blocks layer violations in strict mode
- pre-write-check warns (not blocks) layer violations in relaxed mode
- post-write-check respects stack filtering
- post-write-check respects strictness levels

---

## Version

This work ships as **v1.2.1** (patch: no breaking changes, additive features, backward compatible). Default config values (`strict` + `fullstack`) preserve current behavior exactly.

---

## Out of Scope (deferred to Spec 2: Semantic Intelligence v1.3.0)

- Hook type `agent` (agentic verifier with tool access)
- `channels` (message injection for architectural context)
- Correction learning system
- CI export
- LSP server integration
