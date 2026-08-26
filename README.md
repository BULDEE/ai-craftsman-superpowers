<div align="center">

<a href="https://ai-craftsman.dev">
  <img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/github-banner.png" alt="AI Craftsman Superpowers - a prompt asks, this enforces" width="100%">
</a>

🇬🇧 **English** | [🇫🇷 Français](README.fr.md)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet?logo=claude)](https://code.claude.com)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)

**Claude writes the code. Your architecture rules decide what lands.**

For teams running Claude Code on a codebase where a layer violation costs more
than the feature does.

[Website](https://ai-craftsman.dev) •
[Install](#install) •
[Commands](#commands) •
[Docs](https://ai-craftsman.dev/docs) •
[Contributing](#contributing)

</div>

---

## A prompt asks. This enforces.

You can write "always use final classes" in your `CLAUDE.md`. Claude will
follow it, until the context fills up, or the task gets long, or the tenth file
of a refactor. Instructions decay. That is not a discipline problem, it is an
architecture problem: nothing in the loop is checking.

Craftsman puts the check in the loop. The same rules run as hooks on every
Write, as a gate in your CI, and as the criteria a reviewer agent reads. Layer
violations and missing `strict_types` are refused before the write lands,
everything else is handed straight back to Claude as a finding it has to answer
for, and the same rule fails your pipeline if it reaches a pull request.

## See it refuse

Claude tries to write an entity that imports from the infrastructure layer. The
file never reaches your disk:

<img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/craftsman-demo.gif" alt="The pre-write hook refusing a domain entity that imports infrastructure, then passing the corrected file" width="100%">

<details>
<summary>The same run as text</summary>

```console
$ ./check.sh User.before.php.txt /srv/app/src/Domain/User/User.php

🚫 BLOCKED by AI Craftsman - 2 violation(s) detected before write:
  ✗ LAYER001: Domain imports Infrastructure - DDD layer violation
  ✗ PHP001: Missing declare(strict_types=1) in class file
Fix these before writing. Use // craftsman-ignore: <RULE_ID> to suppress.
exit=2
```

Not a mockup: the recording pipes two fixtures through `hooks/pre-write-check.sh`
and shows whatever it returns. Exit code 2 is the refusal.

</details>

Claude reads the same two lines you do, corrects the import, and writes again.
The correction is recorded; if that same rule keeps coming back across files, it
is offered to you as a candidate instinct in `/craftsman:metrics`. And if the
violation ever reaches a pull request instead, the identical rule fails the
pipeline: one engine, one verdict, no drift between your editor and your CI.

## Against what you already have

Your real alternative is not another plugin. It is the `CLAUDE.md` you already
wrote, and the linters you already run.

| | CLAUDE.md alone | Linter and CI | Craftsman |
|---|---|---|---|
| Still holds at file 300 of a refactor | no | yes | yes |
| Claude sees the violation *before* writing | no | no | yes |
| Same verdict on your machine and in the pipeline | n/a | partial | yes |
| Stops Claude from repeating the same mistake | no | no | yes |
| Blocks a design decision made without a design pass | no | no | yes |

## What it actually does

**It blocks.** One rules engine, enforced identically in hooks and CI. No drift
between what your editor allows and what your pipeline rejects. GitHub, GitLab
and Bitbucket get native annotations; Jenkins runs through a generic adapter.

**It learns.** Every violation you fix is recorded locally. A fix that recurs
3+ times across 3+ files is promoted to a candidate instinct you approve in
`/craftsman:metrics`, and it becomes a project skill with provenance. Detection
is automatic, codification stays human-gated.

**It proves.** "Done" requires evidence. A task cannot be marked complete
without a verification record, and a failing test run revokes one that already
exists.

And it runs each job on the cheapest model that can do it: formatting a commit
on Haiku at low effort, an architecture review on Opus at high. You never pay
Opus rates to write a commit message.

<details>
<summary><b>Seven more mechanisms</b>: the rules engine, the structural ratchet, the adversarial design panel, bias detection, and three others</summary>

<br>

1. **Rules Engine with 3-Level Inheritance** - Global → Project → Directory overrides. Short form (`PHP001: warn`) or long form (custom regex rules). Legacy code coexists with strict new code via directory-level relaxation.
2. **Structural Ratchet** - a committed baseline records each file's structural high-water mark (complexity, size, longest function, import fan-out, suppression count). A file you touch may improve or stay equal, never regress: the mark tightens automatically on a green pass and only loosens through a documented, counted suppression. Untouched legacy is never punished for debt it already had.
3. **Adversarial Design Panel** - three contradictors (YAGNI, invariants and boundaries, feasibility) attack a design during `/craftsman:design`, before any code exists. Every objection lands in a retained or dismissed table: silence is not an option. Contradicting a design costs far less than contradicting the code built on it.
4. **Cognitive Bias Detector** - real-time detection of acceleration bias, scope creep, and over-optimization in your prompts, bilingual FR/EN, context-aware to reduce false positives.
5. **Real-Time Quality Gate** - progressive validation on every Write/Edit: regex (<50ms, always on) → LSP semantics (live, via the official LSP plugin for your language) → static analysis and architecture (PHPStan/ESLint/deptrac, opt-in per machine because running a project's analysers runs its code, see [SECURITY.md](SECURITY.md)). Degrades gracefully with zero tools installed.
6. **Metrics & Trend Analysis** - SQLite-backed tracking of violations, corrections, and sessions, with 7-day/30-day trend views to identify your most-violated rules.
7. **Security Rules** - SEC001-003 (hardcoded secrets, dynamic eval, SQL by concatenation) verified in hooks and CI, with their doctrine routed to Claude on block. Setup observes the repository and asks at most four plain-language questions.

</details>

## Install

> [!WARNING]
> Only install this plugin from the official sources below. Do not trust forks,
> mirrors, or "improved" copies distributed elsewhere. Verification steps:
> [SECURITY.md](SECURITY.md#pre-installation-verification).

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@ai-craftsman-superpowers

# 3. Restart Claude Code, then configure
exit
claude
/craftsman:setup --quick
```

**Running [Hermes](https://hermes-agent.nousresearch.com) agents instead of (or next to) Claude Code?** The same repository is a native Hermes plugin:

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
hermes plugins enable craftsman
```

Your autonomous agent gets the same gate (it cannot conclude a coding turn that leaves critical violations), the correction-learning loop, `/craftsman` on demand and the craftsman doctrine as a skill. Details and threat model: [adapters/hermes/README.md](adapters/hermes/README.md).

That is the whole setup. `--quick` reads your repository and picks defaults; run
`/craftsman:setup` without it to answer four plain-language questions instead.

<details>
<summary>Requirements, local install, and verifying it worked</summary>

<br>

**Requirements**

- Claude Code v2.1.218 or later (`claude --version`). Older versions: install the frozen 3.9.x line.
- `python3` 3.9 or later. That is the floor because it is what `/usr/bin/python3` is on a Mac without homebrew; CI imports every hook library under 3.9 so the floor cannot silently rise.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils is not required: the plugin runs on a stock macOS.

**Install from a local clone**

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /path/to/ai-craftsman-superpowers
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```

**Verify**

```bash
/plugin
# "Installed" tab → craftsman plugin should appear
# "Errors" tab → check here if skills don't appear
```

</details>

## Quick Start

```bash
# The full development cycle: design → spec → plan → implement → test → verify → commit
/craftsman:workflow
I need to add a forgot password feature.
```

Every hook is already running by then. Individual entry points when you do not
want the whole cycle: `/craftsman:design` (DDD modeling), `/craftsman:debug`
(systematic investigation), `/craftsman:challenge` (architecture review),
`/craftsman:verify` (evidence before you call it done).

New to the methodology? The [Beginner Guide](docs/guides/beginner.md) walks
through DDD concepts with worked examples, and [`/examples`](examples/) shows
each command with its expected output.

## Commands

All commands are explicitly invoked, never auto-triggered. Full reference:
[COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Category | Commands |
|----------|----------|
| Core methodology | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| AI/ML engineering | `rag`, `mlops`, `agent-design` |
| Utilities | `metrics`, `setup`, `team`, `healthcheck` |
| CI/CD | `ci` |

Scaffolders offer a template variant before generating code (`bounded-context`
vs `event-sourced` for entities, for instance). Agents that back these commands:
`team-lead`, `architect` (no Write/Edit), `doc-writer`, `security-pentester`,
`legacy-surgeon`, `ui-ux-director`, plus pack-specific reviewers for Symfony,
React and AI/ML. Full roster: [Agents Reference](docs/reference/agents.md).

## Rules Engine

Override any rule per-project or per-directory with 3-level config inheritance:

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Short form: `PHP001: warn` / `TS001: ignore`. Long form: custom rules with
regex, severity, languages. Suppress a single occurrence inline with
`// craftsman-ignore: RULE_ID`.

## CI/CD Integration

CI sources the same pack validators and the same rules engine as the hooks, so a
rule cannot mean one thing on your machine and another in the pipeline. Export a
pipeline with `/craftsman:ci export`.

| Provider | Template | Adapter |
|----------|----------|---------|
| GitHub Actions | `craftsman-quality-gate.yml` | Native: inline annotations and a PR comment |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Native: code-quality report and an MR note |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Native: build report |
| Jenkins | `Jenkinsfile.craftsman` | Generic: plain log output and a markdown file |

## Cost and Privacy

Everything above works with **zero API cost** beyond your normal Claude Code
usage: regex validation, the rules engine, bias detection, CI export and metrics
are local. One optional layer adds semantic analysis through Haiku agent hooks
at roughly $0.15-0.30 per session of 50 Write/Edit operations. Turn it off with
`agent_hooks: false` and everything else keeps working.

**No telemetry, no analytics, no phone-home.** Metrics never leave your machine.
Edited file content only reaches the Anthropic API when `agent_hooks: true`.
Command hooks write only to the local metrics DB and session state.

A cloned repository is untrusted input, so the two capabilities that would
execute repository-supplied code (`trust_project_tools` and external pack paths)
are off until **you** enable them in your own global config, and a project file
can never grant them. `tests/core/test-hostile-repo.sh` reproduces each attack
this model covers and asserts it fails. Full breakdown: [SECURITY.md](SECURITY.md).

## Known Limitations

**By design:** code rule violations block, bias detection only warns; no
auto-commit; commands are explicitly invoked, never auto-triggered; methodology
is opinionated (DDD/Clean Architecture).

**Current constraints:** PHP/TypeScript get full rule coverage, other languages
basic support only; bias detection patterns are EN/FR only; metrics are
per-machine, not shared across a team; auto-fixing violations and IDE plugins
are not supported by design.

More detail in the [FAQ](FAQ.md).

## Going Deeper

| | |
|---|---|
| [What's new in v4](https://github.com/BULDEE/ai-craftsman-superpowers/releases/latest) | Clean break targeting Claude Code >= 2.1.218: closed learning loop, native-first skills, semantic Level 1.5, context budgets. Breaking changes in [MIGRATION.md](MIGRATION.md). |
| [Architecture decisions](docs/adr/) | 28 ADRs covering every major design choice. Start with [ADR-0016](docs/adr/0016-v4-clean-break-native-first.md) and [ADR-0005](docs/adr/0005-knowledge-first-architecture.md). |
| [Knowledge bundle](knowledge/) | The methodology ships as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle: plain Markdown, versioned in git, readable by Obsidian or any OKF consumer. Zero embeddings, zero index, zero external service. |
| [CLAUDE.md guidance](docs/guides/claude-md-best-practices.md) | What belongs in your global file, your project file, and what the plugin should own instead. |
| [Hooks reference](docs/reference/hooks.md) | Every hook, exit code and rule ID, including the Circuit Breaker and the Iron Law Pattern. |
| [Troubleshooting](TROUBLESHOOTING.md) | When a skill does not appear, a hook does not fire, or a rule fires too often. |

## Using with the Superpowers Plugin

Craftsman and [Superpowers](https://github.com/anthropics/claude-code-plugins/tree/main/superpowers)
load simultaneously with no conflicts. Superpowers orchestrates the workflow
(brainstorming, planning, TDD, subagent-driven development); Craftsman enforces
quality inside it.

<details>
<summary>The combined loop, step by step</summary>

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

</details>

## Philosophy

> "Weeks of coding can save hours of planning."

Design before code. Test-first. Systematic debugging over random fixes. YAGNI.
Clean Architecture, dependencies point inward. Make it work, make it right, make
it fast, in that order.

Pragmatism over dogmatism: 80% coverage on critical paths beats 100% everywhere;
DDD for complex domains, not every domain; concrete first, abstract when
actually needed.

## Contributing

Contributions welcome. Fork, branch, follow the methodology (`/craftsman:design`
first), add tests, open a PR. Details in [CONTRIBUTING.md](CONTRIBUTING.md).

Looking for a place to start? The [good first issues](https://github.com/BULDEE/ai-craftsman-superpowers/labels/good%20first%20issue)
are real work, not busywork: new language packs, rule coverage, examples,
translations.

## Contributors

<table>
  <tr>
    <td align="center" width="180">
      <a href="https://github.com/woprrr"><img src="https://github.com/woprrr.png" width="72" alt="" style="border-radius:50%"><br><b>Alexandre Mallet</b></a><br>
      <sub>Author and maintainer</sub><br>
      <sub><a href="https://buldee.com">BULDEE</a></sub>
    </td>
    <td align="center" width="180">
      <a href="https://github.com/Lucr4m"><img src="https://github.com/Lucr4m.png" width="72" alt="" style="border-radius:50%"><br><b>Marc Lucas</b></a><br>
      <sub>Hooks architecture and config resolution</sub><br>
      <sub>CEO, <a href="https://www.malucasfire.dev">M.A. LucasFireDev</a></sub>
    </td>
  </tr>
</table>

[**Marc Lucas**](https://github.com/Lucr4m) ([LinkedIn](https://www.linkedin.com/in/marc-lucas-75a012120/)), CEO of [M.A. LucasFireDev](https://www.malucasfire.dev), contributes actively to the plugin: the migration from agent hooks to gated command hooks, the global `~/.claude/.craft-config.yml` fallback, hook path resolution, and the test suite that covers them. M.A. LucasFireDev is a PHP/Symfony consultancy doing code audit, maintenance and team coaching.

Your name belongs here too.

## Sponsors

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Building the future of AI-assisted development |
| **[M.A. LucasFireDev](https://www.malucasfire.dev)** | PHP/Symfony consultancy, sponsoring the plugin with engineering time |

Interested in sponsoring? [Contact us](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)

## Support

[Discord](https://discord.gg/eBpgHAGu) •
[Issues](https://github.com/BULDEE/ai-craftsman-superpowers/issues) •
[Discussions](https://github.com/BULDEE/ai-craftsman-superpowers/discussions) •
[Changelog](CHANGELOG.md)

Apache License 2.0, see [LICENSE](LICENSE).

---

<div align="center">

**If Craftsman refused a write you would have merged, star the repository.**
<br>
It is the only metric this project collects.

<br>

Forged by [Alexandre Mallet](https://github.com/woprrr) · Sponsored by [BULDEE](https://buldee.com) & [M.A. LucasFireDev](https://www.malucasfire.dev)

[ai-craftsman.dev](https://ai-craftsman.dev)

</div>
