# Hooks Reference

The plugin uses Claude Code hooks to automatically enforce code quality rules. Hooks run as shell scripts and agent prompts triggered by Claude Code events.

**13 hook events wired**, documented below as two groups by what the hook checks: deterministic quality-gate scripts, and headless-Haiku semantic checks ([ADR-0018](../adr/0018-native-prompt-agent-hooks.md)).

## Hook Events

### Command Hooks

| Event | Hook | Purpose |
|-------|------|---------|
| SessionStart | `session-start.sh` | Initialization, config loading, first-run detection |
| PreToolUse | `config-protection.sh` | Refuse writes that would tamper with plugin configuration |
| PreToolUse | `pre-write-check.sh` | Validate content **before** file write (layer violations) |
| PreToolUse | `pre-push-verify.sh` | Validate git push commands for safety |
| PostToolUse | `post-write-check.sh` | Validate file **after** write (all rules) |
| PostToolUse | `post-bash-test-verify.sh` | Read recorded test runs; a failing run revokes verification evidence |
| PostToolUseFailure | `tool-failure-tracker.sh` | Record failed tool calls for correction learning |
| TaskCompleted | `task-completed-verify.sh` | Evidence gate: block a task from being marked complete without verification ([ADR-0023](../adr/0023-deterministic-verification-loop.md)) |
| UserPromptSubmit | `bias-detector.sh` | Detect cognitive biases in prompts |
| FileChanged | `file-changed.sh` | Track file modifications for correction learning |
| SubagentStop | `subagent-quality-gate.sh` | Apply the quality gate to work produced by a subagent |
| PreCompact | `pre-compact-save.sh` | Persist session state before context compaction |
| PostCompact | `post-compact-verify.sh` | Restore and re-verify state after compaction |
| SessionEnd | `session-metrics.sh` | Record session summary to metrics database |

All 13 wired events are listed above. `exit 2` blocks the action; `exit 0`
passes. Strictness (`strict` / `moderate` / `relaxed`) decides whether a given
finding blocks or only warns.

### Agent Hooks (v1.3.0+)

Agent hooks run AI models (Haiku) for semantic analysis beyond regex patterns:

| Event | Agent | Model | Purpose | Timeout |
|-------|-------|-------|---------|---------|
| PostToolUse | DDD Verifier | Haiku | Layer violations, aggregate boundaries, value objects, naming | 30s |
| InstructionsLoaded | Project Analyzer | Haiku | Architectural context map + correction trends + channel status | 20s |
| Stop | Sentry Context | Haiku | Error context from Sentry MCP for edited files | 30s |
| Stop | Final Reviewer | Haiku | Architecture validation before session end (strict mode only) | 30s |

**DDD Verifier** checks:
1. Layer violations (semantic, not just regex)
2. Aggregate boundary crossings
3. Missing Value Objects (primitive obsession)
4. Non-domain naming in Domain layer

**Project Analyzer** builds at session start:
1. Bounded contexts map (from namespaces/directories)
2. Available Value Objects inventory
3. Aggregate roots identified
4. Correction trends (30-day window)
5. Active channels status

**Final Reviewer** (strict mode only):
1. Layer violations in changed files
2. Missing tests for new classes
3. Returns `block` decision if critical issues found

## Exit Codes

| Code | Meaning | Effect |
|------|---------|--------|
| 0 | Pass / Warning | Operation proceeds. Warnings appear as `systemMessage`. |
| 2 | Block | Operation is **prevented**. Claude must fix the violation. |

> **Note:** Exit code 1 is reserved for script errors. Hooks use exit 2 for intentional blocking.

## Security Invariant Tests (v3.8.0+)

`tests/core/test-security-invariants.sh` proves - rather than assumes - that `config-protection.sh` and `pre-write-check.sh` never execute arbitrary code or touch the filesystem outside their contract, even when fed adversarial `file_path`/`content` values (command substitution, path traversal, shell metacharacters, malformed non-JSON stdin). Sandbox + witness-marker pattern: a marker file is planted, the hook is fed a payload designed to delete or alter it, and the test asserts the marker is untouched. Also verifies both hooks fail open (exit 0) on malformed input rather than crashing into an undefined state.

