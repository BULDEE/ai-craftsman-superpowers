# AI Craftsman Superpowers - Project Instructions

## Project Overview

Claude Code plugin that transforms Claude into a disciplined Senior Software Craftsman. DDD, Clean Architecture, TDD methodology enforced through hooks, commands, agents, and a rules engine.

**Current version:** 4.0.0
**Stack:** Bash (hooks/CI), Markdown (skills/agents/templates), Python (metrics helpers), YAML (config)

## Development Rules

- All hook scripts MUST use `exit 0` (pass) or `exit 2` (block). NEVER `exit 1`.
- Hook command output MUST be valid JSON (`jq -n` pattern).
- Semantic verification runs in headless Haiku subprocesses via `hooks/lib/haiku-verify.sh` (never native agent/prompt hook types: no option gating, see ADR-0018). Always guard with `CRAFTSMAN_HEADLESS_VERIFY`.
- The `metrics-query.py` helper MUST be used for all SQLite writes (parameterized queries). NEVER use string interpolation in SQL.
- All writes to `session-state.json` MUST use atomic writes (`tempfile.mkstemp() + os.rename()`). Known TOCTOU window between read and rename when multiple async hooks fire simultaneously - acceptable at current hook frequencies but do not add file-locking without benchmarking first.
- CI adapters follow the `adapter_detect/run/annotate/comment/exit` interface.
- All commands MUST have `description`, `effort` in frontmatter. `effort` is Claude Code's own frontmatter key, not project metadata: it overrides the session effort level, so only `low`, `medium`, `high`, `xhigh`, `max` are valid.
- Templates MUST have: top-level heading, `## Mission` section, `## Context Files` section.
- A skill with `disable-model-invocation: true` starts ONLY when the user types `/craftsman:<name>` first in a prompt; the Skill tool refuses it. So: an agent's `skills:` frontmatter may list only model-invocable skills and never one whose `agent:` binding points back at that agent; a skill body may write `**Invokes:** /craftsman:x` only when `x` is model-invocable, otherwise `**Hands off to:**` plus the command to paste. `tests/core/test-invocation-policy.sh` enforces both.

## Testing

```bash
# Run full test suite
bash tests/run-tests.sh

# Run hook tests only
bash tests/core/test-hooks.sh

# Run template validation only
bash tests/templates/test-templates.sh
```

## Key Differentiators (Marketing)

These are the 6 genuine features that differentiate AI Craftsman Superpowers:

### 1. Correction Learning System
Records every violation fix users make, injects correction trends at next session start, and promotes recurring fixes into human-reviewed learned skills. SQLite-backed feedback loop that progressively teaches Claude the exact patterns your codebase rejects. Cross-file pattern detection suggests project-wide fixes when 3+ files share the same violation. Differentiator: the learning loop is coupled to the rules engine, so what is learned comes from violations that same engine enforces in hooks and in CI, not from a separate model of what good code looks like.

### 2. Rules Engine with 3-Level Inheritance
Enterprise-ready rule customization: Global → Project → Directory overrides. Short form (`PHP001: warn`) and long form (custom rules with regex, message, severity, languages, paths). Legacy code coexists with strict new code via directory-level relaxation. Python-backed YAML parser with bash 3.2 shell compatibility.

### 3. Cognitive Bias Detector
Real-time detection of acceleration bias, scope creep, and over-optimization in user prompts. Context-aware bilingual FR/EN pattern matching on UserPromptSubmit hook - requires imperative verb context to reduce false positives. Non-blocking warnings that encourage reflection before action.

### 4. Real-Time Quality Gate
3-level progressive validation on every Write/Edit:
- Level 1: Regex (<50ms) - strict_types, final, any, setters. Always active.
- Level 2: Static analysis (<2s) - PHPStan, ESLint. When tools installed.
- Level 3: Architecture (<2s) - deptrac, dependency-cruiser. When tools installed.
Graceful degradation: works with zero tools installed (Level 1 only).

### 5. Multi-Provider CI Pipeline
CI sources the same pack validators and the same rules engine as the hooks, and resolves severity per file so directory-level `.craft-rules.yml` applies in both. tests/ci/test-craftsman-ci.sh fails when the two disagree. 4 provider templates: GitHub Actions, GitLab CI, Bitbucket Pipelines, Jenkins; the first three get native annotations, Jenkins runs through the generic adapter. Adapter pattern: detect → run → annotate → comment → exit.

### 6. Metrics & Trend Analysis
SQLite-backed tracking of violations, corrections, and sessions. 7-day and 30-day trend views. Data-driven quality improvement: identify most-violated rules and adjust strictness. Currently per-machine - team metrics sync planned for v3.

## Architecture

```
hooks/              → Real-time validation (SessionStart → PostToolUse → Stop → SessionEnd)
hooks/lib/          → Shared libraries (pack-loader, config, rules-engine, metrics, static-analysis)
skills/             → Core workflows as skills/<name>/SKILL.md (ADR-0017); pack workflows symlinked in at runtime
agents/             → Core agents (11) + pack symlinks
knowledge/          → Core methodology, language-agnostic (Clean Architecture, Hexagonal, DDD, TDD, testing strategy, Clean Code, Refactoring, legacy techniques, Design Patterns, principles, anti-patterns)
knowledge/ddd/      → Agnostic DDD tactical/CQRS (Symfony specifics live in packs/symfony/knowledge/ddd-symfony-implementation.md)
knowledge/legacy/, knowledge/refactoring/ → Legacy rescue and refactoring campaign methodology
packs/              → Loadable language packs (5 packs)
  symfony/          → PHP/Symfony pack (validators, agents, knowledge, templates)
  react/            → React/TypeScript pack (validators, agents, knowledge, templates)
  python/           → Python pack (validators, knowledge, anti-patterns)
  bash/             → Bash/Shell pack (validators, knowledge, anti-patterns)
  ai-ml/            → AI/ML pack (agents, knowledge, commands)
ci/                 → CI pipeline integration; ci/adapters/ = CI providers
adapters/           → host agent runtimes (a different axis from ci/adapters/)
  hermes/           → Nous Research Hermes: pre_verify hook, Claude Code wrapper
```

Three front-ends over one core: `hooks/` for Claude Code, `ci/craftsman-ci.sh`
for pipelines, `adapters/<host>/` for other agent runtimes. The rules engine,
the packs and `knowledge/` are shared, and the parity tests fail when two
front-ends disagree on a severity. A fourth front-end is an adapter, never a
fork.

## Version Sync Checklist

When bumping version, update ALL of these:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → root `version` + plugin `version`
- `ci/craftsman-ci.sh` → `VERSION=`
- `CHANGELOG.md` → new entry
- `README.md` → Version badge
- `README.fr.md` → Version badge + sync any README.md content changes (French mirror, English is the source of truth)
