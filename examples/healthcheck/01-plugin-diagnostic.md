# Example: Plugin Diagnostic for Missing PHPStan

## Prompt

```
/craftsman:healthcheck
PHPStan never triggers when I save PHP files. What is wrong?
```

## Expected Behavior

### Phase 1: Environment Scan

```markdown
## Plugin Diagnostic

### Core Plugin
- Plugin version: 3.1.0
- Plugin loaded: yes
- Hooks registered: 8/8

### Hook Status
| Hook                  | Status | Latency |
|-----------------------|--------|---------|
| post-write-check.sh   | active | 42ms    |
| bias-detector.sh       | active | 18ms    |
| session-metrics.sh     | active | 31ms    |
| subagent-quality-gate  | active | 27ms    |

### Pack Detection
- symfony pack: loaded
- react pack: loaded
```

### Phase 2: Root Cause Analysis

```markdown
## PHPStan Analysis

**Level 2 static analysis is configured but not executing.**

### Checks Performed
1. PHPStan binary lookup: `vendor/bin/phpstan` -- **not found**
2. Global install: `~/.composer/vendor/bin/phpstan` -- not found
3. `phpstan.neon` config: `./phpstan.neon` -- present
4. Pack validator: symfony pack expects `vendor/bin/phpstan`

### Root Cause
PHPStan is not installed. The quality gate degrades gracefully to Level 1 (regex only) when static analysis tools are missing.

### Fix
```

```bash
composer require --dev phpstan/phpstan phpstan/phpstan-symfony
```

### Phase 3: Post-Fix Verification

```markdown
## After Installing PHPStan

### Re-scan
- `vendor/bin/phpstan` -- found (v2.1.0)
- Level 2 validation: **active**
- Test run on `src/Domain/Entity/User.php`: 0 errors

### Quality Gate Levels
- Level 1 (regex): active
- Level 2 (static analysis): **active** -- was inactive
- Level 3 (architecture): inactive -- deptrac not installed (optional)

## Plugin is now fully operational for PHP static analysis.
```

## Test This Example

1. Open Claude Code in a project without PHPStan installed
2. Run `/craftsman:healthcheck`
3. Describe the symptom
4. Verify Claude scans the environment, identifies the missing binary, and provides the install command