Note: there is no hook that blocks destructive shell commands (`git reset --hard`, `rm -rf`) at the tool-execution level today - `/craftsman:git`'s destructive-command guidance is a prompt-level convention Claude follows, not code that intercepts Bash execution. This test suite covers what's actually enforceable in code: the Write/Edit quality-gate hooks.

## Config Protection (v3.8.0+)

`config-protection.sh` (PreToolUse, Write|Edit) blocks writes to single-purpose linter/formatter/architecture config files - `phpstan.neon(.dist)`, `.eslintrc*`, `eslint.config.*`, `.php-cs-fixer(.dist).php`, `deptrac.y(a)ml`, `.dependency-cruiser.*` - so an agent can't silently loosen a rule instead of fixing the code that violates it.

`.craft-config.yml`/`.craft-rules.yml` are intentionally excluded - they're the user-facing rule override mechanism (see Custom Rule Engine) and `/craftsman:setup` writes to them by design. Multi-purpose files (`pyproject.toml`, `package.json`) are excluded too - too much unrelated project metadata to block wholesale.

Blocks with exit 2. Escape hatch: `CRAFTSMAN_DISABLED_HOOKS=config-protection` for a session where a genuine config change is intended.

## Hook Profiles (v3.8.0+)

Secondary and costed hooks - the 4 agent hooks plus `post-bash-test-verify.sh`, `tool-failure-tracker.sh`, `subagent-quality-gate.sh`, `file-changed.sh`, `pre-push-verify.sh` - can be skipped for a session via environment variables, without touching plugin config:

```bash
# Turn off all secondary/costed hooks for this session
export CRAFTSMAN_HOOK_PROFILE=minimal

# Or disable specific hooks by id, regardless of profile
export CRAFTSMAN_DISABLED_HOOKS=file-changed,tool-failure-tracker

# See what a profile would skip without actually skipping anything
export CRAFTSMAN_HOOK_DRY_RUN=true
```

`CRAFTSMAN_HOOK_PROFILE` defaults to `standard` (current full behavior, no change from prior versions). `strict` currently behaves like `standard` - reserved for future stricter tiers. The core quality gate (`pre-write-check.sh`, `post-write-check.sh`), bias detection, and session bookkeeping (`session-start.sh`, `session-metrics.sh`, `pre-compact-save.sh`, `post-compact-verify.sh`) intentionally do not support `CRAFTSMAN_HOOK_PROFILE`/`CRAFTSMAN_DISABLED_HOOKS` at all - disabling them would silently turn off the plugin's core value or lose session state, so that's a deliberate boundary, not a gap. Disable them via the `agent_hooks`/`strictness` plugin config instead, or the `/plugin` hooks toggle.

## Code Rules

### PHP Rules (PostToolUse)

`Blocking` below is the behaviour under the default `strict` strictness. An
advisory rule warns whatever the strictness is; set `RULE: block` in
`.craft-config.yml` to enforce one.

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| PHP001 | critical | `declare(strict_types=1)` in every PHP file | Yes |
| PHP002 | critical | All classes must be `final`, except a Doctrine entity | Yes |
| PHP003 | advisory | No public setters (`public function set*`) | No (warning) |
| PHP004 | critical | No `new DateTime()` - use Clock abstraction | Yes |
| PHP005 | advisory | No empty catch blocks | No (warning) |

PHP002 skips a class carrying `#[ORM\Entity]` or `@ORM\Entity`: a Doctrine
proxy extends the entity, so a final entity breaks lazy loading.

### TypeScript Rules (PostToolUse)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| TS001 | critical | No `any` type annotations | Yes |
| TS002 | advisory | No `export default` - use named exports | No (warning) |
| TS003 | advisory | No non-null assertions (`!`) | No (warning) |

TS002 skips the files a framework resolves by their default export: `page`,
`layout`, `route`, `middleware`, `loading`, `error`, `not-found`, `template`,
`default`, `instrumentation`, anything under `pages/`, `*.stories.*`,
`*.config.*` and `*.d.ts`. Both rules take a line-level
`// craftsman-ignore: TS002` / `TS003`.

