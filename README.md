# AI Craftsman Superpowers

<div align="center">

🇬🇧 **English** | [🇫🇷 Français](README.fr.md)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A51.0.33-blueviolet)](https://code.claude.com)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![Commands](https://img.shields.io/badge/Commands-18%2B-orange)](COMMANDS-QUICK-REF.md)
[![Agents](https://img.shields.io/badge/Agents-6%2B-red)](#specialized-agents)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Transform Claude into a disciplined Senior Software Craftsman**

[Quick Start](#quick-start) •
[Commands](#commands) •
[Security](#security) •
[Contributing](#contributing)

</div>

> [!WARNING]
> Only install this plugin from the official sources listed below. Do not trust forks, mirrors, or "improved" copies distributed elsewhere - see [Pre-Installation Verification](#pre-installation-verification).

---

DDD, Clean Architecture, and TDD methodology enforced through hooks, commands, and a rules engine - not just suggested in a prompt, but actually blocked when violated.

## Why Craftsman? - 6 Core Differentiators

What makes this plugin genuinely unique in the Claude Code ecosystem:

1. **Correction Learning System** - records every violation fix you make and injects correction trends at next session start. SQLite-backed feedback loop that progressively teaches Claude the exact patterns your codebase rejects. Cross-file detection suggests project-wide fixes when 3+ files share the same violation.
2. **Rules Engine with 3-Level Inheritance** - Global → Project → Directory overrides. Short form (`PHP001: warn`) or long form (custom regex rules). Legacy code coexists with strict new code via directory-level relaxation.
3. **Cognitive Bias Detector** - real-time detection of acceleration bias, scope creep, and over-optimization in your prompts, bilingual FR/EN, context-aware to reduce false positives.
4. **Real-Time Quality Gate** - 3-level progressive validation on every Write/Edit: regex (<50ms, always on) → static analysis (<2s, PHPStan/ESLint) → architecture (<2s, deptrac/dependency-cruiser). Degrades gracefully with zero tools installed.
5. **Multi-Provider CI Pipeline** - the same rules engine runs in hooks (real-time) and CI (pipeline) with zero drift, across GitHub Actions, GitLab CI, Bitbucket Pipelines, and Jenkins.
6. **Metrics & Trend Analysis** - SQLite-backed tracking of violations, corrections, and sessions, with 7-day/30-day trend views to identify your most-violated rules.

> No other Claude Code plugin combines all 6: learning from past mistakes, enterprise rule customization, cognitive protection, real-time validation, zero CI drift, and measurable quality trends.

## Requirements

- Claude Code v1.0.33 or later (`claude --version` to check)

## Installation

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@BULDEE-ai-craftsman-superpowers

# 3. Restart Claude Code
exit
claude
```

<details>
<summary>Install from a local clone instead</summary>

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /path/to/ai-craftsman-superpowers
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```
</details>

<details>
<summary>Verify the install</summary>

```bash
/plugin
# "Installed" tab → craftsman plugin should appear
# "Errors" tab → check here if skills don't appear
```
</details>

## Quick Start

```bash
# Design a new entity (follows DDD phases)
/craftsman:design
I need to create a User entity for an e-commerce platform.

# Debug an issue systematically (ReAct pattern)
/craftsman:debug
I have a memory leak in my Node.js app.

# Review code for architecture issues
/craftsman:challenge
[paste your code]

# Run the full development workflow (design → spec → plan → implement → test → verify → commit)
/craftsman:workflow
I need to add a forgot password feature.

# Quick setup (zero questions, smart defaults)
/craftsman:setup --quick
```

New to the methodology? Start with the [Beginner Guide](docs/guides/beginner.md) - it walks through DDD concepts and core commands with worked examples. See [`/examples`](examples/) for detailed usage with expected outputs, and [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md) for the full command list.

## API Cost Model (optional)

The 6 differentiators above work with **zero API cost** beyond your normal Claude Code usage - regex validation, the rules engine, bias detection, CI export, and metrics are all local.

One optional layer adds deeper semantic analysis via Haiku agent hooks (DDD layer violations, Sentry error context, architecture review): ~$0.15-0.30 per session (50 Write/Edit operations).

**Opt-out:** set `agent_hooks: false` in the plugin config. Everything else keeps working.

## Commands

All commands are explicitly invoked with `/craftsman:command-name` (see [ADR-0007](docs/adr/0007-commands-over-skills.md) for why). Full reference: [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Category | Commands |
|----------|----------|
| Core methodology | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| AI/ML engineering | `rag`, `mlops`, `agent-design` |
| Utilities | `metrics`, `setup`, `team`, `healthcheck`, `knowledge` |
| CI/CD | `ci` |

Scaffolders offer a template variant before generating code (e.g. `bounded-context` vs `event-sourced` for entities) - see [Template Variants](commands/scaffold.md#template-variants-v210).

## Specialized Agents

Core agents (more load automatically with packs): `team-lead` (orchestrator), `architect` (DDD/Clean Architecture, read-only), `doc-writer` (ADRs, README, CHANGELOG), `security-pentester`, `legacy-surgeon`, `ui-ux-director` - plus pack-specific reviewers/craftsmen for Symfony, React, and AI/ML. Full roster and model tiering: [Agents Reference](docs/reference/agents.md).

## Rules Engine

Override any rule per-project or per-directory with 3-level config inheritance:

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Short form: `PHP001: warn` / `TS001: ignore`. Long form: custom rules with regex, severity, languages. Suppress a single occurrence inline with `// craftsman-ignore: RULE_ID`.

## CI/CD Integration

Same rules engine, zero drift between local hooks and CI, 4 providers:

| Provider | Template |
|----------|----------|
| GitHub Actions | `craftsman-quality-gate.yml` |
| GitLab CI | `.gitlab-ci.craftsman.yml` |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` |
| Jenkins | `Jenkinsfile.craftsman` |

Use `/craftsman:ci export` or `craftsman-ci.sh init --provider` from the CLI.

Also enforced by hooks: the [Circuit Breaker](docs/reference/hooks.md#circuit-breaker-v210) protects Sentry integration during outages, and the [Iron Law Pattern](docs/reference/hooks.md#iron-law-pattern-v210) blocks impulsive architecture changes made without a prior `/craftsman:design` pass. Full hook behavior, exit codes, and rule IDs: [Hooks Reference](docs/reference/hooks.md).

## Advanced: Knowledge Base RAG (optional)

An **optional** MCP server adds RAG over your local documents. Fully inert unless the `ai-ml` pack is enabled - zero errors for users who don't need it.

```bash
brew install ollama && ollama pull nomic-embed-text
ollama serve

mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge
cp ~/your-docs/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/
```

See [Local RAG Setup Guide](docs/guides/local-rag-ollama.md) and [MCP Reference](docs/reference/mcp-servers.md) for the full setup, and [ADR-0002](docs/adr/0002-ollama-over-openai.md) for why Ollama over a cloud provider.

## CLAUDE.md Configuration

Priority order: explicit user instruction → project `CLAUDE.md` → plugin (skills, hooks, knowledge) → global `~/.claude/CLAUDE.md`.

Put DISC profile/communication style/personal biases in your **global** CLAUDE.md, architecture/key entities/project rules in your **project** CLAUDE.md, and let the **plugin** handle code enforcement and design patterns. Full guidance: [CLAUDE.md Best Practices Guide](docs/guides/claude-md-best-practices.md).

## Architecture Decisions

16 ADRs cover the reasoning behind every major design choice - see [`/docs/adr`](docs/adr/). Start with [ADR-0007: Commands over Skills](docs/adr/0007-commands-over-skills.md) and [ADR-0005: Knowledge-First Architecture](docs/adr/0005-knowledge-first-architecture.md) if you're evaluating the plugin's design.

## Using with Superpowers Plugin

Craftsman and [Superpowers](https://github.com/anthropics/claude-code-plugins/tree/main/superpowers) are complementary and load simultaneously with no conflicts. Superpowers handles workflow orchestration (brainstorming, planning, TDD, subagent-driven development); Craftsman handles domain-specific quality enforcement (DDD rules, architectural validation, correction learning).

```
1. /superpowers:brainstorming     → Design the solution collaboratively
2. /superpowers:writing-plans     → Create implementation plan
3. /superpowers:subagent-driven-development → Execute with fresh subagents
   ├── Craftsman hooks fire on every Write/Edit (real-time quality gate)
   ├── /craftsman:design           → DDD modeling when domain entities appear
   └── /craftsman:challenge        → Architecture review at milestones
4. /craftsman:verify              → Evidence-based verification before commit
5. /superpowers:finishing-a-development-branch → PR and merge
```

## Philosophy

> "Weeks of coding can save hours of planning."

Design before code. Test-first. Systematic debugging over random fixes. YAGNI. Clean Architecture - dependencies point inward. Make it work, make it right, make it fast, in that order.

Pragmatism over dogmatism: 80% coverage on critical paths beats 100% everywhere; DDD for complex domains, not every domain; concrete first, abstract when actually needed.

## Security

Command hooks and reviewer agents are read-only except for the local metrics DB and session state. Agent hooks (Haiku) never modify files. Violations block (exit 2); bias detection only warns (exit 0).

**No telemetry, no analytics, no phone-home.** With `agent_hooks: false` and no Sentry config, zero network activity. Edited file content only reaches the Anthropic API when `agent_hooks: true` (default); Sentry is only queried if configured; metrics and RAG embeddings never leave your machine. Full breakdown: [SECURITY.md](SECURITY.md#data--network-transparency).

### Pre-Installation Verification

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
cd ai-craftsman-superpowers

# Review hooks - the only executable code
cat hooks/bias-detector.sh hooks/post-write-check.sh hooks/pre-write-check.sh hooks/session-metrics.sh

# Verify no network calls
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing (hooks are 100% local)
```

## Known Limitations

**By design:** code rule violations block, bias detection only warns; no auto-commit; commands are explicitly invoked, never auto-triggered; methodology is opinionated (DDD/Clean Architecture).

**Current constraints:** PHP/TypeScript get full rule coverage, other languages basic support only; RAG requires Ollama (no cloud embedding providers); bias detection patterns are EN/FR only; auto-fixing violations and IDE plugins are not supported by design.

More detail in the [FAQ](FAQ.md).

## Contributing

Contributions welcome - this is an open source project.

1. Fork the repository
2. Create a feature branch
3. Follow the craftsman methodology (`/craftsman:design` first!)
4. Add tests for new features
5. Submit a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines. Looking for ideas? New framework skills (Django, Rails, Go), additional hook language support, examples, integration tests, and translations are all welcome.

## Troubleshooting

Moved to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## License

Apache License 2.0 - see [LICENSE](LICENSE)

## Support

- Discord: [Join our community](https://discord.gg/eBpgHAGu)
- Issues: [GitHub Issues](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
- Discussions: [GitHub Discussions](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)
- Documentation: [Claude Code Plugins](https://code.claude.com/docs/en/plugins)

## Sponsors

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Building the future of AI-assisted development |
| **[Time Hacking Limited](https://thelabio.com)** | Maximizing developer productivity |

Interested in sponsoring? [Contact us](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)

## Acknowledgments

Built following [Anthropic's official plugin guidelines](https://code.claude.com/docs/en/discover-plugins), inspired by DDD, Clean Architecture, and TDD principles. Thanks to all contributors and sponsors!

---

**Made with craftsmanship by [Alexandre Mallet](https://github.com/woprrr)**

*Sponsored by [BULDEE](https://buldee.com) & [Time Hacking Limited](https://thelabio.com)*
