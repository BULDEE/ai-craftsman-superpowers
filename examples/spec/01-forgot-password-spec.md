# Example: Forgot Password Specification

## Prompt

```
/craftsman:spec
Implement a forgot password flow. User submits email, we send reset link, they click it and set new password. I need the spec first.
```

## Expected Behavior

### Phase 1: Behavior Discovery

```markdown
## Behavior Specification

### SHOULD (Happy paths)
- [ ] Issue a reset token for the user who asked, valid for one hour
- [ ] Accept the token once, within the hour, to set a new password
- [ ] Record a PasswordReset event on the user after a successful reset

### SHOULD NOT (Explicit non-behaviors)
- [ ] Reveal whether the email has an account (same response either way)
- [ ] Store the token in clear (only its hash is persisted)

### EDGE CASES
- [ ] Token used after one hour → ResetTokenExpired
- [ ] Token used a second time → ResetTokenAlreadyUsed

### ERROR SCENARIOS
- [ ] Unknown token → ResetTokenNotFound
- [ ] New password below the policy → WeakPassword
```

### Phase 2: Test Specification

```php
final class PasswordResetTokenTest extends TestCase
{
    public function test_can_be_consumed_within_one_hour(): void
    public function test_rejects_consumption_after_one_hour(): void
    public function test_rejects_a_second_consumption(): void
}
```

**Ask user:** "Does this test list cover the expected behavior?" The user confirms.

### Phase 3: RED - Write Failing Tests

The two rejection tests below; the first test consumes at 10:59 and asserts `isConsumed()`.

```php
public function test_rejects_consumption_after_one_hour(): void
{
    $token = PasswordResetToken::create(UserId::generate(), FrozenClock::at('2026-01-01 10:00'));

    $this->expectException(ResetTokenExpired::class);

    $token->consume(FrozenClock::at('2026-01-01 11:01'));
}

public function test_rejects_a_second_consumption(): void
{
    $clock = FrozenClock::at('2026-01-01 10:00');
    $token = PasswordResetToken::create(UserId::generate(), $clock);
    $token->consume($clock);

    $this->expectException(ResetTokenAlreadyUsed::class);

    $token->consume($clock);
}
```

```bash
vendor/bin/phpunit --filter=PasswordResetTokenTest
# Expected: FAILURES (class PasswordResetToken does not exist)
```

All three fail for the right reason: the class is missing.

### Phase 4: GREEN - Minimal Implementation

```php
<?php

declare(strict_types=1);

namespace App\Domain\Security;

use App\Domain\ValueObject\UserId;
use App\Shared\Domain\Clock\Clock;

final class PasswordResetToken
{
    private function __construct(
        private readonly UserId $userId,
        private readonly \DateTimeImmutable $expiresAt,
        private ?\DateTimeImmutable $consumedAt,
    ) {}

    public static function create(UserId $userId, Clock $clock): self
    {
        return new self($userId, $clock->now()->modify('+1 hour'), null);
    }

    public function consume(Clock $clock): void
    {
        if ($this->consumedAt !== null) {
            throw ResetTokenAlreadyUsed::for($this->userId);
        }

        if ($clock->now() > $this->expiresAt) {
            throw ResetTokenExpired::for($this->userId);
        }

        $this->consumedAt = $clock->now();
    }

    public function isConsumed(): bool
    {
        return $this->consumedAt !== null;
    }
}
```

```bash
vendor/bin/phpunit --filter=PasswordResetTokenTest
# Expected: OK (3 tests, 3 assertions)
```

### Phase 5: REFACTOR

`'+1 hour'` becomes a `LIFETIME` constant; the tests run again and stay GREEN.

### Output

```markdown
## Specification: PasswordResetToken

### Behaviors to Test
1. Consumable once, within one hour - MUST TEST (critical)
2. Expired and reused tokens rejected - MUST TEST (core functionality)
3. Password hashing - SKIP (framework handles this)

### Test File
`tests/Unit/Domain/Security/PasswordResetTokenTest.php` (3 tests, written first)

### Implementation File
`src/Domain/Security/PasswordResetToken.php`

### Out of scope
Request and reset handlers (next specs), email delivery
```

## Key Points

- Discovery states what the flow must NOT do (enumeration, clear-text tokens)
- Test names come first and are confirmed; the RED run is shown before any code
- GREEN is the minimum: no token value, persistence or email, which no test asks for
- An injected `Clock` tests the one-hour rule at 10:59 and 11:01 without sleeping