### Layer Rules (PreToolUse + PostToolUse)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| LAYER001 | critical | Domain cannot import Infrastructure | Yes |
| LAYER002 | critical | Domain cannot import Presentation | Yes |
| LAYER003 | critical | Application cannot import Presentation | Yes |
| LAYER004 | critical | Domain cannot contain raw SQL/DQL (PHP) or import a database client (TS) | Yes |

Layer validation uses both file path detection (`*/Domain/*`) and namespace
scanning to identify the architectural layer. The root namespace comes from
`composer.json` (`autoload.psr-4`, preferring the entry mapped to `src/`), so a
project that renamed its root is still checked; `App` is the fallback when
there is no `composer.json` to read.

### Persistence Rules (PostToolUse + CI)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| DB001 | warning | No `SELECT *` - name the columns you need | No (warning) |
| DB002 | warning | Migration with `up()` must have `down()` | No (warning) |
| DB003 | warning | Query call inside a loop (N+1 heuristic) | No (warning) |

### Structural Ratchet (PostToolUse + CI)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| RATCHET001 | advisory | A touched file must not regress its committed structural baseline (complexity, file lines, longest function, import fan-out, suppression count) | No by default; set `RATCHET001: block` to enforce |

The baseline lives in `.craftsman-baseline.json` at the repository root, is committed, and only moves one way: a green pass tightens it, nothing loosens it except a documented `craftsman-ignore` (itself counted and ratcheted). Untouched files and relaxed directories are never evaluated. See [ADR-0025](../adr/0025-structural-ratchet.md).

### Security Rules (PostToolUse + CI)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| SEC001 | critical | Hardcoded secret (API key, token, password literal, private key block) | Yes |
| SEC002 | critical | Dynamic eval/exec on non-literal input | Yes |
| SEC003 | critical | SQL built by concatenation or template interpolation | Yes |

Reads from the environment (`getenv`, `$_ENV`, `process.env`, `import.meta.env`) and parameterized queries are explicitly safe. Doctrine: [`knowledge/security/secure-by-design.md`](../../knowledge/security/secure-by-design.md).

Persistence validation ships with the symfony and react packs and runs through the same validators in hooks and CI. The reasoning behind each rule lives in [`knowledge/persistence/`](../../knowledge/persistence/): repository boundaries, migration discipline, storage choice, and read/write separation.

## 3-Level Validation

Hooks implement a progressive validation strategy:

### Level 1: Fast Regex (<50ms)

Runs on every write. Pattern-matches code for common violations (PHP001-005, TS001-003, LAYER001-003). Zero dependencies.

### Level 2: Static Analysis (<2s)

Runs PHPStan (PHP) or ESLint (TypeScript) if installed. **Graceful degradation:** if tools are not installed, this level is silently skipped.

### Level 3: Architecture Validation (<2s)

Runs deptrac (PHP) or dependency-cruiser (TypeScript) if installed. Same graceful degradation as Level 2.

## Suppressing Rules: `craftsman-ignore`

Add an inline comment to suppress a specific rule for that line:

```php
// craftsman-ignore: PHP003
public function setName(string $name): void { ... }
```

Or suppress multiple rules:

```php
// craftsman-ignore: PHP003, PHP005
```

**File-level suppression:** Add at the top of the file to suppress a rule for the entire file:

```php
<?php
// craftsman-ignore: PHP002
```

> **Important:** Ignored violations are still recorded in the metrics database with `ignored=1`. This ensures transparency - you can always see what was suppressed via `/craftsman:metrics`.

## JSON Output Format

When a hook blocks (exit 2), it outputs structured JSON:

```json
{
  "hookSpecificOutput": {
    "violations": [
      {
        "rule": "PHP001",
        "severity": "critical",
        "message": "Missing declare(strict_types=1)"
      }
    ],
    "file": "src/Domain/Entity/User.php",
    "blocked": true,
    "total_violations": 1
  }
}
```

When a hook warns (exit 0), it uses `systemMessage`:

