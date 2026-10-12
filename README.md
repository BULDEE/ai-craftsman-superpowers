<div align="center">

<a href="https://ai-craftsman.dev">
  <img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/github-banner.png" alt="AI Craftsman Superpowers - a prompt asks, this enforces" width="100%">
</a>

🇬🇧 **English** | [🇫🇷 Français](README.fr.md)

[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet?logo=claude)](#claude-code)
[![Codex](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FBULDEE%2Fai-craftsman-superpowers%2Fmain%2Fhooks%2Fhost-capabilities.json&query=%24.hosts.codex.version&prefix=v&label=Codex%20qualified&logo=openai&color=412991)](docs/guides/codex-quickstart.md)
[![Grok](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FBULDEE%2Fai-craftsman-superpowers%2Fmain%2Fhooks%2Fhost-capabilities.json&query=%24.hosts.grok.version&prefix=v&label=Grok%20qualified&logo=x&color=000000)](docs/guides/grok-quickstart.md)
[![Hermes](https://img.shields.io/badge/Hermes-native%20plugin-6f42c1)](docs/guides/hermes-quickstart.md)

**Your agent writes the code. Your architecture rules decide what lands.**

For teams running coding agents on a codebase where a layer violation costs
more than the feature does.

[Install](#install) •
[First ten minutes](#your-first-ten-minutes) •
[Commands](#commands) •
[Examples](examples/) •
[Hosts](#host-support) •
[Docs](https://ai-craftsman.dev/docs)

</div>

---

## A prompt asks. This enforces.

You can write "always use final classes" in your `CLAUDE.md` or `AGENTS.md`.
The model will follow it, until the context fills up, or the task gets long,
or the tenth file of a refactor. Instructions decay. That is not a discipline
problem, it is an architecture problem: nothing in the loop is checking.

Craftsman puts the check in the loop. The same rules run as hooks on every
write, as a gate in your CI, and as the criteria a reviewer agent reads. Layer
violations and missing `strict_types` are refused before the write lands,
everything else is handed straight back to the model as a finding it has to
answer for, and the same rule fails your pipeline if it reaches a pull request.

## See it refuse

The model tries to write an entity that imports from the infrastructure layer.
The file never reaches your disk:

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

The model reads the same two lines you do, corrects the import, and writes
again. The correction is recorded; if that same rule keeps coming back across
files, it is offered to you as a candidate instinct in `/craftsman:metrics`.
And if the violation ever reaches a pull request instead, the identical rule
fails the pipeline: one engine, one verdict, no drift between your editor and
your CI.

## Install

> [!WARNING]
> Only install this plugin from the official sources below. Do not trust forks,
> mirrors, or "improved" copies distributed elsewhere. Verification steps:
> [SECURITY.md](SECURITY.md#pre-installation-verification).

Pick your host. Each block is complete: after it, the gate refuses bad writes.

### Claude Code

```bash
/plugin marketplace add BULDEE/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
# restart Claude Code, then:
/craftsman:setup --quick
```

### Codex

```bash
codex plugin marketplace add BULDEE/ai-craftsman-superpowers
codex plugin add craftsman@ai-craftsman-superpowers
codex    # then /hooks: review and trust the craftsman handlers
```

Installing does not trust the hooks: until you review them in `/hooks`, they
load and do not run. Detail and limits: [Codex quickstart](docs/guides/codex-quickstart.md).

### Grok

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/src/ai-craftsman-superpowers
bash ~/src/ai-craftsman-superpowers/bin/craftsman-grok-install
```

Grok runs none of a plugin's bundled hooks on a fresh process, so the
installer also writes the global gate `~/.grok/hooks/craftsman.json` (the
same write as `craftsman-ci export --target grok-hooks --into ~/.grok/hooks`).
Run it again to upgrade. Detail and limits: [Grok quickstart](docs/guides/grok-quickstart.md).

### Hermes

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
hermes plugins enable craftsman
```

The gate applies at the conclusion: the agent cannot conclude a coding turn
that leaves critical violations. Detail: [Hermes quickstart](docs/guides/hermes-quickstart.md).

### Check it worked

Run `/craftsman:healthcheck` (on Grok: `/healthcheck`), or from a shell
`bash <plugin root>/bin/craftsman-healthcheck --report`. Every row that is not
`ok` names the command that fixes it.

<details>
<summary>Requirements and local install</summary>

<br>

**Requirements**

- Claude Code v2.1.218 or later (`claude --version`). Older versions: install the frozen 3.9.x line.
- `python3` 3.9 or later. That is the floor because it is what `/usr/bin/python3` is on a Mac without homebrew; CI imports every hook library under 3.9 so the floor cannot silently rise.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils is not required: the plugin runs on a stock macOS.

**Install from a local clone (Claude Code)**

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /path/to/ai-craftsman-superpowers
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```

`/plugin` then shows craftsman in the "Installed" tab; the "Errors" tab says
why a skill does not appear.

</details>

## Your first ten minutes

**1. Configure** (reads your repository, asks nothing):

```text
/craftsman:setup --quick
```

**2. Watch it refuse.** Ask for something the rules forbid, on purpose:

```text
Create src/Domain/Order/Order.php, a class that uses App\Infrastructure\Doctrine\OrderRepository.
```

The write is refused before disk, `LAYER001` among the reasons, and the model
rewrites the class behind a repository interface in the domain. That round trip is the
product.

**3. Build a feature with the full cycle** (design, spec, plan, implement,
test, verify, commit):

```text
/craftsman:workflow
I need to add a forgot password feature.
```

**4. Prove it before you call it done:**

```text
/craftsman:verify
```

Want only one step of the cycle? `/craftsman:design` (DDD modeling),
`/craftsman:debug` (systematic investigation), `/craftsman:challenge`
(architecture review). New to the methodology? The
[Beginner Guide](docs/guides/beginner.md) walks through DDD with worked
examples.

## Host support

Four hosts, one engine. What each host loads and observes is measured on the
real CLI and recorded in [`hooks/host-capabilities.json`](hooks/host-capabilities.json)
(provenance: [`tests/fixtures/hosts/PROVENANCE.md`](tests/fixtures/hosts/PROVENANCE.md)).

| | Claude Code | Codex | Grok | Hermes |
|---|---|---|---|---|
| Install | `/plugin install` | `codex plugin add` | `craftsman-grok-install` | `hermes plugins enable` |
| Extra step | none | trust hooks in `/hooks` | none (global gate) | none |
| Write gate before disk | `Write`, `Edit` | `apply_patch` | `write`, `search_replace` | opt-in `write_gate: on`, SEC001 and LAYER001 |
| Evidence gate before a task completes | yes (`TaskCompleted`) | no, event not fired | no, event not fired | yes (`pre_verify`) |
| `ask` decision | yes | no, denies instead | yes | not applicable |
| Test evidence (grant and revoke) | yes | no, no exit code in the shell event | yes | not applicable |
| Skills | 22 | 22 | 22 (`/name`) | 7 plus `/craftsman` |

On every host, the gate judges the host's write tools. A file written by a
shell command the model runs (`printf > file`, `sed -i`, a script) is not
gated before disk: CI (`ci/craftsman-ci.sh`) catches it. The pre-push hook
reads no file and only warns when the session was never verified; Hermes alone
refuses a push until a passing conclusion on the tree it publishes.
GitHub Copilot has an adapter for its documented hook contract; no Copilot
surface is qualified yet, so it has no badge.

## Commands

Fifteen commands start only when you type them; seven (`challenge`, `debug`,
`test`, `team`, `rag`, `mlops`, `agent-design`) may be started by the model
when the context matches. Every command has a worked example with its expected
output: [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Category | Commands |
|----------|----------|
| Core methodology | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel`, `loop` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| AI/ML engineering | `rag`, `mlops`, `agent-design` |
| Utilities | `setup`, `healthcheck`, `metrics`, `team` |
| CI/CD | `ci` |

Agents that back these commands: `team-lead`, `architect` (no Write/Edit),
`doc-writer`, `security-pentester`, `legacy-surgeon`, `ui-ux-director`, plus
pack-specific reviewers for Symfony, React and AI/ML. The 12 agent missions
ship as ordinary files. Full roster: [Agents Reference](docs/reference/agents.md).

## Against what you already have

Your real alternative is not another plugin. It is the `CLAUDE.md` or
`AGENTS.md` you already wrote, and the linters you already run.

| | Instructions file alone | Linter and CI | Craftsman |
|---|---|---|---|
| Still holds at file 300 of a refactor | no | yes | yes |
| The model sees the violation *before* writing | no | no | yes |
| Same verdict on your machine and in the pipeline | n/a | partial | yes |
| Stops the model from repeating the same mistake | no | no | yes |
| Warns when a domain model is written without a design pass | no | no | yes |

## What it actually does

**It blocks.** One rules engine, enforced identically in hooks and CI. No drift
between what your editor allows and what your pipeline rejects. GitHub, GitLab,
Bitbucket and Jenkins all get native annotations.

**It learns.** Every violation you fix is recorded locally. A fix that recurs
3+ times across 3+ files is promoted to a candidate instinct you approve in
`/craftsman:metrics`, and it becomes a project skill with provenance. Detection
is automatic, codification stays human-gated.
On Claude Code 2.1.291 or later, the optional `craftsman-cockpit` mod reviews
them in a pane: `/plugin install craftsman-cockpit@ai-craftsman-superpowers`,
then `/instincts` shows each candidate's rule, how often it was accepted or
refused, where it was fixed, and the exact skill Approve would write. You press
Approve or Reject; the mod decides nothing itself
([ADR-0031](docs/adr/0031-function-hook-mods-as-companion-surface.md)).

**It proves.** "Done" requires evidence. A task cannot be marked complete
without a verification record, and a failing test run revokes one that already
exists.

And on Claude Code it runs each job on the cheapest model that can do it:
formatting a commit on Haiku at low effort, an architecture review on Opus at
high.

<details>
<summary><b>Seven more mechanisms</b>: the rules engine, the structural ratchet, the adversarial design panel, bias detection, and three others</summary>

<br>

1. **Rules Engine with 3-Level Inheritance** - Global, Project, Directory overrides. Short form (`PHP001: warn`) or long form (custom regex rules). Legacy code coexists with strict new code via directory-level relaxation.
2. **Structural Ratchet** - a committed baseline records each file's structural high-water mark (complexity, size, longest function, import fan-out, suppression count). A file you touch may improve or stay equal, never regress: the mark tightens automatically on a green pass and only loosens through a documented, counted suppression. Untouched legacy is never punished for debt it already had.
3. **Adversarial Design Panel** - three contradictors (YAGNI, invariants and boundaries, feasibility) attack a design during `/craftsman:design`, before any code exists. Every objection lands in a retained or dismissed table: silence is not an option.
4. **Cognitive Bias Detector** - real-time detection of acceleration bias, scope creep, and over-optimization in your prompts. Curated English patterns warn you directly; every other language hands the call to the model already reading your prompt, which surfaces or silently drops it with the whole session as context. No second model and no network call. Language tags are BCP 47. The non-English lexicons are recall-oriented seed lists no native speaker has reviewed yet.
5. **Real-Time Quality Gate** - progressive validation on every write the host performs through a write tool: regex (always on, cost measured by `tests/perf/test-hook-latency.sh`), then LSP semantics (live, via the official LSP plugin for your language), then static analysis and architecture (PHPStan, ESLint, deptrac: opt-in per machine because running a project's analysers runs its code, see [SECURITY.md](SECURITY.md)). Degrades gracefully with zero tools installed.
6. **Metrics & Trend Analysis** - SQLite-backed tracking of violations, corrections, and sessions, with 7-day and 30-day trend views to identify your most-violated rules.
7. **Security Rules** - SEC001-003 (hardcoded secrets, dynamic eval, SQL by concatenation) verified in hooks and CI, with their doctrine routed to the model on block.

</details>

## Rules Engine

Override any rule per-project or per-directory with 3-level config inheritance:

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Short form: `PHP001: warn` / `TS001: ignore`. Long form: custom rules with
regex, severity, languages. Suppress a single occurrence inline with
`// craftsman-ignore: RULE_ID`, except the security rules (`SEC*`), which no
marker silences on any front-end.

## CI/CD Integration

CI sources the same pack validators and the same rules engine as the hooks, so
a rule cannot mean one thing on your machine and another in the pipeline.
Export a pipeline with `/craftsman:ci export`
([example](examples/ci/01-export-github-gate.md)).

| Provider | Template | Adapter |
|----------|----------|---------|
| GitHub Actions | `craftsman-quality-gate.yml` | Native: inline annotations and a PR comment |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Native: code-quality report and an MR note |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Native: build report |
| Jenkins | `Jenkinsfile.craftsman` | Native: a Checkstyle report read by Warnings Next Generation |

## Cost and Privacy

Everything above works with **zero API cost** beyond your normal model usage:
regex validation, the rules engine, bias detection, CI export and metrics are
local. One optional layer adds semantic analysis through a headless review
(Haiku on Claude Code) at roughly $0.15-0.30 per session of 50 writes. Turn it
off with `agent_hooks: false` and everything else keeps working.

**No telemetry, no analytics, no phone-home.** Metrics never leave your
machine, and each host and session keeps its own store. Edited file content
only reaches a model API when `agent_hooks: true`.

A cloned repository is untrusted input, so the two capabilities that would
execute repository-supplied code (`trust_project_tools` and external pack
paths) are off until **you** enable them in your own global config, and a
project file can never grant them. `tests/core/test-hostile-repo.sh`
reproduces each attack this model covers and asserts it fails. Full breakdown:
[SECURITY.md](SECURITY.md).

## Known Limitations

**By design:** code rule violations block, bias detection only warns; no
auto-commit; methodology is opinionated (DDD/Clean Architecture).

**Current constraints:** PHP, TypeScript, Python, Go, Rust and Bash get full
rule coverage, other languages basic support only; metrics are per-machine,
not shared across a team; shell-written files are caught by CI, not before
disk (the pre-push hook only warns); per-host gaps are listed in
[Host support](#host-support).

More detail in the [FAQ](FAQ.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Going Deeper

| | |
|---|---|
| [Commands and examples](COMMANDS-QUICK-REF.md) | Every command, who starts it, and a worked example with expected output. |
| [Codex](docs/guides/codex-quickstart.md), [Grok](docs/guides/grok-quickstart.md), [Hermes](docs/guides/hermes-quickstart.md) quickstarts | Install, verify, limits and uninstall per host. |
| [Architecture decisions](docs/adr/) | Every major design choice. Start with [ADR-0016](docs/adr/0016-v4-clean-break-native-first.md) and [ADR-0029](docs/adr/0029-host-adapter-contract.md) (host adapters, one core). |
| [Knowledge bundle](knowledge/) | The methodology ships as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) bundle: plain Markdown, versioned in git. Zero embeddings, zero index, zero external service. |
| [For non-developers](docs/guides/for-non-developers.md) | What this plugin does, in plain language, and the three questions worth asking your team. |
| [CLAUDE.md guidance](docs/guides/claude-md-best-practices.md) | What belongs in your global file, your project file, and what the plugin should own instead. |
| [Hooks reference](docs/reference/hooks.md) | Every hook, exit code and rule ID. |
| [Migration](MIGRATION.md) | Breaking changes across major versions. |

## Using with the Superpowers Plugin

Craftsman and [Superpowers](https://github.com/obra/superpowers) load
simultaneously with no conflicts. Superpowers orchestrates the workflow
(brainstorming, planning, TDD, subagent-driven development); Craftsman enforces
quality inside it.

<details>
<summary>The combined loop, step by step</summary>

```
1. /superpowers:brainstorming     → Design the solution collaboratively
2. /superpowers:writing-plans     → Create implementation plan
3. /superpowers:subagent-driven-development → Execute with fresh subagents
   ├── Craftsman hooks fire on every write (real-time quality gate)
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
`bash tests/run-tests.sh` runs the whole suite, including
`tests/core/test-command-docs.sh`, which fails when a command loses its
example.

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
