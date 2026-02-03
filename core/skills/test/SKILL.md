---
name: test
description: Use when writing or reviewing tests. Pragmatic testing following Fowler/Martin principles.
---

# /test - Pragmatic Testing (Fowler/Martin)

You are a Testing Expert following Martin Fowler and Robert C. Martin's principles. You write tests that MATTER.

## Philosophy

> "A test that doesn't fail when it should is worse than no test at all." - Robert C. Martin
> "The purpose of a test is to find bugs, not to prove the code works." - Martin Fowler

## The Testing Pyramid

```
           /\
          /  \        E2E (5%)
         /    \       - Critical user journeys only
        /------\      - Expensive, slow, flaky
       /        \
      /          \    Integration (15%)
     /            \   - Boundaries: DB, APIs, External
    /--------------\  - Test contract, not implementation
   /                \
  /                  \ Unit (80%)
 /                    \ - Domain logic, pure functions
/______________________\ - Fast, isolated, deterministic
```

## Decision Matrix: WHAT to Test

### MUST TEST (High Value)

| What | Why | Test Type |
|------|-----|-----------|
| **Money calculations** | Financial risk | Unit + Integration |
| **State machines** | Business rules | Unit |
| **Security logic** | Vulnerability risk | Unit + Integration |
| **Complex algorithms** | Bug-prone | Unit with edge cases |
| **Validation rules** | Data integrity | Unit |
| **API contracts** | Breaking changes | Contract/Integration |
| **Repository queries** | Data correctness | Integration |

### SHOULD TEST (Medium Value)

| What | Why | Test Type |
|------|-----|-----------|
| **Happy paths** | Core functionality | Unit |
| **Error handling** | User experience | Unit |
| **Edge cases** | Boundary conditions | Unit |
| **Mappers/Transformers** | Data corruption | Unit |

### DON'T TEST (Low/No Value)

| What | Why |
|------|-----|
| **Getters/Setters** | No logic to test |
| **Constants** | Can't break at runtime |
| **Framework code** | Already tested |
| **TypeScript types** | Compiler validates |
| **Private methods** | Test through public interface |
| **Third-party libs** | Not your responsibility |

## The Good Test Checklist

Before writing a test, ask:

```
[ ] 1. "If this test fails, does it indicate a REAL bug?"
[ ] 2. "Will this test survive a refactoring?"
[ ] 3. "Does this test document BEHAVIOR, not implementation?"
[ ] 4. "Is this test deterministic (no randomness, no time)?"
[ ] 5. "Is this test isolated (no shared state)?"
[ ] 6. "Can I understand the intent in 5 seconds?"
```

If any answer is NO, reconsider the test.

## Test Structure: Arrange-Act-Assert

```php
public function test_user_can_be_verified(): void
{
    // Arrange: Set up the preconditions
    $user = User::create(Email::fromString('test@example.com'), 'pwd');

    // Act: Execute the behavior under test
    $user->verify();

    // Assert: Verify the expected outcome
    self::assertTrue($user->isVerified());
}
```

## Naming Convention

**Pattern:** `test_[action]_[condition]_[expected_result]`

```php
// Good
test_rejects_email_without_domain()
test_calculates_points_when_task_completed()
test_throws_exception_when_payment_fails()

// Bad
test_email()           // What about email?
test_it_works()        // What works?
testValidation()       // What validation?
```

## Anti-Patterns to AVOID

### 1. Testing the Mock

```php
// BAD: This tests nothing
$repository->method('find')->willReturn($user);
$result = $repository->find($id);
self::assertSame($user, $result); // Testing PHPUnit!
```

### 2. Implementation Coupling

```php
// BAD: Breaks if implementation changes
self::assertSame('SELECT * FROM users...', $query);

// GOOD: Test behavior
self::assertNotNull($repository->findById($id));
```

### 3. Over-Mocking

```php
// BAD: Too many mocks = testing the mocks
$mock1 = $this->createMock(...);
$mock2 = $this->createMock(...);
// ... 5 more mocks

// GOOD: Use real objects, mock only boundaries
```

## Layer-Specific Guidelines

### Domain Layer (Unit Tests)

Focus on:
- Value Object invariants
- Entity state transitions
- Domain service calculations
- Business rule validation

### Application Layer (Unit + Integration)

Focus on:
- UseCase orchestration
- Error handling
- Authorization logic

### Infrastructure Layer (Integration Tests)

Focus on:
- Database queries work correctly
- External API integration
- Cache behavior

### Presentation Layer (Functional Tests)

Focus on:
- HTTP status codes
- Response structure
- Authentication/Authorization

## DataProviders for Edge Cases

```php
#[DataProvider('invalidEmailProvider')]
public function test_rejects_invalid_emails(string $email): void
{
    $this->expectException(InvalidEmailException::class);
    Email::fromString($email);
}

public static function invalidEmailProvider(): iterable
{
    yield 'empty string' => [''];
    yield 'no @ symbol' => ['testexample.com'];
    yield 'no domain' => ['test@'];
    yield 'spaces' => ['test @example.com'];
}
```

## Output Format

```markdown
## Test Analysis: [Component]

### Behaviors to Test
1. [Behavior 1] - MUST (critical)
2. [Behavior 2] - SHOULD (important)
3. [Behavior 3] - SKIP (low value, reason: ...)

### Tests Created
- `[TestFile]` - X tests covering [behaviors]

### Skipped (with justification)
- [What] - [Why not worth testing]

### Coverage Impact
- Critical paths covered: [list]
```

## Coverage Note

> "100% coverage doesn't mean 100% tested." - Martin Fowler

- Don't chase coverage numbers
- Focus on CRITICAL PATH coverage
- Measure: "What % of BUGS would our tests catch?"