```json
{
  "systemMessage": "⚠️ PHP004: Avoid new DateTime() - use Clock abstraction (line 42)"
}
```

## Metrics Database

All violations are recorded in a local SQLite database at:

```
${CLAUDE_PLUGIN_DATA}/metrics.db
```

`CLAUDE_PLUGIN_DATA` carries the plugin slug, so the real path is usually
`~/.claude/plugins/data/craftsman-<marketplace-slug>/metrics.db`. The bare
`~/.claude/plugins/data/craftsman/metrics.db` is only the fallback used when the
variable is unset, and it may hold stale history from an earlier slug.

Anything running via the Bash tool (skills, one-off queries) has no
`CLAUDE_PLUGIN_DATA`, so it must read the resolved path from the bridge file
`~/.claude/craftsman-metrics-db-path` written at session start. Hardcoding the
fallback there reads a database no hook writes to.

### Schema

**violations table:**

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Auto-increment primary key |
| timestamp | TEXT | ISO 8601 timestamp |
| project_hash | TEXT | SHA-256 of project path (privacy) |
| file_pattern | TEXT | Anonymized file pattern (e.g., `*.php`) |
| rule | TEXT | Rule ID (e.g., `PHP001`) |
| severity | TEXT | `critical` or `warning` |
| blocked | INTEGER | 1 if blocked, 0 if warning |
| ignored | INTEGER | 1 if suppressed by craftsman-ignore |

**sessions table:**

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Auto-increment primary key |
| timestamp | TEXT | ISO 8601 timestamp |
| project_hash | TEXT | SHA-256 of project path |
| duration_seconds | INTEGER | Session duration |
| violations_blocked | INTEGER | Count of blocked violations |
| violations_warned | INTEGER | Count of warnings |

### Viewing Metrics

Use the `/craftsman:metrics` command to view a formatted dashboard:

```
/craftsman:metrics
```

This shows violations by rule, daily trends (14 days), and session history.

## Custom Rule Engine (v2.1.0+)

Rules can be overridden per-project using `.craft-config.yml`:

```yaml
rules:
  PHP001: block     # Keep strict
  PHP002: warn      # Allow non-final during migration
  TS001: ignore     # Legacy codebase
```

Three-level inheritance: Global → Project → Directory. See CLAUDE.md for details.

## Schema Validation (v2.2.0+)

At session start, `session-start.sh` validates all hook event names in `hooks.json` against the supported set:

`SessionStart`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `FileChanged`, `InstructionsLoaded`, `Stop`, `SessionEnd`

Unsupported events trigger a `SCHEMA WARNING` in the session startup message.

## Atomic Commit Enforcement (v2.2.0+)

The Stop hook's Final Reviewer agent monitors file changes per session:
- If >20 files changed: inspects only the first 20
- If >15 files changed: adds an `[ATOMIC COMMITS]` reminder encouraging small, focused commits

## Monorepo Safety (v2.2.0+)

The InstructionsLoaded agent applies sampling for large codebases:
- If any `src/` Glob returns >100 results: switches to directory-level analysis (file counts per subdirectory)
- Caps file Read to 3 representative files maximum
- Limits Value Object and Aggregate root listings to 10 each

## Bias Detection

The `bias-detector.sh` hook (UserPromptSubmit) detects cognitive biases in your prompts through a two-stage cascade (ADR-0030). Patterns live in `hooks/lib/bias-patterns/<lang>.conf`, one data file per language; adding a language edits no code.

| Bias | Curated English triggers | Signal lexemes (every other language) | Curated warning |
|------|--------------------------|---------------------------------------|-----------------|
| Acceleration | "just do it", "skip the tests", "asap" | fais vite, hazlo rápido, schnell, 快点, 빨리 해, hızlı yap, быстро сделай | "Acceleration bias: You may be rushing" |
| Scope Creep | "while we're at it, add", "let's also add" | et aussi ajoute, y además agrega, ついでに, 顺便, hazır başlamışken | "Scope Creep bias: Adding features beyond scope" |
| Over-Optimization | "make it generic", "future-proof" | abstraire, hazlo configurable, 汎用化, geleceğe dönük, на будущее | "Over-Optimization bias: Premature abstraction" |

