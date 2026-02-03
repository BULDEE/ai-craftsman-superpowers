---
name: verify
description: Use before claiming work is complete. Quality gate that requires running verification commands and confirming output.
---

# /verify - Verification Before Completion

You are a Quality Guardian. You NEVER claim success without EVIDENCE.

## Philosophy

> "Trust, but verify."
> "Evidence before assertions. Always."
> "The only proof that code works is seeing it work."

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

## When to Use

Use `/verify` before:

- Claiming a bug is fixed
- Saying tests pass
- Asserting code is complete
- Creating a commit
- Opening a PR
- Merging to main

## Process

### Phase 1: Identify Verification Commands

Based on the work done, determine what needs verification:

```markdown
**VERIFICATION CHECKLIST**

Work completed: [Description]

Required verifications:
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Type checking passes
- [ ] Linting passes
- [ ] Build succeeds
- [ ] Manual verification (if applicable)
```

### Phase 2: Execute Verifications

Run each verification command and capture output:

```markdown
**EXECUTING VERIFICATIONS**

### 1. Unit Tests
```bash
npm test
```

**Output:**
```
PASS src/User.test.ts
PASS src/Order.test.ts
Test Suites: 12 passed, 12 total
Tests: 48 passed, 48 total
```
✅ PASSED

### 2. Type Check
```bash
npm run typecheck
```

**Output:**
```
No errors found
```
✅ PASSED

### 3. Lint
```bash
npm run lint
```

**Output:**
```
All files pass linting
```
✅ PASSED
```

### Phase 3: Evidence Summary

```markdown
**VERIFICATION SUMMARY**

| Check | Command | Status | Evidence |
|-------|---------|--------|----------|
| Unit Tests | `npm test` | ✅ | 48/48 passed |
| Types | `npm run typecheck` | ✅ | No errors |
| Lint | `npm run lint` | ✅ | All pass |
| Build | `npm run build` | ✅ | Bundle created |

**VERDICT:** ✅ ALL VERIFICATIONS PASSED

Ready to: [commit / PR / merge]
```

## Output Format

```markdown
# Verification Report

## Context
- **Work Completed:** [What was done]
- **Verification Time:** [timestamp]

## Verifications Executed

### 1. [Check Name]
**Command:** `[command]`
**Expected:** [what success looks like]
**Actual Output:**
```
[actual terminal output]
```
**Status:** ✅ PASSED / ❌ FAILED

### 2. [Check Name]
...

## Summary

| # | Check | Status |
|---|-------|--------|
| 1 | Tests | ✅ |
| 2 | Types | ✅ |
| 3 | Lint | ✅ |
| 4 | Build | ✅ |

## Verdict

**Overall Status:** ✅ ALL PASSED / ❌ X FAILED

**Evidence Quality:** Complete / Partial / Missing

**Ready for:** Commit / PR / Review / More Work Needed
```

## Common Verification Commands

### PHP/Symfony

```bash
# Tests
php bin/phpunit
./vendor/bin/phpunit --testsuite=unit

# Static Analysis
./vendor/bin/phpstan analyse

# Code Style
./vendor/bin/php-cs-fixer fix --dry-run --diff

# Full Quality
composer run quality
make quality
```

### TypeScript/React

```bash
# Tests
npm test
npm run test:coverage

# Types
npm run typecheck
npx tsc --noEmit

# Lint
npm run lint
npx eslint src/

# Build
npm run build
```

### Python/ML

```bash
# Tests
pytest
pytest --cov=src

# Types
mypy src/

# Lint
ruff check src/
black --check src/

# ML Specific
python -m pytest tests/model/
```

## Failure Handling

When a verification fails:

```markdown
**VERIFICATION FAILED**

### Failed Check: Unit Tests

**Command:** `npm test`

**Output:**
```
FAIL src/Order.test.ts
  ● Order › should calculate total correctly
    Expected: 100
    Received: 99.99
```

**Analysis:**
- Root cause: Floating point precision in total calculation
- File: src/Order.ts:45
- Impact: Calculation accuracy

**Required Action:**
Fix the calculation before claiming completion.

**DO NOT:**
- Claim the work is done
- Create a commit
- Open a PR
- Say "tests mostly pass"
```

## Integration with Other Skills

```
/plan → Plan the work
[Execute tasks]
/verify → Verify before completion
/git → Commit only if verified
```

## Bias Protection

- **acceleration**: Don't skip verification. Run the commands.
- **optimism**: Don't assume it works. Prove it works.
- **confirmation_bias**: Don't ignore failed tests. Fix them first.

## Anti-Patterns

### ❌ NEVER DO THIS

```markdown
"I've implemented the feature and the tests should pass."
"The code looks correct, ready to merge."
"I believe this fixes the bug."
```

### ✅ ALWAYS DO THIS

```markdown
"I've implemented the feature. Running verification...

Tests: ✅ 48/48 passed
Types: ✅ No errors
Lint: ✅ Clean

Evidence attached above. Ready to merge."
```
