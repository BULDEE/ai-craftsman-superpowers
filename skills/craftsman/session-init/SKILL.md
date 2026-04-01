---
name: session-init
description: Internal skill for session initialization. Loads craftsman context and checks configuration.
disable-model-invocation: true
---

# Craftsman Session Initialized

Welcome to **AI Craftsman Superpowers**.

## Configuration Check

**First, check if setup has been completed:**

```bash
cat ~/.claude/.craft-config.yml 2>/dev/null
```

### If config file NOT found:

Display this warning:

```
Setup Required

AI Craftsman Superpowers is installed but not configured.

Run /craftsman:setup to:
- Set your profile (name, DISC type)
- Enable bias protection
- Select technology packs (Symfony, React, AI)

Core commands are available, but pack-specific commands
require setup to enable the appropriate packs.
```

Then show only core commands (see below).

### If config file found:

Parse the YAML and display personalized greeting:

```
Welcome back, {profile.name}!

Your Profile:
  DISC Type: {profile.disc_type}
  Bias Protection: {profile.biases}

Enabled Packs: {list enabled packs}
```

Then show commands based on enabled packs.

---

## Available Commands

### Core (Always Available)

| Command | Purpose |
|---------|---------|
| `/craftsman:setup` | Configure or reconfigure the plugin |
| `/craftsman:design` | DDD design with challenge phases |
| `/craftsman:debug` | Systematic debugging (ReAct pattern) |
| `/craftsman:plan` | Structured planning & execution |
| `/craftsman:challenge` | Architecture review |
| `/craftsman:verify` | Evidence-based verification |
| `/craftsman:spec` | Specification-first (TDD/BDD) |
| `/craftsman:refactor` | Systematic refactoring |
| `/craftsman:test` | Pragmatic testing |
| `/craftsman:git` | Safe git workflow |
| `/craftsman:parallel` | Parallel agent orchestration |

### Scaffolding (if `packs.symfony: true` or `packs.react: true`)

| Command | Purpose |
|---------|---------|
| `/craftsman:scaffold entity` | Scaffold DDD entity with Value Objects |
| `/craftsman:scaffold usecase` | Scaffold Use Case with Command/Handler |
| `/craftsman:scaffold component` | Scaffold React component with tests |
| `/craftsman:scaffold hook` | Scaffold TanStack Query hook |
| `/craftsman:scaffold api-resource` | API Platform resource with State Provider |
| `/craftsman:scaffold pack` | Create new community pack |

### AI Pack (if `packs.ai: true`)

| Command | Purpose |
|---------|---------|
| `/craftsman:rag` | Design RAG pipeline |
| `/craftsman:mlops` | MLOps audit |
| `/craftsman:agent-design` | Agent 3P pattern |

### Utility (Always Available)

| Command | Purpose |
|---------|---------|
| `/craftsman:scaffold` | Unified scaffolder (entity, usecase, component, hook, api-resource, pack) |

---

## Bias Protection Active

The following biases are being monitored (based on your config):

- **Acceleration** - Will warn if rushing to code
- **Scope Creep** - Will warn if adding features beyond scope
- **Over-Optimization** - Will warn if premature abstraction
- **Dispersion** - Will warn if jumping between topics

## Code Rules Enforced

**PHP:**
- `declare(strict_types=1)` required
- `final class` required
- No public setters
- No `new DateTime()` (use Clock)

**TypeScript:**
- No `any` types
- Named exports only
- No non-null assertions

---

Ready to build quality software. How can I help?
