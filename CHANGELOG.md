# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.0] - 2026-03-29

### Added
- **Knowledge-RAG MCP Server**: Migrated from excluded ai-pack to proper packs/ai-ml/mcp/ with setup script
- **API Resource Scaffold Type**: `/craftsman:scaffold api-resource` with API Platform State Provider/Processor patterns
- **Pack-Specific Test Suites**: Separate test files for symfony, react, and ai-ml packs
- **CI Pack-Loader Integration**: craftsman-ci.sh now loads pack-specific rules

### Changed
- **Test structure reorganized**: tests/hooks/ → tests/core/ + tests/packs/ for better modularity
- **Distribution ignore updated**: Targets packs/*/mcp/*/node_modules/ instead of blanket ai-pack/
- **plugin.json**: Registers knowledge-rag MCP server for AI-ML pack users

### Removed
- Old `ai-pack/` directory (replaced by packs/ai-ml/mcp/)

## [2.4.0] - 2026-03-29

### Added
- **Core + Pack Architecture**: Loadable language packs (symfony, react, ai-ml) with `pack.yml` manifests
- **Pack Loader** (`hooks/lib/pack-loader.sh`): Discovers, validates, and loads packs based on stack config
- **Symlink Management**: Pack agents and commands auto-linked into root directories for Claude Code discovery
- **API Craftsman Agent**: New specialized agent for API Platform, REST/HATEOAS, OpenAPI in symfony pack
- **Unified Scaffold Command**: `/craftsman:scaffold <type>` loads types from active packs
- **Pack Selection in Setup**: `/craftsman:setup` now includes pack auto-detection and selection

### Changed
- **Commands consolidated** (25 → 15 core + 3 pack): Merged setup+start, unified scaffold, moved AI-ML commands to pack
- **Agents consolidated** (12 → 5 core + 6 pack): Removed duplicates, added allowedTools, team-lead Opus→Sonnet
- **post-write-check.sh refactored**: 536 → ~390 lines orchestrator delegating to pack validators
- **file-changed.sh deduplicated**: Removed ~60 lines of duplicated validators, now uses pack-loader
- **static-analysis.sh**: Reduced to thin dispatcher, wrappers moved to packs
- **Knowledge distributed**: PHP examples → symfony pack, TS examples → react pack, AI/ML → ai-ml pack
- **Templates migrated**: `symfony-pack/` → `packs/symfony/templates/`, `react-pack/` → `packs/react/templates/`

### Removed
- `architecture-reviewer` agent (absorbed by `architect`)
- `ai-reviewer` agent (absorbed by `ai-engineer`)
- `/craftsman:source-verify` command (moved to CLAUDE.md instruction)
- `/craftsman:agent-create` command (integrated into scaffold)
- `/craftsman:start` command (absorbed into setup)
- Standalone scaffold commands (entity, usecase, component, hook — unified into scaffold)
- Old `symfony-pack/`, `react-pack/` root directories

---

## [2.3.0] - 2026-03-29

### Added

- **Distribution ignore** — `.claude-plugin/ignore` reduces plugin size from 134 MB to <1 MB by excluding ai-pack/, tests/, scripts/, docs/superpowers/
- **Dependency check** — `session-start.sh` verifies python3, jq, sqlite3 at boot with clear install instructions if missing
- **Agent hooks opt-out** — `agent_hooks: false` in userConfig disables all 4 AI agent hooks (DDD verifier, Sentry, analyzer, reviewer). Saves ~$0.15-0.30/session in Haiku API costs.
- **API Cost Model** — README section documenting agent hook costs and opt-out mechanism
- **Auto-setup gate** — Improved first-run detection: checks both global (`~/.claude/.craft-config.yml`) and project config, with clear guidance to run `/craftsman:setup`

---

## [2.2.1] - 2026-03-29

### Added

- **Version bump script** — `scripts/bump-version.sh` updates all version references in one command
- **README v2.x features** — Custom Rule Engine, CI/CD Integration, Circuit Breaker, Pack Templates, Schema Validation sections
- **README missing commands** — Added `/craftsman:team`, `/craftsman:start` to commands table

### Fixed

