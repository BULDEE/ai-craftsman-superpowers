# Commands Quick Reference

Every `/craftsman:*` command on one page, with a worked example for each. See
[README.md](README.md#commands) for the overview.

**Started by**: *you* means the command starts only when you type it first in a
prompt; *you or model* means the model may also start it when the context
matches. `tests/core/test-command-docs.sh` fails when this page, the examples
or the README drift from the skills.

**Names per host.** Claude Code: `/craftsman:<name>`. Codex loads the same 22
skills natively under the plugin `craftsman`. Grok: `/<name>`,
except `plan`, `loop` and `workflow`, which Grok already owns, so those stay
`/craftsman:plan`, `/craftsman:loop`, `/craftsman:workflow`. Hermes: `/craftsman`
plus seven situation skills, see the
[Hermes quickstart](docs/guides/hermes-quickstart.md).

## Core Methodology

| Command | What it does | Started by | Example |
|---------|--------------|------------|---------|
| `/craftsman:design` | DDD design with challenge phases (Understand, Challenge, Recommend, Implement) | you | [create an entity](examples/design/01-create-entity.md) |
| `/craftsman:debug` | Systematic debugging using the ReAct pattern | you or model | [memory leak](examples/debug/01-memory-leak.md) |
| `/craftsman:plan` | Structured planning and execution with checkpoints | you | [microservice migration](examples/plan/01-migration-microservices.md) |
| `/craftsman:challenge` | Senior architecture review and code challenge | you or model | [code review](examples/challenge/01-code-review.md) |
| `/craftsman:verify` | Evidence-based verification before completion claims | you | [pre-commit check](examples/verify/01-pre-commit-verification.md) |
| `/craftsman:workflow` | Full pipeline: design, spec, plan, implement, test, verify, commit | you | [feature workflow](examples/workflow/01-feature-workflow.md) |
| `/craftsman:loop` | Bounded verification loop: act, verify, repeat until green, no progress or budget | you | [red-test burn-down](examples/loop/01-red-test-burndown.md) |
| `/craftsman:spec` | Specification-first development (TDD/BDD) | you | [forgot password](examples/spec/01-forgot-password-spec.md) |
| `/craftsman:refactor` | Systematic refactoring with behavior preservation (safety net first, Mikado mode) | you | [extract a value object](examples/refactor/01-extract-value-object.md) |
| `/craftsman:legacy` | Legacy rescue: hotspot audit, characterization tests, strangler-fig migration | you | [audit an inherited codebase](examples/legacy/01-audit-inherited-codebase.md) |
| `/craftsman:test` | Pragmatic testing following Fowler/Martin principles | you or model | [testing strategy](examples/test/01-testing-strategy.md) |
| `/craftsman:git` | Safe git workflow with destructive command protection | you | [safe commit](examples/git/01-safe-commit.md) |
| `/craftsman:parallel` | Parallel agent orchestration for independent tasks | you | [parallel review](examples/parallel/01-parallel-review.md) |

## Scaffolding

`/craftsman:scaffold` offers a template variant before generating code
(`bounded-context` or `event-sourced` for entities, for instance). Worked
example: [an entity in a bounded context](examples/scaffold/01-entity-bounded-context.md).

| Command | What it does | Started by |
|---------|--------------|------------|
| `/craftsman:scaffold entity` | DDD entity with Value Objects, Events, Tests | you |
| `/craftsman:scaffold usecase` | Use case with Command/Handler pattern | you |
| `/craftsman:scaffold component` | React component with TypeScript, tests, Storybook | you |
| `/craftsman:scaffold hook` | TanStack Query hook with tests | you |
| `/craftsman:scaffold api-resource` | API Platform resource with State Provider | you |
| `/craftsman:scaffold pack` | Create a new community pack | you |

## AI/ML Engineering

| Command | What it does | Started by | Example |
|---------|--------------|------------|---------|
| `/craftsman:rag` | Design RAG pipelines (ingestion, retrieval, generation) | you or model | [internal docs Q&A](examples/rag/01-internal-docs-qa.md) |
| `/craftsman:mlops` | Audit ML projects for production readiness | you or model | [production readiness audit](examples/mlops/01-production-readiness-audit.md) |
| `/craftsman:agent-design` | Design AI agents using the 3P pattern (Perceive, Plan, Perform) | you or model | [support triage agent](examples/agent-design/01-support-triage-agent.md) |

## Utilities

| Command | What it does | Started by | Example |
|---------|--------------|------------|---------|
| `/craftsman:setup` | Setup and onboarding. `--quick` reads the repository and picks defaults | you | [quick setup](examples/setup/01-quick-setup.md) |
| `/craftsman:healthcheck` | Diagnose the installation, the hooks and the gate on this host | you | [plugin diagnostic](examples/healthcheck/01-plugin-diagnostic.md) |
| `/craftsman:metrics` | Quality metrics dashboard (violations, trends, sessions, instincts) | you | [instinct review](examples/metrics/02-instinct-review.md) |
| `/craftsman:team` | Create and manage agent teams for collaborative tasks | you or model | [full-stack feature](examples/team/01-feature-fullstack.md) |

## CI/CD Integration

| Command | What it does | Started by | Example |
|---------|--------------|------------|---------|
| `/craftsman:ci` | Export quality gates to CI/CD (GitHub, GitLab, Bitbucket, Jenkins) | you | [export the GitHub gate](examples/ci/01-export-github-gate.md) |

## Shell helpers

On Claude Code these are on the plugin's PATH. Elsewhere, call them from the
plugin root (`bash <plugin root>/bin/<name>`).

| Helper | What it does |
|--------|--------------|
| `craftsman-healthcheck --report` | The same diagnostic as `/craftsman:healthcheck`, from a shell |
| `craftsman-ci export --target <t>` | Export doctrine (`agents-md`, `cursor`, `copilot`; `all` writes these three), Codex roles (`codex-agents`) or a host gate (`grok-hooks`, `codex-hooks`) |
| `craftsman-grok-install` | Install on Grok and write the global gate `~/.grok/hooks/craftsman.json` |
| `craftsman-runtime metrics` | Print the metrics database of the current host and session |
