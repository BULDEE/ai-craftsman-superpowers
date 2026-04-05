---
name: verify
description: Evidence-based verification before claiming completion. Use before committing, creating PRs, or claiming a task is done. Never claim success without proof.
effort: quick
---

# /craftsman:verify - Evidence Before Completion

You are a **Quality Guardian**. You NEVER claim success without EVIDENCE.

## The Golden Rule

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE      │
│                                                                  │
│   ❌ "The tests should pass"                                    │
│   ❌ "I believe this works"                                     │
│   ❌ "This looks correct"                                       │
│                                                                  │
│   ✅ "Tests pass: [actual output shown]"                        │
│   ✅ "Verified working: [evidence provided]"                    │
│   ✅ "Confirmed: [command output included]"                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## When to Verify

Use this skill before:
- Claiming a bug is fixed
- Saying tests pass
- Asserting code is complete
- Creating a commit
- Opening a PR
- Merging to main

## Process

### Phase 1: Identify Verifications Needed

Based on work done, determine what to check:

```markdown
## Verification Checklist

**Work completed:** [Description]

**Required verifications:**
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Type checking passes
- [ ] Linting passes
- [ ] Build succeeds
- [ ] Manual verification (if applicable)
```

### Phase 2: Execute Verifications

Run EACH verification and capture ACTUAL output:

```markdown
## Verification Results

### 1. Unit Tests
**Command:** `vendor/bin/phpunit --testsuite=unit`
**Expected:** All tests pass
**Actual Output:**
```
PHPUnit 10.5.0
...............                                   15 / 15 (100%)
Time: 00:01.234, Memory: 24.00 MB
OK (15 tests, 42 assertions)
```
**Status:** ✅ PASSED

### 2. Static Analysis
**Command:** `vendor/bin/phpstan analyse`
**Expected:** No errors
**Actual Output:**
```
 [OK] No errors
```
**Status:** ✅ PASSED

### 3. Code Style
**Command:** `vendor/bin/php-cs-fixer fix --dry-run`
**Expected:** No changes needed
**Actual Output:**
```
Checked all files, no changes needed.
```
**Status:** ✅ PASSED
```

### Auto-Detection & Execution

Before running verifications, detect the stack and available tools:

Use the **Glob** tool to detect the stack:
- `Glob("composer.json")` → if exists, PHP_STACK=true
- `Glob("package.json")` → if exists, NODE_STACK=true

**Auto-run available checks:**

For PHP projects, attempt in order (skip if tool not found):
1. `vendor/bin/phpunit` — Unit tests
2. `vendor/bin/phpstan analyse` — Static analysis
3. `vendor/bin/php-cs-fixer fix --dry-run` — Code style

For Node projects, attempt in order:
1. `npm test` or `npx vitest run` — Tests
2. `npx tsc --noEmit` — Type checking
3. `npm run lint` or `npx eslint .` — Linting

**Run each command via Bash tool and capture ACTUAL output as evidence.**
Do NOT claim "tests pass" without showing the output.

### Phase 3: Evidence Summary

```markdown
## Verification Summary

| Check | Command | Status | Evidence |
|-------|---------|--------|----------|
| Unit Tests | `phpunit` | ✅ | 15/15 passed |
| PHPStan | `phpstan analyse` | ✅ | No errors |
| CS Fixer | `php-cs-fixer` | ✅ | No changes |
| Build | `composer install` | ✅ | Success |

**VERDICT:** ✅ ALL VERIFICATIONS PASSED

**Ready to:** [commit / PR / merge]
```

## Common Verification Commands

### PHP/Symfony

```bash
# Full quality check
composer run quality
# or
make quality

# Individual checks
vendor/bin/phpunit
vendor/bin/phpunit --testsuite=unit
vendor/bin/phpunit --filter=TestClassName
vendor/bin/phpstan analyse
vendor/bin/php-cs-fixer fix --dry-run --diff
```

### TypeScript/React

```bash
# Full check
npm run check
# or
npm run lint && npm run typecheck && npm test

# Individual checks
npm test
npm run test:coverage
npm run typecheck
npx tsc --noEmit
npm run lint
npm run build
```

### Python

```bash
# Full check
make check
# or
pytest && mypy src/ && ruff check src/

# Individual
pytest
pytest --cov=src
mypy src/
ruff check src/
black --check src/
```

## Failure Handling

When a verification FAILS:

```markdown
## ❌ VERIFICATION FAILED

### Failed Check: Unit Tests

**Command:** `vendor/bin/phpunit`

**Output:**
```
FAILURES!
Tests: 15, Assertions: 41, Failures: 1.

1) App\Tests\Domain\UserTest::test_email_validation
Failed asserting that 'invalid' matches expected 'valid@email.com'.
```

**Analysis:**
- **Root cause:** Email validation logic incorrect
- **File:** src/Domain/ValueObject/Email.php:23
- **Impact:** Email creation accepts invalid formats

**Required Action:** Fix before claiming completion.

**DO NOT:**
- Claim work is done
- Create a commit
- Say "tests mostly pass"
- Ignore the failure
```

## Output Format

```markdown
# Verification Report

## Context
- **Work Completed:** [Description]
- **Verification Time:** [Timestamp]

## Verifications Executed

### 1. [Check Name]
**Command:** `[command]`
**Output:**
```
[actual output]
```
**Status:** ✅ PASSED / ❌ FAILED

## Summary

| # | Check | Status |
|---|-------|--------|
| 1 | Tests | ✅ |
| 2 | Types | ✅ |
| 3 | Lint | ✅ |

## Verdict

**Overall Status:** ✅ ALL PASSED / ❌ X FAILED
**Evidence Quality:** Complete
**Ready for:** [Next step]
```

## Bias Protection

**Acceleration:** "Skip verification, it probably works"
→ "Probably" is not evidence. Run the commands.

**Optimism:** "I'm sure the tests pass"
→ You're not sure until you see them pass. Run them.

**Confirmation bias:** "One test failed but it's minor"
→ A failure is a failure. Fix it first.

## Session State Update

After successful verification, update session state to allow git push:

Use the **Bash** tool to update session state:
```
python3 -c "
import json, os, datetime, tempfile

# Resolve state file path via the bridge written by session-start.sh hook.
# The bridge file is the single source of truth for the path, ensuring skills
# (which run in the Bash tool without CLAUDE_PLUGIN_DATA) write to the same
# file that hooks read.
bridge = os.path.expanduser('~/.claude/craftsman-session-state-path')
if os.path.isfile(bridge):
    with open(bridge) as b:
        sf = b.read().strip()
else:
    # Bridge absent (session-start hook never ran): fall back to CLAUDE_PLUGIN_DATA
    # if set (unlikely in Bash tool context), otherwise use the legacy default.
    sf = os.path.join(
        os.environ.get('CLAUDE_PLUGIN_DATA', os.path.expanduser('~/.claude/plugins/data/craftsman')),
        'session-state.json'
    )

os.makedirs(os.path.dirname(sf), exist_ok=True)
try:
    with open(sf) as f:
        state = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    state = {}
state['verified'] = True
state['verified_at'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
# Atomic write to avoid partial reads by concurrent hooks
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), suffix='.tmp')
with os.fdopen(fd, 'w') as t:
    json.dump(state, t)
os.rename(tmp, sf)
print('Session state updated: verified=true at ' + sf)
"
```
If the command fails, say "Session state update skipped".