- **SECURITY.md** — Updated commands count (22→25), hooks count (6→7), added pre-push-verify.sh, v2.x audit trail, supported versions
- **docs/reference/skills.md** — Added 3 missing commands to Quick Reference Table (`/craftsman:team`, `/craftsman:ci`, `/craftsman:start`)
- **docs/reference/hooks.md** — Added pre-push-verify.sh, Rules Engine, Schema Validation, Atomic Commits, Monorepo Safety sections
- **README Project Structure** — Added `config/`, `ci/`, `pre-push-verify.sh`, fixed hooks count 6→7

---

## [2.2.0] - 2026-03-29

### Security

- **SQL injection fix** — `metrics-db.sh` write functions now use parameterized queries via `metrics-query.py` Python helper. Eliminates injection risk from filenames/rule names containing SQL metacharacters.
- **Bitbucket adapter fix** — Replaced fragile double-nested `python3 -c` JSON encoding with single safe call using `sys.stdin.read()`.

### Added

- **Hooks schema validation** — `session-start.sh` validates `hooks.json` events against supported set at startup. Catches unsupported events before CI fails.
- **Atomic commit enforcement** — Stop hook caps file inspection at 20 files and warns when >15 files modified in a session, encouraging small focused commits.
- **Monorepo sampling** — InstructionsLoaded agent switches to directory-level analysis when Glob returns >100 files. Prevents token explosion on large codebases.
- **Key Differentiators section** — README "Why Craftsman?" marketing table with 8 unique selling points.
- **Project CLAUDE.md** — Development rules, testing commands, version sync checklist, and 10 marketing differentiators.

### Fixed

- `commands/ci.md` — Added missing `effort: medium` frontmatter field.
- README badges — Updated from v1.5.0/22 commands to v2.2.0/25 commands.
- README — Removed outdated "CI/CD not supported" line (CI has been supported since v2.1.0).

---

## [2.1.0] - 2026-03-29

### Added

- **Custom Rule Engine** — Per-project rule customization with 3-level inheritance:
  - Global (~/.claude/.craft-config.yml) → Project (.craft-config.yml) → Directory (.craft-rules.yml)
  - Short form (`PHP001: warn`) and long form (custom rules with pattern, message, severity, languages)
  - Custom rule validation on config load (bad regex = skipped with warning)
- **CI Adapter System** — Universal adapter architecture for multi-provider CI:
  - Auto-detection via env vars (GITHUB_ACTIONS, GITLAB_CI, BITBUCKET_BUILD_NUMBER)
  - 4 adapters: GitHub Actions, GitLab CI, Bitbucket Pipelines, Generic (Jenkins/CircleCI)
  - `craftsman-ci.sh ci` mode with full adapter lifecycle
  - `craftsman-ci.sh init --provider` generates CI template files
  - Unified PR/MR comment format across all providers
  - Inline file annotations (GitHub ::error, GitLab codequality, Bitbucket Reports API)
- **CI Templates** — GitLab CI, Bitbucket Pipelines, Jenkinsfile templates
- **Circuit Breaker** — Protects against external service failures:
  - 3 states: closed → open → half-open
  - Configurable threshold and cooldown per channel
  - File-based cache with TTL and LRU eviction
  - Stale cache serving during circuit open
- **Pack Template Variants**:
  - Symfony: CRUD API (API Platform simple) + Event-Sourced (Aggregate + Event Store + Projections)
  - React: Form-Heavy (multi-step wizard + Zod + useActionState) + Dashboard-Data (TanStack Table + Recharts)

### Changed

- **Config format** — Updated to v2.1 with `rules:` section for per-rule overrides and `channels:` for circuit breaker config
- **post-write-check.sh** — Refactored to use rules engine instead of hardcoded severity logic
- **craftsman-ci.sh** — Integrated rules engine, added `ci` and `init` subcommands, bumped to v2.1.0
- **channels.sh** — Rewritten with circuit breaker integration and cache orchestration
- **Sentry hook** — Now checks circuit breaker state before querying, records success/failure
- **GitHub Actions template** — Simplified to use adapter system

---

## [2.0.0] - 2026-03-28

### Added

