# AI Craftsman Superpowers

<div align="center">

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A51.0.33-blueviolet)](https://code.claude.com)
[![Version](https://img.shields.io/badge/Version-1.0.0-blue)](CHANGELOG.md)
[![Commands](https://img.shields.io/badge/Commands-20-orange)]()
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

> **Why source-verify?** AI tools evolve rapidly. This command ensures claims about capabilities are verified against official documentation before being stated as facts. See [ADR-004](docs/adr/004-official-documentation-verification.md).

## Features

### Bias Protection (Active by Default)

Hooks automatically detect and warn about cognitive biases:

| Bias | Trigger | Protection |
|------|---------|------------|
| **Acceleration** | "vite", "quick", "just do it" | STOP - Design first |
| **Scope Creep** | "et aussi", "while we're at it" | STOP - Is this in scope? |
| **Over-Optimization** | "abstraire", "generalize" | STOP - YAGNI |

### Code Rule Enforcement

Post-write/edit hooks validate your code automatically (triggers on both `Write` and `Edit` tools):

**PHP:**
- `declare(strict_types=1)` required
- `final class` on all classes
- No public setters
- No `new DateTime()` direct usage

**TypeScript:**
- No `any` types
- Named exports only
- No non-null assertions (`!`)

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

- [ADR-001: Model Tiering Strategy](docs/adr/001-model-tiering.md)
- [ADR-002: Context Fork Strategy](docs/adr/002-context-fork-strategy.md)
- [ADR-003: Progressive Disclosure](docs/adr/003-progressive-disclosure.md)
- [ADR-0002: Ollama over OpenAI](docs/adr/0002-ollama-over-openai.md)
- [ADR-0007: Commands over Skills](docs/adr/0007-commands-over-skills.md)

## Examples

See [`/examples`](examples/) for detailed usage examples:

- [Design: Create Entity](examples/design/01-create-entity.md)
- [Debug: Memory Leak](examples/debug/01-memory-leak.md)
- [Challenge: Code Review](examples/challenge/01-code-review.md)
- [Plan: Migration](examples/plan/01-migration-microservices.md)
- [Git: Safe Commit](examples/git/01-safe-commit.md)
- [Test: Testing Strategy](examples/test/01-testing-strategy.md)

## Project Structure

```
ai-craftsman-superpowers/
├── .claude-plugin/              # Plugin manifest
│   └── plugin.json
├── commands/                    # User-invocable commands (20 *.md files)
├── agents/                      # Specialized reviewers (5)
├── hooks/                       # Automated validation
│   ├── hooks.json
│   ├── bias-detector.sh
│   └── post-write-check.sh
├── knowledge/                   # Patterns & principles
├── examples/                    # Usage examples
├── tests/                       # Test suite
├── docs/
│   └── adr/                     # Architecture decisions
├── SECURITY.md                  # Security documentation
├── CHANGELOG.md                 # Version history
├── CONTRIBUTING.md
└── LICENSE                      # Apache 2.0
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
| Skills | Prompt templates | Only when instructed |
| Agents | Code reviewers | Never |
| Hooks | Validation scripts | Never (read-only) |

**All hooks exit 0** — They warn but never block your workflow.

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

# Verify no network calls
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing
```

## Known Limitations

### By Design

- **Hooks are warnings only** — They never block operations, only inform
- **No auto-commit** — All git operations require explicit user action
- **Commands are opinionated** — Follows DDD/Clean Architecture strictly
- **Explicit invocation** — Commands are deliberately invoked, not auto-triggered

### Current Constraints

- **PHP/TypeScript focus** — Other languages have basic support only
- **RAG requires Ollama** — No cloud embedding providers supported
- **English/French only** — Bias detection patterns in EN/FR

### Not Supported

- ❌ Auto-fixing violations (by design, for safety)
- ❌ CI/CD integration (use native tools instead)
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
