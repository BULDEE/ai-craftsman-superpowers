# AI Craftsman Superpowers

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-v1.0.33+-green.svg)](https://code.claude.com)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> Senior craftsman methodology for Claude Code. DDD, Clean Architecture, TDD.

Transform Claude Code into a disciplined software engineer with battle-tested methodologies.

## Requirements

- Claude Code v1.0.33 or later
- Run `claude --version` to check

## Installation

### From GitHub (Recommended)

```bash
# Step 1: Add the marketplace
/plugin marketplace add woprrr/ai-craftsman-superpowers

# Step 2: Install the plugin
/plugin install craftsman@woprrr-ai-craftsman-superpowers

# Step 3: Restart Claude Code
exit
claude
```

### From Local Path

```bash
# If you cloned the repo locally
git clone https://github.com/woprrr/ai-craftsman-superpowers.git
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

## Skills

### Core Methodology

| Skill | Model | Purpose | Auto-triggers |
|-------|-------|---------|---------------|
| `/craftsman:design` | Sonnet | DDD design with challenge phases | "create", "design", "entity" |
| `/craftsman:debug` | Sonnet | Systematic debugging (ReAct) | "bug", "error", "broken" |
| `/craftsman:plan` | Opus | Structured planning & execution | "plan", "migrate", "roadmap" |
| `/craftsman:challenge` | Opus | Architecture review | "review", "feedback" |
| `/craftsman:verify` | Haiku | Evidence-based verification | "verify", "is it done" |
| `/craftsman:spec` | Sonnet | Specification-first (TDD/BDD) | "spec", "test first" |
| `/craftsman:refactor` | Sonnet | Systematic refactoring | "refactor", "clean up" |
| `/craftsman:test` | Sonnet | Pragmatic testing (Fowler/Martin) | "test strategy" |
| `/craftsman:git` | Haiku | Safe git workflow | "commit", "branch", "PR" |
| `/craftsman:parallel` | Opus | Parallel agent orchestration | "parallel tasks" |

### Model Tiering Strategy

- **Haiku**: Fast, simple tasks (verification, git commands)
- **Sonnet**: Balanced tasks (design, testing, refactoring)
- **Opus**: Complex, critical tasks (architecture review, planning)

See [ADR-001: Model Tiering](docs/adr/001-model-tiering.md) for rationale.

### Symfony/PHP

| Skill | Model | Purpose |
|-------|-------|---------|
| `/craftsman:entity` | Sonnet | Scaffold DDD entity with VO, events, tests |
| `/craftsman:usecase` | Sonnet | Scaffold use case with command/handler |

### React/TypeScript

| Skill | Model | Purpose |
|-------|-------|---------|
| `/craftsman:component` | Sonnet | Scaffold React component |
| `/craftsman:hook` | Sonnet | Scaffold TanStack Query hook |

### AI/ML Engineering

| Skill | Model | Purpose |
|-------|-------|---------|
| `/craftsman:rag` | Opus | Design RAG pipelines |
| `/craftsman:mlops` | Opus | Audit ML projects |
| `/craftsman:agent-design` | Opus | Design AI agents (3P pattern) |

## Features

### Bias Protection (Active by Default)

Hooks automatically detect and warn about cognitive biases:

| Bias | Trigger | Protection |
|------|---------|------------|
| **Acceleration** | "vite", "quick", "just do it" | STOP - Design first |
| **Scope Creep** | "et aussi", "while we're at it" | STOP - Is this in scope? |
| **Over-Optimization** | "abstraire", "generalize" | STOP - YAGNI |

### Code Rule Enforcement

Post-write hooks validate your code automatically:

**PHP:**
- `declare(strict_types=1)` required
- `final class` on all classes
- No public setters
- No `new DateTime()` direct usage

**TypeScript:**
- No `any` types
- Named exports only
- No non-null assertions (`!`)

## Advanced: Knowledge Base RAG

The plugin includes a knowledge base that can be queried via RAG (Retrieval-Augmented Generation).

### Setup (Ollama Recommended)

```bash
# 1. Install Ollama
brew install ollama && ollama pull nomic-embed-text

# 2. Index knowledge base
cd ai-pack/mcp/knowledge-rag
npm install && npm run build
npm run index:ollama
```

See [Local RAG Setup Guide](docs/guides/local-rag-ollama.md) for detailed instructions.

> **Why Ollama?** 100% local, free, private. OpenAI API is supported but not recommended. See [ADR-0002](docs/adr/0002-ollama-over-openai.md).

## Architecture Decisions

See [`/docs/adr`](docs/adr/) for Architecture Decision Records:

- [ADR-001: Model Tiering Strategy](docs/adr/001-model-tiering.md)
- [ADR-002: Context Fork Strategy](docs/adr/002-context-fork-strategy.md)
- [ADR-003: Progressive Disclosure](docs/adr/003-progressive-disclosure.md)
- [ADR-0002: Ollama over OpenAI](docs/adr/0002-ollama-over-openai.md)

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
├── plugins/craftsman/           # Main plugin
│   ├── .claude-plugin/          # Plugin manifest
│   ├── skills/                  # All skills (SKILL.md)
│   ├── agents/                  # Specialized reviewers
│   ├── hooks/                   # Automated validation
│   └── knowledge/               # Patterns & principles
├── examples/                    # Usage examples
├── tests/                       # Test suite
├── docs/
│   └── adr/                     # Architecture decisions
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
/plugin uninstall craftsman@woprrr-ai-craftsman-superpowers
/plugin install craftsman@woprrr-ai-craftsman-superpowers
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

- Issues: [GitHub Issues](https://github.com/woprrr/ai-craftsman-superpowers/issues)
- Discussions: [GitHub Discussions](https://github.com/woprrr/ai-craftsman-superpowers/discussions)
- Documentation: [Claude Code Plugins](https://code.claude.com/docs/en/plugins)

## Sponsors

This project is proudly sponsored by:

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Building the future of AI-assisted development |
| **[Time Hacking Limited](https://thelabio.com)** | Maximizing developer productivity |

Interested in sponsoring? [Contact us](https://github.com/woprrr/ai-craftsman-superpowers/discussions)

## Acknowledgments

- Built following [Anthropic's official plugin guidelines](https://code.claude.com/docs/en/discover-plugins)
- Inspired by DDD, Clean Architecture, and TDD principles
- Thanks to all contributors and sponsors!

---

**Made with craftsmanship by [Alexandre Mallet](https://github.com/woprrr)**

*Sponsored by [BULDEE](https://buldee.com) & [Time Hacking Limited](https://thelabio.com)*