- **Teams system** — Agent team orchestration with `/craftsman:team` (create, context, list):
  - 3 built-in templates: `code-review`, `feature`, `security-audit`
  - Interactive team builder with questionnaire or template selection
  - Codebase analysis for optimal team composition
- **CI export** — `/craftsman:ci` skill + standalone `craftsman-ci.sh` CLI:
  - Same regex rules as hooks (PHP001-005, TS001-003, LAYER001-003)
  - JSON + text output formats for CI/CD integration
  - GitHub Actions workflow template (`craftsman-quality-gate.yml`)
  - 36 CLI tests, 0 failures
- **Onboarding** — `/craftsman:start` for first-time users:
  - Auto-detect stack, scan codebase, suggest top 5 skills
  - Quick reference card with all commands
- **Pre-push verification** — `pre-push-verify.sh` blocks `git push` if `/craftsman:verify` not run
- **Workflow enforcement** — `bias-detector.sh` warns when domain modeling without `/craftsman:design`
- **TeammateIdle + TaskCompleted hooks** — New hook events in hooks.json
- **4 canonical examples** — API Platform 4 State Provider, Messenger handler, React Server Component, Compound Component
- **3 anti-patterns** — sync-in-async (Messenger), barrel imports, inline components

### Changed

- **Hooks enriched** — Structured PHPStan/ESLint/deptrac parsing with error-to-code mapping (PHPSTAN001-003, ESLINT001)
- **Correction Learning v2** — Cross-file pattern detection: project-wide and directory-level suggestions when same rule violated in 3+ files
- **craftsman-ignore multi-rules** — `// craftsman-ignore: PHP001, TS001, LAYER001` on single line
- **Session metrics** — Now tracks agent invocations, team type, and completed tasks
- **All 22 skills enriched** — `paths` field (7 skills), `effort` field (all 22), `!command` injections for runtime context
- **Scaffolders** (entity, usecase, component, hook) — Worktree isolation recommendation
- **/craftsman:plan** — TaskCreate/TaskUpdate integration + Agent tool dispatch for parallel execution
- **/craftsman:verify** — Auto-detection + real execution of tests/lint/typecheck + session state `verified=true`
- **/craftsman:debug** — WebSearch/WebFetch auto-research after 2 inconclusive investigation cycles
- **/craftsman:challenge** — Deep Review Mode with parallel reviewer agents for complex PRs
- **/craftsman:parallel** — Real Agent tool spawn with `isolation: "worktree"` and `run_in_background: true`
- **/craftsman:setup** — Auto-detection of stack + analysis tools check + pack auto-selection
- **/craftsman:metrics** — Correction trends, quality score (100-based), agent/team usage stats
- **Symfony pack** — API Platform 4 (State Provider/Processor), Messenger async handlers, Scheduler 7.4+, MapRequestPayload
- **React pack** — React 19 Server Components, useOptimistic, useTransition, Compound Components, Render Props with useSuspenseQuery
- **knowledge/stack-specifics.md** — 6 new sections (API Platform 4, Messenger, Scheduler, React 19, Composition)

### Fixed

- **8 factual inaccuracies** in packs — Messenger routing glob, Processor return type, Next.js cache leak, unsafe type cast, untyped activity fetch, missing ErrorBoundary note, pagination type, missing patterns

---

## [1.5.0] - 2026-03-28

### Added

- **7 craftsman agents** — New specialized agents for full-stack implementation:
  - `team-lead` (Opus, max effort) — orchestrator, delegates, challenges, never codes
  - `backend-craftsman` (Sonnet) — PHP/Symfony expert with Symfony.com + API Platform refs
  - `frontend-craftsman` (Sonnet) — React/TS expert with 65 Vercel best practices rules
  - `architect` (Sonnet, read-only) — DDD/Clean Architecture validation, disallowedTools: Edit,Write
  - `ai-engineer` (Sonnet) — RAG, LLM, MCP server, agent design
  - `ui-ux-director` (Sonnet) — UX, WCAG 2.1 AA, design tokens, data visualization
  - `doc-writer` (Haiku, cost-optimized) — ADRs, README, CHANGELOG, runbooks
- **Agent Teams support** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled in settings. Team launch prompt prepared at `.claude/team-prompts/v2-implementation.md`.

