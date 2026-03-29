# AI Craftsman Superpowers

<div align="center">

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A51.0.33-blueviolet)](https://code.claude.com)
[![Version](https://img.shields.io/badge/Version-2.5.0-blue)](CHANGELOG.md)
[![Commands](https://img.shields.io/badge/Commands-15-orange)]()
[![Agents](https://img.shields.io/badge/Agents-5-red)]()
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Transform Claude into a disciplined Senior Software Craftsman**

[Installation](#installation) •
[Skills](#skills) •
[Security](#security) •
[Contributing](#contributing)

</div>

---

> Senior craftsman methodology for Claude Code. DDD, Clean Architecture, TDD.

Transform Claude Code into a disciplined software engineer with battle-tested methodologies.

## Requirements

- Claude Code v1.0.33 or later
- Run `claude --version` to check

## Installation

### From GitHub (Recommended)

```bash
# Step 1: Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# Step 2: Install the plugin
/plugin install craftsman@BULDEE-ai-craftsman-superpowers

# Step 3: Restart Claude Code
exit
claude
```

### From Local Path

```bash
# If you cloned the repo locally
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
/plugin install craftsman@/path/to/ai-craftsman-superpowers
```

### Verify Installation

```bash
# Open plugin manager
/plugin

# Go to "Installed" tab to see craftsman plugin
# Go to "Errors" tab if skills don't appear
```

## API Cost Model

The plugin uses AI agent hooks for deep semantic analysis beyond regex. These are **optional** and can be disabled.

| Agent Hook | Trigger | Model | Purpose |
|------------|---------|-------|---------|
| DDD Verifier | Each Write/Edit | Haiku | Layer violations, aggregate boundaries, naming |
| Sentry Context | Each Write/Edit | Haiku | Error context from Sentry (if configured) |
| Architecture Analyzer | Session start | Haiku | Build project context map |
| Final Reviewer | Session end | Haiku | Validate architecture (strict mode only) |

**Estimated cost:** ~$0.15-0.30 per session (50 Write/Edit operations)

**Opt-out:** Set `agent_hooks: false` in plugin config to disable all agent hooks. Regex-based validation (Level 1) and static analysis (Level 2) continue to work without agent hooks.

## Quick Start

After installation, try:

```bash
# Design a new entity (follows DDD phases)
/craftsman:design
I need to create a User entity for an e-commerce platform.

# Debug an issue systematically (ReAct pattern)
/craftsman:debug
I have a memory leak in my Node.js app.

# Plan a feature implementation
/craftsman:plan
I need to migrate our API to microservices.

# Review code for architecture issues
/craftsman:challenge
[paste your code]
```

See [`/examples`](examples/) for detailed usage examples with expected outputs.

## Why Craftsman? — Key Differentiators

What makes this plugin unique in the Claude Code ecosystem:

| Differentiator | What It Does | Why It Matters |
|----------------|-------------|----------------|
| **Iron Law Pattern** | Forces canonical example loading before ANY code generation | Zero drift — generated code matches project standards exactly, every time |
| **Cognitive Bias Detector** | Real-time detection of acceleration, scope creep, sunk cost, anchoring biases in user prompts | The only Claude Code plugin that protects against human cognitive biases |
| **Correction Learning** | Records when you fix Claude-generated code, injects patterns at next session start | Claude learns from its own mistakes — error rate decreases over time |
| **3-Level Validation** | Regex (<50ms) + Static Analysis (<2s) + Architecture (<2s) on every write | Sub-3-second quality gate that catches issues from typos to layer violations |
| **Rules Engine** | Per-project rule override with 3-level inheritance (global → project → directory) | Enterprise-ready: legacy code coexists with strict new code in the same repo |
| **Circuit Breaker** | Production-grade external service protection (closed → open → half-open) with stale cache | Sentry goes down? Plugin keeps working with cached data |
| **Multi-Provider CI** | Same rules in hooks AND CI across GitHub Actions, GitLab CI, Bitbucket Pipelines, Jenkins | One source of truth — what blocks locally blocks in CI, zero drift |
| **Metrics & Trends** | SQLite-backed violation tracking with 7d/30d trend analysis | Data-driven quality improvement: see which rules get violated most |

> **No other Claude Code plugin combines real-time cognitive protection with automated code quality enforcement and cross-session learning.**

## Commands

All commands are explicitly invoked with `/craftsman:command-name`. See [ADR-0007](docs/adr/0007-commands-over-skills.md) for the rationale.

### Core Methodology

| Command | Purpose |
|---------|---------|
| `/craftsman:design` | DDD design with challenge phases (Understand → Challenge → Recommend → Implement) |
| `/craftsman:debug` | Systematic debugging using ReAct pattern |
| `/craftsman:plan` | Structured planning & execution with checkpoints |
| `/craftsman:challenge` | Senior architecture review and code challenge |
| `/craftsman:verify` | Evidence-based verification before completion claims |
| `/craftsman:spec` | Specification-first development (TDD/BDD) |
| `/craftsman:refactor` | Systematic refactoring with behavior preservation |
| `/craftsman:test` | Pragmatic testing following Fowler/Martin principles |
| `/craftsman:git` | Safe git workflow with destructive command protection |
| `/craftsman:parallel` | Parallel agent orchestration for independent tasks |

### Symfony/PHP Scaffolding

| Command | Purpose |
|---------|---------|
| `/craftsman:entity` | Scaffold DDD entity with Value Objects, Events, Tests |
| `/craftsman:usecase` | Scaffold use case with Command/Handler pattern |

### React/TypeScript Scaffolding

| Command | Purpose |
|---------|---------|
| `/craftsman:component` | Scaffold React component with TypeScript, tests, Storybook |
| `/craftsman:hook` | Scaffold TanStack Query hook with tests |

### AI/ML Engineering

| Command | Purpose |
|---------|---------|
| `/craftsman:rag` | Design RAG pipelines (ingestion, retrieval, generation) |
| `/craftsman:mlops` | Audit ML projects for production readiness |
| `/craftsman:agent-design` | Design AI agents using 3P pattern (Perceive/Plan/Perform) |

### Utilities

| Command | Purpose |
|---------|---------|
| `/craftsman:source-verify` | Verify AI capabilities against official documentation |
| `/craftsman:agent-create` | Interactively create bounded context agents |
| `/craftsman:scaffold` | Analyze code and generate context agents |
| `/craftsman:metrics` | Display quality metrics dashboard (violations, trends, sessions) |
| `/craftsman:setup` | Interactive setup wizard (DISC profile, stack, packs) |
| `/craftsman:team` | Create and manage agent teams for collaborative tasks |
| `/craftsman:start` | Onboarding wizard for first-time users |

### CI/CD Integration

| Command | Purpose |
|---------|---------|
| `/craftsman:ci` | Export quality gates to CI/CD pipeline (GitHub, GitLab, Bitbucket, Jenkins) |

> **Why source-verify?** AI tools evolve rapidly. This command ensures claims about capabilities are verified against official documentation before being stated as facts. See [ADR-004](docs/adr/004-official-documentation-verification.md).

## Features

### Bias Protection (Active by Default)

Hooks automatically detect and warn about cognitive biases:

| Bias | Trigger | Protection |
|------|---------|------------|
| **Acceleration** | "vite", "quick", "just do it" | STOP - Design first |
| **Scope Creep** | "et aussi", "while we're at it" | STOP - Is this in scope? |
| **Over-Optimization** | "abstraire", "generalize" | STOP - YAGNI |

### Semantic Intelligence (v1.3.0+)

Agent hooks provide semantic analysis beyond regex:

| Hook | Event | Purpose |
|------|-------|---------|
| DDD Verifier (Haiku) | PostToolUse | Checks layer violations, aggregate boundaries, value objects, naming |
| Sentry Context (Haiku) | PostToolUse | Injects error context from Sentry for edited files |
| Project Analyzer (Haiku) | InstructionsLoaded | Builds architectural context map at session start |
| Final Reviewer (Haiku) | Stop | Validates architecture before session end (strict mode) |

### Correction Learning (v1.3.0+)

The plugin detects when you fix Claude-generated code and records patterns in the metrics database. At session start, recent correction trends are injected so Claude learns from past mistakes. View trends with `/craftsman:metrics`.

### Sentry Channel Integration (v1.4.0+)

Sentry MCP server is bound as a channel. When editing files, the PostToolUse agent hook automatically queries Sentry for related errors and injects context. Configure via:

```bash
# In plugin settings
sentry_org: your-org
sentry_project: your-project
sentry_token: (stored securely)
```

### Specialized Agents (v1.5.0)

12 agents — 5 reviewers + 7 craftsmen:

| Agent | Role | Model |
|-------|------|-------|
| `team-lead` | Orchestrator — delegates, challenges, never codes | Opus |
| `backend-craftsman` | PHP/Symfony expert (Symfony.com + API Platform refs) | Sonnet |
| `frontend-craftsman` | React/TS expert (65 Vercel best practices) | Sonnet |
| `architect` | DDD/Clean Architecture validation (read-only) | Sonnet |
| `ai-engineer` | RAG, LLM, MCP server, agent design | Sonnet |
| `ui-ux-director` | UX, WCAG 2.1 AA, design tokens | Sonnet |
| `doc-writer` | ADRs, README, CHANGELOG, runbooks | Haiku |
| `architecture-reviewer` | Clean Architecture compliance | Sonnet |
| `security-pentester` | Security vulnerability detection | Sonnet |
| `symfony-reviewer` | Symfony/DDD best practices | Sonnet |
| `react-reviewer` | React patterns and hooks | Sonnet |
| `ai-reviewer` | RAG/MLOps/Agent best practices | Sonnet |

### Code Rule Enforcement (v1.2.0+)

Hooks validate your code automatically with **3-level analysis**:

**Level 1 — Fast Regex (<50ms):** Runs on every write/edit.

| Rule | Language | Check |
|------|----------|-------|
| PHP001 | PHP | `declare(strict_types=1)` required |
| PHP002 | PHP | `final class` on all classes |
| PHP003 | PHP | No public setters |
| PHP004 | PHP | No `new DateTime()` direct usage |
| PHP005 | PHP | No empty catch blocks |
| TS001 | TypeScript | No `any` types |
| TS002 | TypeScript | Named exports only |
| TS003 | TypeScript | No non-null assertions (`!`) |
| LAYER001 | PHP | Domain cannot import Infrastructure |
| LAYER002 | PHP | Domain cannot import Presentation |
| LAYER003 | PHP | Application cannot import Presentation |

**Level 2 — Static Analysis (<2s):** PHPStan, ESLint (when installed). Graceful degradation if tools are absent.

**Level 3 — Architecture (<2s):** Deptrac, dependency-cruiser (when installed).

**Suppressing rules:** Add `// craftsman-ignore: RULE_ID` inline to suppress a specific rule.

Violations are **blocking** (exit 2) — Claude must fix the code before proceeding. All violations are recorded in a local SQLite database for trend tracking via `/craftsman:metrics`.

### Custom Rule Engine (v2.1.0+)

Override any rule per-project or per-directory with 3-level config inheritance:

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Short form: `PHP001: warn` / `TS001: ignore`. Long form: custom rules with regex, severity, languages.

### CI/CD Integration (v2.1.0+)

Same rules engine runs in hooks (real-time) AND CI (pipeline). 4 providers with adapter pattern:

| Provider | Template | Annotations |
|----------|----------|-------------|
| GitHub Actions | `craftsman-quality-gate.yml` | `::error` inline |
| GitLab CI | `.gitlab-ci.craftsman.yml` | codequality artifact |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Reports API |
| Jenkins | `Jenkinsfile.craftsman` | Console output |

Use `/craftsman:ci export` to generate or `craftsman-ci.sh init --provider` from CLI.

### Circuit Breaker (v2.1.0+)

Production-grade protection for external services (Sentry). 3 states: closed → open → half-open. File-based cache with TTL/LRU eviction serves stale data during outages.

### Pack Template Variants (v2.1.0+)

Each scaffolder offers template selection before generating code:

| Pack | Template | Use Case |
|------|----------|----------|
| Symfony | `bounded-context` | Standard DDD entity |
| Symfony | `crud-api` | API Platform 4 CRUD |
| Symfony | `event-sourced` | Event Sourcing + Projections |
| React | `bounded-context` | Standard TanStack Query hook |
| React | `form-heavy` | Multi-step wizard + Zod |
| React | `dashboard-data` | TanStack Table + Recharts |

### Schema Validation & Safety (v2.2.0+)

- **Hooks schema validation** — `session-start.sh` validates all hook events against the supported set at startup
- **Atomic commit enforcement** — Stop hook warns when >15 files modified, caps inspection at 20
- **Monorepo sampling** — InstructionsLoaded switches to directory-level analysis for large codebases (>100 files)

## Advanced: Knowledge Base RAG (Optional)

The plugin includes an **optional** MCP server for RAG (Retrieval-Augmented Generation) over local documents.

> **Note:** The plugin is fully functional without the MCP. This is a power-user feature.

### Prerequisites

- Node.js 20+
- [Ollama](https://ollama.ai) with `nomic-embed-text` model

### Setup

```bash
# 1. Install Ollama
brew install ollama && ollama pull nomic-embed-text
ollama serve  # Keep running

# 2. Build MCP server
cd ~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag
npm install && npm run build

# 3. Create knowledge directory & add documents
mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge
cp ~/your-docs/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/

# 4. Index knowledge base
npm run index:ollama

# 5. Configure Claude Code
# Add to ~/.claude/settings.local.json:
```

```json
{
  "mcpServers": {
    "knowledge-rag": {
      "command": "node",
      "args": ["~/.claude/plugins/marketplaces/ai-craftsman-superpowers/ai-pack/mcp/knowledge-rag/dist/src/index.js"]
    }
  }
}
```

```bash
# 6. Restart Claude Code
```

See [Local RAG Setup Guide](docs/guides/local-rag-ollama.md) and [MCP Reference](docs/reference/mcp-servers.md) for detailed instructions.

> **Why Ollama?** 100% local, free, private. See [ADR-0002](docs/adr/0002-ollama-over-openai.md).

## CLAUDE.md Configuration

Understanding how to structure your CLAUDE.md files is crucial for optimal plugin integration.

### Priority Hierarchy

```
1. Explicit user instruction     ← Highest
2. Project CLAUDE.md (./CLAUDE.md)
3. Plugin (skills, hooks, knowledge)
4. Global CLAUDE.md (~/.claude/CLAUDE.md)  ← Lowest
```

### Quick Rules

| Put in Global | Put in Project | Let Plugin Handle |
|---------------|----------------|-------------------|
| DISC profile | Architecture | Code enforcement |
| Communication style | Key entities | Design patterns |
| Personal biases | External services | Canonical examples |
| Stack versions | Project rules | Skill routing |

See **[CLAUDE.md Best Practices Guide](docs/guides/claude-md-best-practices.md)** for complete documentation.

## Architecture Decisions

See [`/docs/adr`](docs/adr/) for Architecture Decision Records:

- [ADR-0001: Skills over Prompts](docs/adr/0001-skills-over-prompts.md)
- [ADR-0002: Ollama over OpenAI](docs/adr/0002-ollama-over-openai.md)
- [ADR-0003: SQLite over pgvector](docs/adr/0003-sqlite-over-pgvector.md)
- [ADR-0004: 3P Agent Pattern](docs/adr/0004-3p-agent-pattern.md)
- [ADR-0005: Knowledge-First Architecture](docs/adr/0005-knowledge-first-architecture.md)
- [ADR-0006: Project-Specific Knowledge](docs/adr/0006-project-specific-knowledge.md)
- [ADR-0007: Commands over Skills](docs/adr/0007-commands-over-skills.md)
- [ADR-001: Model Tiering Strategy](docs/adr/001-model-tiering.md)
- [ADR-002: Context Fork Strategy](docs/adr/002-context-fork-strategy.md)
- [ADR-003: Progressive Disclosure](docs/adr/003-progressive-disclosure.md)
- [ADR-004: Official Documentation Verification](docs/adr/004-official-documentation-verification.md)

## Examples

See [`/examples`](examples/) for detailed usage examples:

- [Design: Create Entity](examples/design/01-create-entity.md)
- [Debug: Memory Leak](examples/debug/01-memory-leak.md)
- [Challenge: Code Review](examples/challenge/01-code-review.md)
- [Plan: Migration](examples/plan/01-migration-microservices.md)
- [Git: Safe Commit](examples/git/01-safe-commit.md)
- [Test: Testing Strategy](examples/test/01-testing-strategy.md)

## Architecture

```
hooks/              → Real-time validation (SessionStart → PostToolUse → Stop → SessionEnd)
hooks/lib/          → Shared libraries (pack-loader, config, rules-engine, metrics, static-analysis)
commands/           → Core user-invoked workflows (15 commands)
agents/             → Core agents (5) + pack symlinks
knowledge/          → Core methodology (DDD, Clean Architecture, patterns)
packs/              → Loadable language packs
  symfony/          → PHP/Symfony pack (validators, agents, knowledge, templates)
  react/            → React/TypeScript pack (validators, agents, knowledge, templates)
  ai-ml/            → AI/ML pack (agents, knowledge, commands)
ci/                 → CI pipeline integration (adapter pattern)
```

## Philosophy

> "Weeks of coding can save hours of planning."

### Core Principles

1. **Design before code** - Understand, challenge, then implement
2. **Test-first** - If you can't write the test, you don't understand the requirement
3. **Systematic debugging** - No random fixes, find root cause first
4. **YAGNI** - Build what's needed, not what might be needed
5. **Clean Architecture** - Dependencies point inward
6. **Make it work, make it right, make it fast** - In that order

### Pragmatism over Dogmatism

| Dogmatic | Pragmatic (our choice) |
|----------|------------------------|
| 100% test coverage | Critical paths covered (80%) |
| Pure DDD everywhere | DDD for complex domains only |
| Always abstract | Concrete first, abstract when needed |

## Security

This plugin prioritizes transparency and safety:

| Component | Behavior | Modifies Files? |
|-----------|----------|-----------------|
| Commands | Prompt templates | Only when instructed |
| Reviewer Agents | Code analysis (5 agents) | Never (read-only) |
| Craftsman Agents | Implementation (7 agents) | When instructed |
| Command Hooks | Validation scripts (6 scripts) | Never (read-only, except metrics DB) |
| Agent Hooks | Semantic analysis (4 agents, Haiku) | Never (read-only) |

**Hooks use exit codes** — Bias detection warns (exit 0). Code rule violations **block** (exit 2) to enforce quality standards. See [Hooks Reference](docs/reference/hooks.md).

See [SECURITY.md](./SECURITY.md) for full security documentation.

### Pre-Installation Verification

Verify the plugin before installing:

```bash
# Clone and inspect
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
cd ai-craftsman-superpowers

# Review hooks (the only executable code)
cat hooks/bias-detector.sh
cat hooks/post-write-check.sh
cat hooks/pre-write-check.sh
cat hooks/session-metrics.sh

# Verify no network calls
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing (hooks are 100% local)
```

## Known Limitations

### By Design

- **Hooks block on violations** — Code rule violations are blocking (exit 2); bias detection is warning-only (exit 0)
- **No auto-commit** — All git operations require explicit user action
- **Commands are opinionated** — Follows DDD/Clean Architecture strictly
- **Explicit invocation** — Commands are deliberately invoked, not auto-triggered

### Current Constraints

- **PHP/TypeScript focus** — Other languages have basic support only
- **RAG requires Ollama** — No cloud embedding providers supported
- **English/French only** — Bias detection patterns in EN/FR

### Not Supported

- ❌ Auto-fixing violations (by design, for safety)
- ❌ IDE plugins (Claude Code CLI only)

## Contributing

We welcome contributions! This is an open source project.

1. Fork the repository
2. Create a feature branch
3. Follow the craftsman methodology (use `/craftsman:design` first!)
4. Add tests for new features
5. Submit a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

### Ideas for Contributions

- New skills for other frameworks (Django, Rails, Go)
- Additional language support for hooks
- Improved examples and documentation
- Integration tests
- Translations

## Troubleshooting

### Commands not appearing in autocompletion

**Symptom:** `/cra<TAB>` doesn't suggest craftsman commands, but they work when typed fully.

**Cause:** Version mismatch between `plugin.json` and `marketplace.json` prevents cache updates.

**Fix:**
```bash
# Force update the plugin
claude plugin update craftsman@ai-craftsman-superpowers

# If still not working, clear cache and reinstall
rm -rf ~/.claude/plugins/cache/ai-craftsman-superpowers
claude plugin install craftsman@ai-craftsman-superpowers

# Restart Claude Code
exit
claude
```

### Skills not loading

```bash
# Clear plugin cache
rm -rf ~/.claude/plugins/cache

# Restart Claude Code
exit
claude

# Reinstall plugin
/plugin uninstall craftsman@BULDEE-ai-craftsman-superpowers
/plugin install craftsman@BULDEE-ai-craftsman-superpowers
```

### Check for errors

```bash
# Open plugin manager
/plugin

# Go to "Errors" tab
# Check for missing dependencies or path issues
```

### Hooks not running

Verify hooks are enabled in your scope:
1. `/plugin` → "Installed" tab
2. Select craftsman plugin
3. Check "Hooks enabled" status

## License

Apache License 2.0 - See [LICENSE](LICENSE)

## Support

- Discord: [Join our community](https://discord.gg/eBpgHAGu)
- Issues: [GitHub Issues](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
- Discussions: [GitHub Discussions](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)
- Documentation: [Claude Code Plugins](https://code.claude.com/docs/en/plugins)

## Sponsors

This project is proudly sponsored by:

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Building the future of AI-assisted development |
| **[Time Hacking Limited](https://thelabio.com)** | Maximizing developer productivity |

Interested in sponsoring? [Contact us](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)

## Acknowledgments

- Built following [Anthropic's official plugin guidelines](https://code.claude.com/docs/en/discover-plugins)
- Inspired by DDD, Clean Architecture, and TDD principles
- Thanks to all contributors and sponsors!

---

**Made with craftsmanship by [Alexandre Mallet](https://github.com/woprrr)**

*Sponsored by [BULDEE](https://buldee.com) & [Time Hacking Limited](https://thelabio.com)*
