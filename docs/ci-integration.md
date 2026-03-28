# CI Integration

Craftsman quality rules run as Claude Code hooks during development. For CI/CD pipelines, the same rules are available via the standalone `craftsman-ci` CLI and a ready-made GitHub Actions workflow.

## Quick Start

Run inside your project root (where `ci/craftsman-ci.sh` lives):

```bash
# Scan src/ with default settings (strict, fullstack)
bash ci/craftsman-ci.sh

# JSON output for machine consumption
bash ci/craftsman-ci.sh --format json > report.json

# Scan specific paths
bash ci/craftsman-ci.sh src/Domain/ src/Application/
```

Or use the `/craftsman:ci` skill to export a GitHub Actions workflow:

```
/craftsman:ci export
/craftsman:ci status
```

## Configuration Options

`craftsman-ci` reads configuration with the same priority order as the Claude Code hooks:

1. `--config <file>` flag (highest)
2. `.craft-config.yml` in the current directory
3. `CLAUDE_PLUGIN_OPTION_*` environment variables
4. Hardcoded defaults (lowest)

### `.craft-config.yml`

```yaml
strictness: strict   # strict | moderate | relaxed
stack: fullstack     # symfony | react | fullstack | other
```

### Strictness levels

| Level | PHP rules | TS rules | Layer rules |
|-------|-----------|----------|-------------|
| `strict` | blocking | blocking | blocking |
| `moderate` | warnings | warnings | blocking |
| `relaxed` | warnings | warnings | warnings |

### Stack values

| Stack | PHP scanned | TypeScript scanned |
|-------|-------------|-------------------|
| `symfony` | yes | no |
| `react` | no | yes |
| `fullstack` | yes | yes |
| `other` | no | no |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Clean — no violations, no warnings |
| `1` | Warnings only |
| `2` | Violations found |

These follow standard CI conventions (compatible with `make`, GitHub Actions `if: failure()`, etc.).

## GitHub Actions Integration

### Export the workflow

```
/craftsman:ci export
```

This generates `.github/workflows/craftsman-quality-gate.yml` from the template at `ci/templates/craftsman-quality-gate.yml`.

### Workflow behavior

The workflow:
- Triggers on pull requests and pushes to `main`
- Auto-detects stack from `composer.json` / `package.json`
- Runs PHPStan level 8 if available
- Runs ESLint if available
- Runs deptrac if available
- Runs `craftsman-ci` and saves a JSON report
- Posts results as a PR comment (updates existing comment on re-runs)
- Fails the job if any violations are found

### Minimal manual setup

```yaml
# .github/workflows/craftsman-quality-gate.yml
name: Craftsman Quality Gate
on:
  pull_request:
  push:
    branches: [main]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run craftsman-ci
        run: bash ci/craftsman-ci.sh --format json > craftsman-report.json
      - name: Check violations
        run: |
          violations=$(jq '.summary.violations' craftsman-report.json)
          [ "$violations" -gt 0 ] && exit 1 || exit 0
```

## Custom CI Pipeline Integration

### GitLab CI

```yaml
craftsman:
  stage: quality
  script:
    - bash ci/craftsman-ci.sh --format json | tee craftsman-report.json
    - violations=$(jq '.summary.violations' craftsman-report.json)
    - "[ \"$violations\" -gt 0 ] && exit 1 || exit 0"
  artifacts:
    reports:
      junit: craftsman-report.json
    paths:
      - craftsman-report.json
    when: always
```

### Bitbucket Pipelines

```yaml
pipelines:
  pull-requests:
    '**':
      - step:
          name: Craftsman Quality Gate
          script:
            - bash ci/craftsman-ci.sh --format json > craftsman-report.json
            - violations=$(jq '.summary.violations' craftsman-report.json)
            - "[ \"$violations\" -gt 0 ] && exit 1 || exit 0"
          artifacts:
            - craftsman-report.json
```

### Pre-push Git hook

```bash
#!/usr/bin/env bash
# .git/hooks/pre-push
bash ci/craftsman-ci.sh --format text
```

## JSON Output Schema Reference

```json
{
  "version": "2.0.0",
  "timestamp": "2026-03-28T21:00:00Z",
  "config": {
    "strictness": "strict",
    "stack": "fullstack"
  },
  "summary": {
    "files_scanned": 42,
    "violations": 3,
    "warnings": 5
  },
  "violations": [
    {
      "rule": "PHP001",
      "file": "src/Domain/Entity/User.php",
      "line": 1,
      "message": "Missing declare(strict_types=1)",
      "severity": "critical"
    }
  ]
}
```

### Severity values

| Value | Description |
|-------|-------------|
| `critical` | Blocking violation (exit 2) |
| `warning` | Non-blocking warning (exit 1) |

### Rule codes

| Rule | Language | Description |
|------|----------|-------------|
| `PHP001` | PHP | Missing `declare(strict_types=1)` |
| `PHP002` | PHP | Non-final class |
| `PHP003` | PHP | Public setter method |
| `PHP004` | PHP | `new DateTime()` usage |
| `PHP005` | PHP | Empty catch block (warning) |
| `TS001` | TypeScript | `any` type usage |
| `TS002` | TypeScript | Default export |
| `TS003` | TypeScript | Non-null assertion `!` |
| `LAYER001` | PHP/TS | Domain imports Infrastructure |
| `LAYER002` | PHP | Domain imports Presentation |
| `LAYER003` | PHP | Application imports Presentation |
| `WARN-PHP001` | PHP | Method with 4+ parameters (warning) |
| `WARN-TS001` | TypeScript | Function with 4+ parameters (warning) |

## Suppressing Rules

Use `craftsman-ignore` comments in source files (identical to hook behavior):

```php
// craftsman-ignore: no-setter
public function setLegacyField(string $value): void { ... }
```

```typescript
const data = legacyApi() as any; // craftsman-ignore: no-any
```

Note: `craftsman-ignore` suppresses inline violations. File-level rules (like PHP001) require fixing the actual issue.
