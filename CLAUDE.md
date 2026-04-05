# AI Craftsman Superpowers — Project Instructions

## Project Overview

Claude Code plugin that transforms Claude into a disciplined Senior Software Craftsman. DDD, Clean Architecture, TDD methodology enforced through hooks, commands, agents, and a rules engine.

**Current version:** 3.3.2
**Stack:** Bash (hooks/CI), Markdown (commands/agents/templates), Python (metrics helpers), YAML (config)

## Development Rules

- All hook scripts MUST use `exit 0` (pass) or `exit 2` (block). NEVER `exit 1`.
- Hook command output MUST be valid JSON (`jq -n` pattern).
- Agent hook prompts use `$ARGUMENTS` for tool input injection.
- The `metrics-query.py` helper MUST be used for all SQLite writes (parameterized queries). NEVER use string interpolation in SQL.
- All writes to `session-state.json` MUST use atomic writes (`tempfile.mkstemp() + os.rename()`). Known TOCTOU window between read and rename when multiple async hooks fire simultaneously — acceptable at current hook frequencies but do not add file-locking without benchmarking first.
- CI adapters follow the `adapter_detect/run/annotate/comment/exit` interface.
- All commands MUST have `description`, `effort` (quick/medium/heavy) in frontmatter.
- Templates MUST have: top-level heading, `## Mission` section, `## Context Files` section.

## Testing

```bash
# Run full test suite
bash tests/run-tests.sh

# Run hook tests only
bash tests/hooks/test-hooks.sh

# Run template validation only
bash tests/templates/test-templates.sh
```

## Key Differentiators (Marketing)

These are the 6 genuine features that differentiate AI Craftsman Superpowers:

### 1. Correction Learning System
Records every violation fix users make and injects correction trends at next session start. SQLite-backed feedback loop that progressively teaches Claude the exact patterns your codebase rejects. Cross-file pattern detection suggests project-wide fixes when 3+ files share the same violation. Unique in the ecosystem — no other Claude Code plugin creates this behavioral feedback loop.

### 2. Rules Engine with 3-Level Inheritance
Enterprise-ready rule customization: Global → Project → Directory overrides. Short form (`PHP001: warn`) and long form (custom rules with regex, message, severity, languages, paths). Legacy code coexists with strict new code via directory-level relaxation. Python-backed YAML parser with bash 3.2 shell compatibility.

### 3. Cognitive Bias Detector
Real-time detection of acceleration bias, scope creep, and over-optimization in user prompts. Context-aware bilingual FR/EN pattern matching on UserPromptSubmit hook — requires imperative verb context to reduce false positives. Non-blocking warnings that encourage reflection before action.

### 4. Real-Time Quality Gate
3-level progressive validation on every Write/Edit:
- Level 1: Regex (<50ms) — strict_types, final, any, setters. Always active.
- Level 2: Static analysis (<2s) — PHPStan, ESLint. When tools installed.
- Level 3: Architecture (<2s) — deptrac, dependency-cruiser. When tools installed.
Graceful degradation: works with zero tools installed (Level 1 only).

### 5. Multi-Provider CI Pipeline
Same rules engine runs in hooks (real-time) AND CI (pipeline) with zero drift — CI sources the same pack validators as hooks. 4 providers: GitHub Actions, GitLab CI, Bitbucket Pipelines, Jenkins. Adapter pattern: detect → run → annotate → comment → exit.

### 6. Metrics & Trend Analysis
SQLite-backed tracking of violations, corrections, and sessions. 7-day and 30-day trend views. Data-driven quality improvement: identify most-violated rules and adjust strictness. Currently per-machine — team metrics sync planned for v3.

## Architecture

```
hooks/              → Real-time validation (SessionStart → PostToolUse → Stop → SessionEnd)
hooks/lib/          → Shared libraries (pack-loader, config, rules-engine, metrics, static-analysis)
commands/           → Core user-invoked workflows (20 skills)
agents/             → Core agents (11) + pack symlinks
knowledge/          → Core methodology (DDD, Clean Architecture, Clean Code, Refactoring, Design Patterns)
packs/              → Loadable language packs (5 packs)
  symfony/          → PHP/Symfony pack (validators, agents, knowledge, templates)
  react/            → React/TypeScript pack (validators, agents, knowledge, templates)
  python/           → Python pack (validators, knowledge, anti-patterns)
  bash/             → Bash/Shell pack (validators, knowledge, anti-patterns)
  ai-ml/            → AI/ML pack (agents, knowledge, commands)
ci/                 → CI pipeline integration (adapter pattern)
```

## Version Sync Checklist

When bumping version, update ALL of these:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → root `version` + plugin `version`
- `ci/craftsman-ci.sh` → `VERSION=`
- `CHANGELOG.md` → new entry
- `README.md` → Version badge
