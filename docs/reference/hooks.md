# Hooks Reference

The plugin uses Claude Code hooks to automatically enforce code quality rules. Hooks run as shell scripts triggered by Claude Code events.

## Hook Events

| Event | Hook | Purpose |
|-------|------|---------|
| PreToolUse | `pre-write-check.sh` | Validate content **before** file write (layer violations) |
| PostToolUse | `post-write-check.sh` | Validate file **after** write (all rules) |
| UserPromptSubmit | `bias-detector.sh` | Detect cognitive biases in prompts |
| SessionEnd | `session-metrics.sh` | Record session summary to metrics database |

## Exit Codes

| Code | Meaning | Effect |
|------|---------|--------|
| 0 | Pass / Warning | Operation proceeds. Warnings appear as `systemMessage`. |
| 2 | Block | Operation is **prevented**. Claude must fix the violation. |

> **Note:** Exit code 1 is reserved for script errors. Hooks use exit 2 for intentional blocking.

## Code Rules

### PHP Rules (PostToolUse)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| PHP001 | critical | `declare(strict_types=1)` in every PHP file | Yes |
| PHP002 | critical | All classes must be `final` | Yes |
| PHP003 | warning | No public setters (`public function set*`) | Yes |
| PHP004 | warning | No `new DateTime()` — use Clock abstraction | No (warning) |
| PHP005 | warning | No empty catch blocks | No (warning) |

### TypeScript Rules (PostToolUse)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| TS001 | critical | No `any` type annotations | Yes |
| TS002 | warning | No `export default` — use named exports | No (warning) |
| TS003 | warning | No non-null assertions (`!`) | No (warning) |

### Layer Rules (PreToolUse + PostToolUse)

| Rule | Severity | Check | Blocking |
|------|----------|-------|----------|
| LAYER001 | critical | Domain cannot import Infrastructure | Yes |
| LAYER002 | critical | Domain cannot import Presentation | Yes |
| LAYER003 | critical | Application cannot import Presentation | Yes |

Layer validation uses both file path detection (`*/Domain/*`) and namespace scanning (`namespace App\Domain`) to identify the architectural layer.

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

> **Important:** Ignored violations are still recorded in the metrics database with `ignored=1`. This ensures transparency — you can always see what was suppressed via `/craftsman:metrics`.

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
  "systemMessage": "⚠️ PHP004: Avoid new DateTime() — use Clock abstraction (line 42)"
}
```

## Metrics Database

All violations are recorded in a local SQLite database at:

```
${CLAUDE_PLUGIN_DATA}/metrics.db
```

Default location: `~/.claude/plugins/data/craftsman/metrics.db`

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

## Bias Detection

The `bias-detector.sh` hook (UserPromptSubmit) detects cognitive biases in your prompts:

| Bias | Trigger Keywords | Warning |
|------|-----------------|---------|
| Acceleration | "vite", "quick", "just do it" | STOP — Design first |
| Scope Creep | "et aussi", "while we're at it" | STOP — Is this in scope? |
| Over-Optimization | "abstraire", "generalize" | STOP — YAGNI |

Bias detection is **warning-only** (exit 0) — it never blocks your workflow.

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

# If not installed, Level 2/3 silently skip — this is by design
```

### Metrics database issues

```bash
# Check database location
echo "${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/craftsman}/metrics.db"

# Query directly
sqlite3 "$HOME/.claude/plugins/data/craftsman/metrics.db" "SELECT COUNT(*) FROM violations;"
```
