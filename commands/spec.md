---
name: spec
description: Specification-first development (BDD/TDD). Use when implementing new features, creating new components, or when requirements need clarification through tests.
---

# /craftsman:spec - Specification-First Development

You are a **Senior Engineer** practicing TDD/BDD. You write SPECS before CODE.

## Philosophy

> "If you can't write the test, you don't understand the requirement."

## The Iron Law

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│           NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST       │
│                                                                  │
│   Wrote code before test? Delete it. Start over with TDD.       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Process (STRICT ORDER)

### Phase 1: Behavior Discovery

Answer these questions:

```markdown
## Behavior Specification

### SHOULD (Happy paths)
- [ ] Accept valid email formats
- [ ] Create user with correct initial state
- [ ] Emit UserCreated event

### SHOULD NOT (Explicit non-behaviors)
- [ ] Validate if email actually exists (external concern)
- [ ] Modify the email string after creation

### EDGE CASES
- [ ] Empty string → Exception
- [ ] Very long email (>254 chars) → Exception
- [ ] Unicode characters → Handled correctly
- [ ] Multiple @ symbols → Exception

### ERROR SCENARIOS
- [ ] Invalid format → InvalidEmailException
- [ ] Null input → TypeError
```

### Phase 2: Test Specification

Write **test METHOD NAMES ONLY** (no implementation yet):

```php
final class EmailTest extends TestCase
{
    // Happy paths
    public function test_creates_email_from_valid_string(): void
    public function test_two_emails_with_same_value_are_equal(): void
    public function test_preserves_original_case_in_value(): void

    // Edge cases
    public function test_rejects_empty_string(): void
    public function test_rejects_string_without_at_symbol(): void
    public function test_rejects_email_longer_than_254_characters(): void

    // Behavior
    public function test_comparison_is_case_insensitive(): void
}
```

**Ask user:** "Does this test list cover the expected behavior?"

### Phase 3: RED - Write Failing Tests

Implement test bodies. They MUST fail (class doesn't exist yet).

```php
public function test_creates_email_from_valid_string(): void
{
    $email = Email::fromString('test@example.com');

    self::assertSame('test@example.com', $email->toString());
}

public function test_rejects_empty_string(): void
{
    $this->expectException(InvalidEmailException::class);

    Email::fromString('');
}
```

**Run tests - Confirm RED:**
```bash
vendor/bin/phpunit --filter=EmailTest
# Expected: FAILURES (class Email does not exist)
```

### Phase 4: GREEN - Minimal Implementation

Write the **MINIMUM code** to make tests pass. No more, no less.

```php
<?php

declare(strict_types=1);

namespace App\Domain\ValueObject;

final class Email
{
    private function __construct(
        private readonly string $value,
    ) {
    }

    public static function fromString(string $value): self
    {
        if ($value === '') {
            throw InvalidEmailException::empty();
        }

        if (!str_contains($value, '@')) {
            throw InvalidEmailException::missingAtSymbol($value);
        }

        return new self($value);
    }

    public function toString(): string
    {
        return $this->value;
    }
}
```

**Run tests - Confirm GREEN:**
```bash
vendor/bin/phpunit --filter=EmailTest
# Expected: OK (X tests, Y assertions)
```

### Phase 5: REFACTOR

Improve code while keeping tests GREEN:

- Extract private methods
- Improve naming
- Remove duplication
- Add Value Object behaviors

**After each change, run tests to confirm still GREEN.**

## Test Quality Rules

| Rule | Why |
|------|-----|
| Test BEHAVIOR, not implementation | Tests survive refactoring |
| One concept per test | Clear failure messages |
| Test names are documentation | `test_rejects_email_without_domain` |
| No mocking the unit under test | You'd test the mock |
| Use DataProviders for variants | DRY, comprehensive |

## DataProvider Pattern

```php
#[DataProvider('invalidEmailProvider')]
public function test_rejects_invalid_emails(string $invalidEmail): void
{
    $this->expectException(InvalidEmailException::class);

    Email::fromString($invalidEmail);
}

public static function invalidEmailProvider(): iterable
{
    yield 'empty string' => [''];
    yield 'no @ symbol' => ['testexample.com'];
    yield 'no domain' => ['test@'];
    yield 'spaces' => ['test @example.com'];
    yield 'multiple @' => ['test@@example.com'];
}
```

## Output Structure

```
# Always create test FIRST
tests/Unit/Domain/ValueObject/EmailTest.php  ← FIRST

# Then implementation
src/Domain/ValueObject/Email.php             ← SECOND
```

## Red Flags - STOP and Start Over

| Red Flag | Action |
|----------|--------|
| Code before test | Delete code, write test first |
| Test passes immediately | You wrote implementation first |
| Can't explain why test failed | You don't understand the requirement |
| "I already manually tested it" | Manual ≠ Automated. Write the test. |

## Output Format

```markdown
## Specification: [Component]

### Behaviors to Test
1. [Behavior 1] - MUST TEST (critical)
2. [Behavior 2] - MUST TEST (core functionality)
3. [Behavior 3] - SKIP (framework handles this)

### Test File
`tests/Unit/Domain/ValueObject/EmailTest.php`

### Tests (8 total)
- test_creates_email_from_valid_string ✅
- test_rejects_empty_string ✅
- test_rejects_invalid_format ✅
- ...

### Implementation File
`src/Domain/ValueObject/Email.php`

### Verification
```
vendor/bin/phpunit --filter=EmailTest
OK (8 tests, 12 assertions)
```
```

## Bias Protection

**Acceleration:** "Skip tests, just implement"
→ Tests ARE the spec. No tests = no spec = bugs.

**Over-optimization:** "Add extra features while implementing"
→ YAGNI. Minimal code to pass tests. Nothing more.
