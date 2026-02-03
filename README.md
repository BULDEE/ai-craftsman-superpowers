# AI Craftsman Superpowers

> Senior craftsman methodology for Claude Code. DDD, Clean Architecture, TDD.

Transform Claude Code into a disciplined software engineer with battle-tested methodologies.

## Requirements

- Claude Code v1.0.33 or later
- Run `claude --version` to check

## Installation

### Option 1: From GitHub (Recommended)

```bash
# Step 1: Add the marketplace
/plugin marketplace add woprrr/ai-craftsman-superpowers

# Step 2: Install the plugin
/plugin install craftsman@woprrr-ai-craftsman-superpowers
```

### Option 2: From Local Path

```bash
# If you cloned the repo locally
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```

### Option 3: Direct Git URL

```bash
/plugin marketplace add https://github.com/woprrr/ai-craftsman-superpowers.git
/plugin install craftsman@woprrr-ai-craftsman-superpowers
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
# Design a new entity
/craftsman:design

# Debug an issue systematically
/craftsman:debug

# Plan a feature implementation
/craftsman:plan

# Review code for architecture issues
/craftsman:challenge
```

## Skills

### Core Methodology

| Skill | Purpose | Auto-triggers |
|-------|---------|---------------|
| `/craftsman:design` | DDD design with challenge phases | "create", "design", "entity", "model" |
| `/craftsman:debug` | Systematic debugging (ReAct pattern) | "bug", "error", "broken", "not working" |
| `/craftsman:plan` | Structured planning & execution | "plan", "how to", "migrate", "roadmap" |
| `/craftsman:challenge` | Architecture review | "review", "check this", "feedback" |
| `/craftsman:verify` | Evidence-based verification | "verify", "is it done", "ready to commit" |
| `/craftsman:spec` | Specification-first (TDD/BDD) | "spec", "test first", "acceptance" |
| `/craftsman:refactor` | Systematic refactoring | "refactor", "clean up", "improve" |
| `/craftsman:test` | Pragmatic testing (Fowler/Martin) | "test strategy", "coverage" |
| `/craftsman:git` | Safe git workflow | "commit", "branch", "PR", "merge" |
| `/craftsman:parallel` | Parallel agent orchestration | "parallel", "multiple tasks" |

### Symfony/PHP

| Skill | Purpose |
|-------|---------|
| `/craftsman:entity` | Scaffold DDD entity with VO, events, tests |
| `/craftsman:usecase` | Scaffold use case with command/handler |

### React/TypeScript

| Skill | Purpose |
|-------|---------|
| `/craftsman:component` | Scaffold React component |
| `/craftsman:hook` | Scaffold TanStack Query hook |

### AI/ML Engineering

| Skill | Purpose |
|-------|---------|
| `/craftsman:rag` | Design RAG pipelines |
| `/craftsman:mlops` | Audit ML projects |
| `/craftsman:agent-design` | Design AI agents (3P pattern) |

## Agents

| Agent | Purpose |
|-------|---------|
| `architecture-reviewer` | Clean Architecture validation |
| `symfony-reviewer` | PHP/Symfony best practices |
| `react-reviewer` | React/TypeScript validation |
| `security-pentester` | OWASP security audit |
| `ai-reviewer` | AI/ML code review |

## Features

### Bias Protection (Active by Default)

Hooks automatically detect and warn about:

| Bias | Trigger | Protection |
|------|---------|------------|
| **Acceleration** | "vite", "quick", "just do it" | STOP - Design first |
| **Scope Creep** | "et aussi", "while we're at it" | STOP - Is this in scope? |
| **Over-Optimization** | "abstraire", "generalize" | STOP - YAGNI |

### Code Rule Enforcement

Post-write hooks validate:

**PHP:**
- `declare(strict_types=1)` required
- `final class` on all classes
- No public setters
- No `new DateTime()` direct usage

**TypeScript:**
- No `any` types
- Named exports only
- No non-null assertions (`!`)

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

## Project Structure

```
ai-craftsman-superpowers/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace catalog
├── plugins/
│   └── craftsman/            # Main plugin
│       ├── .claude-plugin/
│       │   └── plugin.json   # Plugin manifest
│       ├── skills/           # All skills (SKILL.md format)
│       │   ├── design/
│       │   ├── debug/
│       │   ├── plan/
│       │   └── ...
│       ├── agents/           # Specialized reviewers
│       ├── hooks/
│       │   ├── hooks.json
│       │   ├── bias-detector.sh
│       │   └── post-write-check.sh
│       └── knowledge/        # Patterns & principles
├── docs/                     # Documentation
├── core/                     # Core methodology (legacy)
├── symfony-pack/             # Symfony-specific extensions
├── react-pack/               # React-specific extensions
└── ai-pack/                  # AI/ML extensions
```

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

## Contributing

1. Fork the repository
2. Create a feature branch
3. Follow the craftsman methodology (use `/craftsman:design` first!)
4. Submit a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT License - See [LICENSE.md](LICENSE.md)

## Support

- Issues: [GitHub Issues](https://github.com/woprrr/ai-craftsman-superpowers/issues)
- Documentation: [Claude Code Plugins](https://code.claude.com/docs/en/plugins)

## Acknowledgments

Built following [Anthropic's official plugin guidelines](https://code.claude.com/docs/en/discover-plugins).
