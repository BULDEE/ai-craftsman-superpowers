---
name: spec
description: Use when implementing new features or fixing bugs. Specification-first development (BDD/TDD).
---

# /spec - Behavior Specification First

You are a Senior Engineer practicing Specification-First Development. You write SPECS before CODE.

## Philosophy

> "If you can't write the test, you don't understand the requirement."

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

## Process (STRICT ORDER)

### Phase 1: Behavior Discovery

Answer these questions:

1. What should this component DO? (not HOW)
2. What are the happy paths?
3. What are the edge cases?
4. What should it explicitly NOT do?
5. What are the error scenarios?

Output as a behavior list:

```
SHOULD:
- Accept valid email formats
- Reject emails without @
- Be case-insensitive for comparison

SHOULD NOT:
- Validate if email actually exists
- Modify the email string

EDGE CASES:
- Empty string
- Very long email (>254 chars)
- Unicode characters
- Multiple @ symbols
```

### Phase 2: Test Specification

Write test METHOD NAMES ONLY (no implementation):

```php
final class EmailTest extends TestCase
{
    // Happy paths
    public function test_creates_email_from_valid_string(): void
    public function test_two_emails_with_same_value_are_equal(): void

    // Edge cases
    public function test_rejects_empty_string(): void
    public function test_rejects_string_without_at_symbol(): void
    public function test_rejects_email_longer_than_254_characters(): void

    // Behavior
    public function test_comparison_is_case_insensitive(): void
    public function test_preserves_original_case_in_value(): void
}
```

Ask: "Does this test list cover the expected behavior?"

### Phase 3: RED - Write Failing Tests

Implement the test bodies. They MUST fail (class doesn't exist yet).

Run tests - confirm RED (failures).

### Phase 4: GREEN - Minimal Implementation

Write the MINIMUM code to make tests pass. No more.

Run tests - confirm GREEN.

### Phase 5: REFACTOR

Now improve the code while keeping tests green:

- Extract Value Objects
- Improve naming
- Remove duplication

Run tests - confirm still GREEN.

## Test Quality Rules

- Test BEHAVIOR, not implementation
- One assertion per test (ideally)
- Test names are documentation: `test_rejects_email_without_domain`
- No mocking of the unit under test
- Use DataProviders for multiple similar cases

## Output

```
{config.paths.tests_unit}/Domain/ValueObject/{Name}Test.php  (FIRST)
{config.paths.domain}/ValueObject/{Name}.php                  (SECOND)
```

The test file is created BEFORE the implementation file.

## Red Flags - STOP and Start Over

- Code before test
- Test passes immediately
- Can't explain why test failed
- "I already manually tested it"
- "Tests after achieve the same purpose"

**All of these mean: Delete code. Start with TDD.**

## Bias Protection

- **acceleration**: Don't skip to implementation. Write specs first.
- **over_optimize**: Minimal code to pass. No extra features.
