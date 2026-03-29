# AI Craftsman Superpowers — Project Instructions

## Project Overview

Claude Code plugin that transforms Claude into a disciplined Senior Software Craftsman. DDD, Clean Architecture, TDD methodology enforced through hooks, commands, agents, and a rules engine.

**Current version:** 2.4.0
**Stack:** Bash (hooks/CI), Markdown (commands/agents/templates), Python (metrics helpers), YAML (config)

## Development Rules

- All hook scripts MUST use `exit 0` (pass) or `exit 2` (block). NEVER `exit 1`.
- Hook command output MUST be valid JSON (`jq -n` pattern).
- Agent hook prompts use `$ARGUMENTS` for tool input injection.
- The `metrics-query.py` helper MUST be used for all SQLite writes (parameterized queries). NEVER use string interpolation in SQL.
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

These are the unique selling points that differentiate AI Craftsman Superpowers from every other Claude Code plugin:

### 1. Iron Law Pattern
Every scaffolder command forces loading canonical examples BEFORE generating any code. This guarantees zero drift from project standards across sessions.

### 2. Cognitive Bias Detector
The only Claude Code plugin with real-time cognitive bias detection on user prompts. Detects: acceleration ("vite", "quick"), scope creep ("et aussi", "while we're at it"), sunk cost, anchoring, authority bias. Fires on UserPromptSubmit hook.

### 3. Correction Learning System
Records when users fix Claude-generated code patterns in a SQLite database. At next session start, recent correction trends are injected so Claude learns from past mistakes. Visible via `/craftsman:metrics`. This creates a feedback loop unique in the ecosystem.

### 4. Sub-3-Second Quality Gate
3-level validation on every Write/Edit:
- Level 1: Regex (<50ms) — strict_types, final, any, setters
- Level 2: Static analysis (<2s) — PHPStan, ESLint
- Level 3: Architecture (<2s) — deptrac, dependency-cruiser
Graceful degradation: works with zero tools installed (Level 1 only).

### 5. Rules Engine with 3-Level Inheritance
Enterprise-ready rule customization: Global → Project → Directory. Short form (`PHP001: warn`) and long form (custom rules with regex, message, severity, languages, paths). Legacy code coexists with strict new code.

### 6. Circuit Breaker for External Services
Production-grade pattern (closed → open → half-open) protecting Sentry integration. File-based cache with TTL/LRU eviction. Stale cache serving during outages.

### 7. Multi-Provider CI with Zero Drift
Same rules engine runs in hooks (real-time) AND CI (pipeline). 4 providers: GitHub Actions, GitLab CI, Bitbucket Pipelines, Jenkins. Adapter pattern: detect → run → annotate → comment → exit.

### 8. Metrics & Trend Analysis
SQLite-backed tracking of violations, corrections, and sessions. 7-day and 30-day trend views. Data-driven quality improvement: identify most-violated rules and adjust strictness.

### 9. 5 Core Agents + Pack Agents with Model Tiering
Sonnet (team-lead/craftsmen/reviewers) → Haiku (hooks). Cost-optimized: expensive models only where judgment is needed.

### 10. Atomic Commit Enforcement
Stop hook monitors file change count per session. Warns when >15 files modified, encouraging craftsman practice of small, focused commits.

## Architecture

```
hooks/              → Real-time validation (SessionStart → PostToolUse → Stop → SessionEnd)
hooks/lib/          → Shared libraries (pack-loader, config, rules-engine, metrics, static-analysis)
commands/           → Core user-invoked workflows (15 commands)
agents/             → Core agents (5) + pack symlinks
knowledge/          → Core methodology (DDD, Clean Architecture, patterns)
packs/              → Loadable language packs
  symfony/          → PHP/Symfony pack (validators, agents, knowledge, templates)
  react/            → React/TypeScript pack (validators, agents, knowledge, templates)
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