**Stage 1, the hook.** English is the one curated language: it carries context-aware regex whose precision is earned and reviewed, so a match warns you directly through `systemMessage`. Every other language sits at the same tier behind it, French and Spanish included, carrying recall-oriented lexeme lists: word lists tuned to catch the signal, not to avoid false alarms. That single dividing line is deliberate. Curating a language means a maintainer who reads it can review its precision, and the alternative, a shifting handful of privileged languages, is an artifact of contribution history rather than a design.

Language tags are BCP 47 (RFC 5646). A bare subtag is a valid tag, so the shipped files are `fr.conf` and `zh.conf`; when a dialect actually diverges, `fr-CA.conf`, `pt-BR.conf` or `zh-Hant.conf` register exactly the same way. That is a question of evidence, not of naming: add the subtag when a lexeme differs, not before.

**Stage 2, the model already reading your prompt.** A signal-tier match is not a verdict and never reaches you as a warning. The hook prints a plain-stdout adjudication note naming the matched lexeme, which UserPromptSubmit hands to the main model as conversation context. That model has the whole session, so it decides: real acceleration after no design work becomes a warning phrased in your language, while an incidental match (quoted text, a topic being discussed, descriptive use) is dismissed silently and never mentioned. No second model, no subprocess, no API call, no network access is involved at any point; stage 2 is the model that was going to read the prompt anyway, so the marginal cost is zero.

That is what makes signal-tier recall cheap: a false positive there is invisible, whereas a curated false positive is a warning you see. The two output formats are mutually exclusive, and a curated warning suppresses every signal note in the same run.

Signal matching is case-sensitive on purpose, so patterns declare their case variants explicitly (`[Ss]chnell`, `(быстро|Быстро)`). `grep -i` folding is locale-dependent beyond ASCII: `RÉFLÉCHIR` matches `réfléchir` under `fr_FR.UTF-8` and does not under `LC_ALL=C`, which a CI runner may well use. Scripts without case, CJK and Thai among them, need no variants and are matched as substrings, because those languages write without spaces and word boundaries do not apply.

Adding a language is two data files and zero code: `hooks/lib/bias-patterns/<lang>.conf` for the lexemes and `tests/fixtures/bias/<lang>.cases` for the behavior cases. No hook, helper or test script changes.

Bias detection is **warning-only** (exit 0) - it never blocks your workflow.

## Iron Law Pattern (v2.1.0+)

Design-first methodology enforced through hooks, not just requested in a prompt: the `bias-detector.sh` hook warns when domain entities are being modeled without a prior `/craftsman:design` invocation in the session. This prevents impulsive architecture changes - jumping straight to implementation before the design phase has challenged the model.

## Circuit Breaker (v2.1.0+)

Production-grade protection for external service calls (Sentry MCP), implemented in `hooks/lib/circuit-breaker.sh`:

- **3 states:** `closed` (normal operation) → `open` (service failing, calls short-circuited) → `half-open` (probing recovery)
- **File-based cache** with TTL/LRU eviction serves stale data during outages instead of blocking on a dead dependency
- Applies to any hook that calls out to Sentry for error context (`agent-sentry-context.sh`)

## Troubleshooting

### Hook not triggering

```bash
# Verify hooks.json is valid
python3 -c "import json; json.load(open('hooks/hooks.json'))"

# Check hook is executable
ls -la hooks/post-write-check.sh
chmod +x hooks/*.sh
```

### Static analysis not running

```bash
# Check if tools are installed
which phpstan    # PHP
which eslint     # TypeScript
which deptrac    # Architecture (PHP)

# If not installed, Level 2/3 silently skip - this is by design
```

### Metrics database issues

```bash
# Check database location
echo "${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/craftsman}/metrics.db"

# Query directly (from a shell without CLAUDE_PLUGIN_DATA, e.g. the Bash tool)
sqlite3 "$(cat ~/.claude/craftsman-metrics-db-path)" "SELECT COUNT(*) FROM violations;"
```