### Changed

- **5 existing reviewers enriched** — All reviewers now have `memory: project` (cross-session learning), `effort: high`, `skills` preload, and `maxTurns` (camelCase per official Claude Code docs). Fields migrated from legacy `allowed-tools`/`max-turns` to official `tools`/`maxTurns`.

---

## [1.4.0] - 2026-03-28

### Added

- **Sentry Channel integration** — Sentry MCP server bound via `channels` in plugin.json. PostToolUse agent hook queries Sentry for errors related to edited files.
- **Channel lifecycle library** — `hooks/lib/channels.sh` provides `channel_available()` and `channel_status_summary()` for gating channel usage.
- **Sentry configuration** — `sentry_org`, `sentry_project`, `sentry_token` (sensitive: true) in userConfig.
- **Corrections reporting** — InstructionsLoaded agent hook queries 30-day correction trends and suggests strictness adjustments.
- **Channel status** — InstructionsLoaded agent reports active channels at session start.

### Changed

- **config.sh** — Added `_config_resolve()` generic helper. All config functions now use it.
- **hooks.json** — Now has 8 events, 6 command hooks, 4 agent hooks (PostToolUse DDD + Sentry, InstructionsLoaded, Stop).

---

## [1.3.0] - 2026-03-28

### Added

- **Semantic Intelligence** — 3 agent hooks for semantic analysis beyond regex:
  - PostToolUse DDD verifier (Haiku) — checks layer violations, aggregate boundaries, value objects, naming
  - InstructionsLoaded project analyzer (Haiku) — builds architectural context map at session start
  - Stop final reviewer (Haiku) — validates architecture before session end (strict mode only)
- **Correction Learning System** — Detects when user fixes Claude-generated code, records patterns in metrics.db corrections table, injects trends into InstructionsLoaded.
- **Environment variable fix** — All hooks now use `CLAUDE_PLUGIN_DATA` with proper fallback.

---

## [1.2.1] - 2026-03-28

### Fixed

- **Metrics DB migration** — Added 'info' severity to violations CHECK constraint. Auto-migrates existing tables.

---

## [1.2.0] - 2026-03-28

### Added

- **3-level code validation** — Hooks now enforce code rules with progressive analysis: regex (<50ms), static analysis (<2s), and architecture validation (<2s). Rules: PHP001-005, TS001-003, LAYER001-003.
- **Blocking hooks (exit 2)** — Critical violations now **block** Claude from proceeding. Code must be fixed before continuing. Warnings remain non-blocking.
- **Pre-write validation** — New PreToolUse hook (`pre-write-check.sh`) validates layer imports BEFORE file write, preventing architecture violations at the source.
- **Session metrics** — New SessionEnd hook (`session-metrics.sh`) records session summary (blocked/warned counts) to local SQLite database.
- **`/craftsman:metrics` command** — Quality dashboard showing violations by rule, daily trends (14 days), and session history. Queries local SQLite database.
- **`craftsman-ignore` syntax** — Suppress specific rules per-line or per-file with `// craftsman-ignore: RULE_ID` comments. Suppressed violations are still tracked in metrics.
- **Metrics database** — SQLite database at `${CLAUDE_PLUGIN_DATA}/metrics.db` records all violations with project hash (privacy), rule, severity, and blocked/ignored status.
- **Static analysis wrappers** — `hooks/lib/static-analysis.sh` wraps PHPStan, ESLint, deptrac, and dependency-cruiser with graceful degradation (returns empty if tools not installed).
- **Hook test suite** — `tests/hooks/test-hooks.sh` with 12 behavioral tests covering all rules and edge cases.

### Changed

- **post-write-check.sh** — Complete rewrite from warning-only (exit 0) to blocking (exit 2) with JSON structured output, craftsman-ignore support, metrics recording, and static analysis integration.
- **hooks.json** — Now registers 4 event hooks: PreToolUse, PostToolUse, UserPromptSubmit, SessionEnd.

### Removed

- **Duplicate scripts** — Removed `scripts/bias-detector.sh` and `scripts/post-write-check.sh` (canonical copies live in `hooks/`).

---

## [1.1.1] - 2025-02-06

### Added

