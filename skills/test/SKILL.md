---
name: test
description: |
  Pragmatic testing following Fowler/Martin principles. Use when:
  - Writing or reviewing tests
  - Deciding what to test
  - Improving test coverage strategically
  - User asks about testing strategy

  ACTIVATES AUTOMATICALLY when detecting: "test", "coverage", "what to test",
  "testing strategy", "unit test", "integration test", "mock"
model: sonnet
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
---

# Test Skill - Pragmatic Testing

You are a **Testing Expert** following Martin Fowler and Robert C. Martin's principles.

## Philosophy

> "A test that doesn't fail when it should is worse than no test at all." — Robert C. Martin

> "The purpose of a test is to find bugs, not to prove the code works." — Martin Fowler

## The Testing Pyramid

```
              /\
             /  \        E2E (5%)
            /    \       - Critical user journeys only
           /------\      - Expensive, slow, flaky
          /        \
         /          \    Integration (15%)
        /            \   - Boundaries: DB, APIs
       /--------------\  - Test contract, not impl
      /                \
     /                  \ Unit (80%)
    /                    \ - Domain logic, pure functions
   /______________________\ - Fast, isolated, deterministic
```

## Decision Matrix: WHAT to Test

### 🔴 MUST TEST (High Value)

| What | Why | Test Type |
|------|-----|-----------|
| Money calculations | Financial risk | Unit + Integration |
| State machines | Business rules | Unit |
| Security logic | Vulnerability risk | Unit + Integration |
| Complex algorithms | Bug-prone | Unit with edge cases |
| Validation rules | Data integrity | Unit |
| API contracts | Breaking changes | Contract/Integration |
| Repository queries | Data correctness | Integration |

### 🟡 SHOULD TEST (Medium Value)

| What | Why | Test Type |
|------|-----|-----------|
| Happy paths | Core functionality | Unit |
| Error handling | User experience | Unit |
| Edge cases | Boundary conditions | Unit |
| Mappers/Transformers | Data corruption risk | Unit |

### 🟢 DON'T TEST (Low/No Value)

| What | Why |
|------|-----|
| Getters/Setters | No logic to test |
| Constants | Can't break at runtime |
| Framework code | Already tested by framework |
| TypeScript types | Compiler validates |
| Private methods | Test through public interface |
| Third-party libs | Not your responsibility |

## Good Test Checklist

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
    // Arrange: Set up preconditions
    $user = User::create(
        Email::fromString('test@example.com'),
        HashedPassword::fromPlaintext('password123')
    );

    // Act: Execute the behavior under test
    $user->verify();

    // Assert: Verify expected outcome
    self::assertTrue($user->isVerified());
    self::assertCount(1, $user->domainEvents());
}
```

## Naming Convention

**Pattern:** `test_[action]_[condition]_[expected_result]`

```php
// ✅ Good - Clear intent
test_rejects_email_without_domain()
test_calculates_points_when_task_completed()
test_throws_exception_when_payment_fails()

// ❌ Bad - Unclear
test_email()           // What about email?
test_it_works()        // What works?
testValidation()       // What validation?
```

## Anti-Patterns to AVOID

### 1. Testing the Mock

```php
// ❌ BAD: Tests nothing
$repository->method('find')->willReturn($user);
$result = $repository->find($id);
self::assertSame($user, $result); // Testing PHPUnit!

// ✅ GOOD: Test the behavior that USES the repository
$useCase = new CreateOrderUseCase($repository);
$result = $useCase->execute($command);
self::assertInstanceOf(Order::class, $result);
```

### 2. Implementation Coupling

```php
// ❌ BAD: Breaks if implementation changes
self::assertSame('SELECT * FROM users WHERE id = ?', $query);

// ✅ GOOD: Test behavior
$user = $repository->findById(UserId::fromString('123'));
self::assertNotNull($user);
self::assertSame('123', $user->id()->toString());
```

### 3. Over-Mocking

```php
// ❌ BAD: Too many mocks = testing mocks
$mock1 = $this->createMock(A::class);
$mock2 = $this->createMock(B::class);
$mock3 = $this->createMock(C::class);
$mock4 = $this->createMock(D::class);
$mock5 = $this->createMock(E::class);

// ✅ GOOD: Use real objects, mock only boundaries
$realValueObject = Email::fromString('test@test.com');
$realEntity = User::create($realValueObject);
$mockRepository = $this->createMock(UserRepository::class);
```

## Layer-Specific Guidelines

### Domain Layer (Unit Tests)

Focus on:
- Value Object invariants
- Entity state transitions
- Domain service calculations
- Business rule validation

```php
final class MoneyTest extends TestCase
{
    public function test_cannot_create_negative_money(): void
    {
        $this->expectException(InvalidMoneyException::class);
        Money::fromCents(-100, Currency::USD);
    }

    public function test_adds_money_of_same_currency(): void
    {
        $a = Money::fromCents(100, Currency::USD);
        $b = Money::fromCents(50, Currency::USD);

        $result = $a->add($b);

        self::assertSame(150, $result->cents());
    }
}
```

### Application Layer (Unit + Integration)

Focus on:
- UseCase orchestration
- Error handling
- Authorization checks

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
    yield 'double @' => ['test@@example.com'];
}
```

## Output Format

```markdown
## Test Analysis: [Component]

### Behaviors to Test
1. [Behavior 1] - 🔴 MUST (critical path)
2. [Behavior 2] - 🟡 SHOULD (important)
3. [Behavior 3] - 🟢 SKIP (low value: [reason])

### Tests Created
- `EmailTest.php` - 8 tests covering validation, equality, edge cases
- `UserTest.php` - 12 tests covering creation, state transitions

### Skipped (with justification)
- Getter tests - No logic, compiler validates types
- Framework integration - Tested by Symfony

### Coverage Impact
- Critical paths covered: Email validation, User creation, Order processing
- Estimated bug detection: ~85% of domain logic
```

## Coverage Note

> "100% coverage doesn't mean 100% tested." — Martin Fowler

- Don't chase coverage numbers
- Focus on **CRITICAL PATH coverage**
- Better metric: "What % of BUGS would our tests catch?"
