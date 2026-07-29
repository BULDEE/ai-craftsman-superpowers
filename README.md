# AI Craftsman Superpowers

<div align="center">

🇬🇧 **English** | [🇫🇷 Français](README.fr.md)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet?logo=claude)](https://code.claude.com)
[![Hermes](https://img.shields.io/badge/Hermes-compatible-14b8a6?logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48cGF0aCBkPSJNMTIgNnYxNiIvPjxwYXRoIGQ9Ik0xMiA2LjJDMTAuMiA0LjYgNy42IDUgNyA3YzIgLjYgNC0uMiA1LS44IDEgLjYgMyAxLjQgNSAuOC0uNi0yLTMuMi0yLjQtNS0uOHoiIGZpbGw9IiNmZmYiIHN0cm9rZT0ibm9uZSIvPjxwYXRoIGQ9Ik04LjUgOS41YzIuMiAxLjYgNC44IDEuNiA3IDAiLz48cGF0aCBkPSJNMTUuNSAxM2MtMi4yIDEuNi00LjggMS42LTcgMCIvPjxwYXRoIGQ9Ik04LjUgMTYuNWMyLjIgMS42IDQuOCAxLjYgNyAwIi8%2BPGNpcmNsZSBjeD0iMTIiIGN5PSIzLjIiIHI9IjEuNCIgZmlsbD0iI2ZmZiIgc3Ryb2tlPSJub25lIi8%2BPC9nPjwvc3ZnPgo%3D)](adapters/hermes/README.md)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![Skills](https://img.shields.io/badge/Skills-21-orange)](COMMANDS-QUICK-REF.md)
[![Agents](https://img.shields.io/badge/Agents-12-red)](#specialized-agents)
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

## A prompt asks. This enforces.

You can write "always use final classes" in your `CLAUDE.md`. Claude will
follow it, until the context fills up, or the task gets long, or the tenth file
of a refactor. Instructions decay. That is not a discipline problem, it is an
architecture problem: nothing in the loop is checking.

Craftsman puts the check in the loop. The same rules run as hooks on every
Write, as a gate in your CI, and as the criteria a reviewer agent reads. A
violation is not a gentle reminder in the next paragraph: layer violations and
missing `strict_types` are refused before the write lands, everything else is
handed straight back to Claude as a finding it has to answer for, and the same
rule fails your pipeline if it reaches a pull request.

Three things follow from that, and they are what make this plugin different
from a well-written prompt:

| | |
|---|---|
| **It blocks** | One rules engine, enforced identically in hooks and CI. No drift between what your editor allows and what your pipeline rejects. |
| **It learns** | Every violation you fix is recorded. A pattern that recurs across files becomes a candidate instinct you approve, and Claude stops making that mistake instead of being reminded about it. |
| **It proves** | "Done" requires evidence. A task cannot be marked complete without a verification record, and a failing test run revokes one that already exists. |

And it does this on the cheapest model that can do each job: mechanical work on
Haiku, pattern application on Sonnet, architectural judgment on Opus. You do
not pick, and you do not pay Opus rates to format a commit message.

## Why Craftsman? - Core Differentiators

What makes this plugin genuinely unique in the Claude Code ecosystem:

1. **Correction Learning System (closed loop)** - records every violation fix, injects correction trends at session start, and promotes recurring fixes (3+ across 3+ files) into candidate instincts you approve in `/craftsman:metrics`. Approved instincts become project skills with provenance - Claude stops making the mistake instead of being reminded about it.
2. **Rules Engine with 3-Level Inheritance** - Global → Project → Directory overrides. Short form (`PHP001: warn`) or long form (custom regex rules). Legacy code coexists with strict new code via directory-level relaxation.
3. **Cognitive Bias Detector** - real-time detection of acceleration bias, scope creep, and over-optimization in your prompts, bilingual FR/EN, context-aware to reduce false positives.
4. **Real-Time Quality Gate** - progressive validation on every Write/Edit: regex (<50ms, always on) → LSP semantics (live, when your language server is installed) → static analysis and architecture (PHPStan/ESLint/deptrac, opt-in per machine because running a project's analysers runs its code, see [SECURITY.md](SECURITY.md)). Degrades gracefully with zero tools installed.
5. **Multi-Provider CI Pipeline** - CI sources the same pack validators and rules engine as the hooks, so a rule means the same thing locally and in the pipeline. GitHub Actions, GitLab CI and Bitbucket Pipelines get native annotations; Jenkins runs through the generic adapter.
6. **Metrics & Trend Analysis** - SQLite-backed tracking of violations, corrections, and sessions, with 7-day/30-day trend views to identify your most-violated rules.
7. **Structural Ratchet** - a committed baseline records each file's structural high-water mark (complexity, size, longest function, import fan-out, suppression count). A file you touch may improve or stay equal, never regress: the mark tightens automatically on a green pass and only loosens through a documented, counted suppression. Enforced identically in hooks and CI; untouched legacy is never punished for debt it already had.
8. **Adversarial Design Panel** - three contradictors (YAGNI, invariants and boundaries, feasibility) attack a design during `/craftsman:design`, before any code exists. Every objection lands in a retained or dismissed table: silence is not an option. Contradicting a design costs far less than contradicting the code built on it.
9. **Security and Situational Onboarding** - SEC001-003 (hardcoded secrets, dynamic eval, SQL by concatenation) verified in hooks and CI with their doctrine routed on block; setup observes the repository and asks at most four plain-language questions, and guided mode makes every block explain itself.
10. **Per-Task Model Tiering** - each skill declares the cheapest model that can do its job and how hard it should think, enforced for the turn it runs in. Formatting a commit runs on Haiku at low effort; an architecture review runs on Opus at high. Tiers are aliases, so they follow model releases, and you can remap a whole tier with one environment variable. See [Model Tiering Explained](docs/guides/model-tiering-explained.md).

> No other Claude Code plugin combines all of these: learning from past mistakes, enterprise rule customization, cognitive protection, real-time validation, zero CI drift, measurable quality trends, and per-task model economics.


## Opening an Untrusted Repository

The plugin's hooks run automatically, so a cloned repository is untrusted input: its file names, contents, config files, and any tool it vendors. Two capabilities that would execute repository-supplied code are therefore off unless **you** allow them in your own `~/.claude/.craft-config.yml`, and a project file can never grant them:

| Capability | Why it is gated |
|------------|-----------------|
| `trust_project_tools: true` | Level 2 runs `vendor/bin/phpstan` and `node_modules/.bin/eslint` and the configs they auto-discover. ESLint's flat config is executable JavaScript by design; PHPStan's `bootstrapFiles` requires arbitrary PHP. |
| `packs.external[].path` | External pack validators are sourced as shell code. |

Everything else keeps working on an untrusted repository: the rules engine, layer, persistence and security rules, the structural ratchet, metrics, and the CI gate are the plugin's own code. `tests/core/test-hostile-repo.sh` reproduces each attack this model covers and asserts it fails. Full detail: [SECURITY.md](SECURITY.md).

## Requirements

- Claude Code v2.1.218 or later (`claude --version` to check). Older versions: install the frozen 3.9.x line.
- `python3` 3.9 or later. That is the floor because it is what `/usr/bin/python3` is on a Mac without homebrew; CI imports every hook library under 3.9 so the floor cannot silently rise.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils is not required: the plugin runs on a stock macOS.

## Installation

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@ai-craftsman-superpowers

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

The differentiators above work with **zero API cost** beyond your normal Claude Code usage - regex validation, the rules engine, bias detection, CI export, and metrics are all local.

One optional layer adds deeper semantic analysis via Haiku agent hooks (DDD layer violations, Sentry error context, architecture review): ~$0.15-0.30 per session (50 Write/Edit operations).

**Opt-out:** set `agent_hooks: false` in the plugin config. Everything else keeps working.

## Commands

All commands are explicitly invoked with `/craftsman:command-name`. Full reference: [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md). In v4 these become skills with forked execution and live context injection, with unchanged invocations - see [ADR-0017](docs/adr/0017-skills-over-commands.md).

| Category | Commands |
|----------|----------|
| Core methodology | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| AI/ML engineering | `rag`, `mlops`, `agent-design` |
| Utilities | `metrics`, `setup`, `team`, `healthcheck` |
| CI/CD | `ci` |

Scaffolders offer a template variant before generating code (e.g. `bounded-context` vs `event-sourced` for entities) - see [Template Variants](skills/scaffold/SKILL.md#template-variants-v210).

## Specialized Agents

Core agents (more load automatically with packs): `team-lead` (orchestrator), `architect` (DDD/Clean Architecture, no Write/Edit), `doc-writer` (ADRs, README, CHANGELOG), `security-pentester`, `legacy-surgeon`, `ui-ux-director` - plus pack-specific reviewers/craftsmen for Symfony, React, and AI/ML. Full roster and model tiering: [Agents Reference](docs/reference/agents.md).

## Rules Engine

Override any rule per-project or per-directory with 3-level config inheritance:

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Short form: `PHP001: warn` / `TS001: ignore`. Long form: custom rules with regex, severity, languages. Suppress a single occurrence inline with `// craftsman-ignore: RULE_ID`.

## CI/CD Integration

CI sources the same pack validators and the same rules engine as the hooks, so
a rule cannot mean one thing on your machine and another in the pipeline.

| Provider | Template | Adapter |
|----------|----------|---------|
| GitHub Actions | `craftsman-quality-gate.yml` | Native: inline annotations and a PR comment |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Native: code-quality report and an MR note |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Native: build report |
| Jenkins | `Jenkinsfile.craftsman` | Generic: plain log output and a markdown file, no native annotations |

Use `/craftsman:ci export` or `craftsman-ci.sh init --provider` from the CLI.

Also enforced by hooks: the [Circuit Breaker](docs/reference/hooks.md#circuit-breaker-v210) protects Sentry integration during outages, and the [Iron Law Pattern](docs/reference/hooks.md#iron-law-pattern-v210) blocks impulsive architecture changes made without a prior `/craftsman:design` pass. Full hook behavior, exit codes, and rule IDs: [Hooks Reference](docs/reference/hooks.md).

## Knowledge as an OKF Bundle

The plugin's methodology knowledge (Clean Architecture, DDD, persistence, legacy, refactoring) ships as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle: curated Markdown with YAML frontmatter, versioned in git, reviewed in PRs. A deterministic lookup routes rules to the concept that explains them (a LAYER004 block points at the repository-pattern doc) with zero embeddings, zero index, zero external services. Your own memory tools (Obsidian, claude-mem, any OKF consumer) can read the bundle directly - it is plain Markdown on disk.

## CLAUDE.md Configuration

Priority order: explicit user instruction → project `CLAUDE.md` → plugin (skills, hooks, knowledge) → global `~/.claude/CLAUDE.md`.

Put DISC profile/communication style/personal biases in your **global** CLAUDE.md, architecture/key entities/project rules in your **project** CLAUDE.md, and let the **plugin** handle code enforcement and design patterns. Full guidance: [CLAUDE.md Best Practices Guide](docs/guides/claude-md-best-practices.md).

## What's New in v4.0.0 - The Self-Learning Craftsman System

v4 is a **clean break** targeting Claude Code >= 2.1.218, with no backward compatibility (the 3.9.x line stays available and frozen). Headlines:

- **Closed learning loop**: recurring corrections become candidate instincts you review in `/craftsman:metrics`; approved ones are codified as project skills. Detection stays automatic, codification stays human-gated.
- **Native-first architecture**: workflows become forked skills with live context injection, and verification uses `asyncRewake` plus a `TaskCompleted` gate. Semantic verification runs on Haiku in headless subprocesses behind gated command hooks rather than native `agent`/`prompt` hook types, which offer no per-plugin option gating and would take away your ability to turn verification off ([ADR-0018](docs/adr/0018-native-prompt-agent-hooks.md)).
- **Semantic Level 1.5**: LSP-backed validation between the regex gate and static analysis, activating only on language servers you already have installed - the plugin orchestrates your stack's tooling, never substitutes for it.
- **Context discipline**: every injection capped by configurable budgets, every hook individually disableable.

Full plan and phases: [docs/v4-roadmap.md](docs/v4-roadmap.md). Decisions: ADRs [0016](docs/adr/0016-v4-clean-break-native-first.md) through [0023](docs/adr/0023-deterministic-verification-loop.md). Breaking changes: [MIGRATION.md](MIGRATION.md).

## Architecture Decisions

28 ADRs cover the reasoning behind every major design choice - see [`/docs/adr`](docs/adr/). Start with [ADR-0016: v4 Clean Break](docs/adr/0016-v4-clean-break-native-first.md) and [ADR-0005: Knowledge-First Architecture](docs/adr/0005-knowledge-first-architecture.md) if you're evaluating the plugin's design.

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

Command hooks write only to the local metrics DB and session state. Agent hooks (Haiku) never modify files. Bias detection only warns (exit 0). Layer and `strict_types` violations are refused before the write; the remaining rules report the violation to Claude after it and fail CI on a pull request.

Agents declare their own tool grant in `tools:`. Most craftsmen hold `Write`/`Edit`/`Bash` because their job is to change code; `architect` and `team-lead` hold no `Write` or `Edit`. Read each agent's frontmatter for its actual grant rather than assuming a role name implies read-only.

**No telemetry, no analytics, no phone-home.** With `agent_hooks: false` and no Sentry config, zero network activity. Edited file content only reaches the Anthropic API when `agent_hooks: true` (default); Sentry is only queried if configured; metrics never leave your machine. Full breakdown: [SECURITY.md](SECURITY.md#data--network-transparency).

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

**Current constraints:** PHP/TypeScript get full rule coverage, other languages basic support only; bias detection patterns are EN/FR only; metrics are per-machine, not shared across a team; auto-fixing violations and IDE plugins are not supported by design.

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
