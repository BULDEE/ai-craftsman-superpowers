# Example: Define Testing Strategy

## Prompt

```
/craftsman:test
What tests should I write for my UserService?
It handles user registration, profile updates, and deactivation.
```

## Expected Behavior

### Phase 1: Understand the Service

Claude asks:
```markdown
## Context Needed

1. **Service type:** Application service? Domain service?
2. **Dependencies:** What does it depend on? (Repository, Mailer, etc.)
3. **Side effects:** Does it send emails? Dispatch events?
4. **Existing tests:** Any tests already? Coverage?
```

### Phase 2: Test Strategy Recommendation

```markdown
## Testing Strategy for UserService

### Test Pyramid Distribution

```
        ┌───────────┐
        │   E2E     │  10% - Happy paths only
        │  (3-5)    │
        ├───────────┤
        │Integration│  20% - Repository, external services
        │  (8-10)   │
        ├───────────┤
        │   Unit    │  70% - Business logic, edge cases
        │  (20-30)  │
        └───────────┘
```

### Unit Tests (Behavior-focused)

| Test Case | Why |
|-----------|-----|
| `test_user_can_register_with_valid_data` | Happy path |
| `test_registration_fails_with_duplicate_email` | Business rule |
| `test_registration_fails_with_invalid_email_format` | Validation |
| `test_profile_update_changes_email` | State change |
| `test_profile_update_emits_event` | Side effect |
| `test_deactivation_changes_status` | State change |
| `test_cannot_deactivate_already_inactive_user` | Business rule |
| `test_deactivation_emits_event` | Side effect |

### What NOT to Test

| Anti-pattern | Why |
|--------------|-----|
| Testing getters/setters | No logic to test |
| Testing framework code | Already tested |
| Testing implementation details | Brittle tests |
| Testing private methods | Test through public API |

### Test Code Example

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application;

use App\Application\UseCase\RegisterUserHandler;
use App\Domain\Event\UserRegisteredEvent;
use App\Domain\ValueObject\Email;
use PHPUnit\Framework\TestCase;

final class RegisterUserHandlerTest extends TestCase
{
    private InMemoryUserRepository $users;
    private RegisterUserHandler $handler;

    protected function setUp(): void
    {
        $this->users = new InMemoryUserRepository();
        $this->handler = new RegisterUserHandler($this->users);
    }

    public function test_user_can_register_with_valid_data(): void
    {
        // Arrange
        $command = new RegisterUserCommand(
            email: 'john@example.com',
            name: 'John Doe',
        );

        // Act
        $userId = ($this->handler)($command);

        // Assert
        $user = $this->users->findById($userId);
        self::assertNotNull($user);
        self::assertTrue($user->email()->equals(Email::fromString('john@example.com')));
    }

    public function test_registration_fails_with_duplicate_email(): void
    {
        // Arrange
        $this->users->save(UserMother::withEmail('existing@example.com'));
        $command = new RegisterUserCommand(
            email: 'existing@example.com',
            name: 'Another User',
        );

        // Assert
        $this->expectException(EmailAlreadyExistsException::class);

        // Act
        ($this->handler)($command);
    }

    public function test_registration_emits_user_registered_event(): void
    {
        // Arrange
        $command = new RegisterUserCommand(
            email: 'john@example.com',
            name: 'John Doe',
        );

        // Act
        $userId = ($this->handler)($command);

        // Assert
        $user = $this->users->findById($userId);
        $events = $user->releaseEvents();
        self::assertCount(1, $events);
        self::assertInstanceOf(UserRegisteredEvent::class, $events[0]);
    }
}
```

### Integration Tests

| Test Case | What it validates |
|-----------|-------------------|
| `test_user_persisted_to_database` | Doctrine mapping correct |
| `test_welcome_email_sent` | Mailer integration |
| `test_event_dispatched_to_messenger` | Message bus integration |
```

## Test This Example

1. Describe your service to `/craftsman:test`
2. Verify Claude recommends the test pyramid
3. Check tests focus on behavior, not implementation
4. Verify test examples follow AAA pattern