- **`/craftsman:setup` command** - Interactive setup wizard that was documented but never implemented. Creates `~/.claude/.craft-config.yml` with user profile, bias protection, and pack selection.
- **DISC mini-assessment** - 4-question quick test for users who don't know their DISC profile. Options: "Je connais mon DISC", "Mini-test (4 questions)", or "Passer".

### Fixed

- **Setup wizard implementation** - The wizard specification existed in `setup/wizard.md` but was never converted to an invocable command. Now properly available as `/craftsman:setup`.
- **First-run detection** - `session-init` now checks if `~/.claude/.craft-config.yml` exists and displays appropriate warnings if setup hasn't been completed.
- **Pack activation gating** - Pack-specific commands (`entity`, `usecase`, `component`, `hook`) now verify that their respective pack is enabled before proceeding. Previously all commands were available regardless of configuration.

### Changed

- **session-init** - Now displays different content based on configuration state (setup required vs configured)
- **Pack commands** - Added requirement check at the beginning of `entity.md`, `usecase.md`, `component.md`, and `hook.md`

---

## [1.1.0] - 2025-02-05

### Fixed

- **Version synchronization** - `plugin.json` and `marketplace.json` now share the same version number. This fixes an issue where Claude Code cache wouldn't update because version mismatch between the two files.

### Changed

- Commands frontmatter simplified (removed `name:` field) - Claude Code auto-generates it during installation

---

## [1.0.0] - 2025-02-04

### Added

**20 Commands with `craftsman:*` namespace**

All skills use consistent `/craftsman:*` naming convention for better discoverability and ecosystem coherence.

**Core Methodology (10)**
- `/craftsman:design` - DDD design with challenge phases
- `/craftsman:debug` - Systematic debugging (ReAct pattern)
- `/craftsman:plan` - Structured planning & execution
- `/craftsman:challenge` - Architecture review
- `/craftsman:verify` - Evidence-based verification
- `/craftsman:spec` - Specification-first (TDD/BDD)
- `/craftsman:refactor` - Systematic refactoring
- `/craftsman:test` - Pragmatic testing
- `/craftsman:git` - Safe git workflow
- `/craftsman:parallel` - Parallel agent orchestration

**Symfony/PHP (2)**
- `/craftsman:entity` - DDD entity scaffolding
- `/craftsman:usecase` - Use case with command/handler

**React/TypeScript (2)**
- `/craftsman:component` - React component scaffolding
- `/craftsman:hook` - TanStack Query hook scaffolding

**AI/ML (4)**
- `/craftsman:rag` - RAG pipeline design
- `/craftsman:mlops` - MLOps audit
- `/craftsman:agent-design` - AI agent design (3P pattern)
- `/craftsman:source-verify` - Verify AI capabilities against official docs

**Utility (1)**
- `/craftsman:session-init` - Session initialization

**5 Specialized Agents**
- `architecture-reviewer` - Clean Architecture compliance
- `security-pentester` - Security vulnerability detection
- `symfony-reviewer` - Symfony/DDD best practices
- `react-reviewer` - React patterns and hooks
- `ai-reviewer` - RAG/MLOps/Agent best practices

**Hooks System**
- `bias-detector.sh` - Cognitive bias detection (UserPromptSubmit)
- `post-write-check.sh` - Code validation for Write|Edit tools

**Knowledge Base**
- Principles (SOLID, DRY, YAGNI, KISS)
- Patterns (DDD, Clean Architecture, Microservices)
- Canonical examples (PHP entities, TS components)
- Anti-patterns (Anemic domain, Prop drilling, Any type)
- AI-specific (RAG architecture, MLOps, Vector databases, 3P pattern)

**Optional MCP Server**
- `knowledge-rag` - Semantic search over local PDFs with Ollama embeddings

### Architecture

- **Consolidated structure**: Single `/skills/` directory for all skills
- **Single `/agents/` directory**: All reviewers in one place
- **Single `/knowledge/` directory**: All reference material centralized
- **Framework packs** contain only templates (no skill duplication)

---

## Links

- [GitHub Repository](https://github.com/BULDEE/ai-craftsman-superpowers)
- [Documentation](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs)
- [Issue Tracker](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
