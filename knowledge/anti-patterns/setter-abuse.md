# Anti-Pattern: Setter Abuse

## What It Is

Using public setters to modify entity state instead of behavior methods.

## Why It's Bad

- Entity can be put in invalid/inconsistent states
- No validation at state change time
- Business rules scattered or duplicated
- No domain events
- Impossible to maintain invariants

## Example

### BAD: Public Setters

```php
final class User
{
    private string $email;
    private string $status;
    private bool $isVerified;
    private ?DateTimeImmutable $verifiedAt;

    public function setEmail(string $email): void
    {
        $this->email = $email;
        // Should verification reset? Who knows!
    }

    public function setStatus(string $status): void
    {
        $this->status = $status;
        // Any status is valid? No validation!
    }

    public function setIsVerified(bool $verified): void
    {
        $this->isVerified = $verified;
        // verifiedAt not set! Inconsistent state!
    }

    public function setVerifiedAt(?DateTimeImmutable $at): void
    {
        $this->verifiedAt = $at;
        // isVerified not set! Inconsistent state!
    }
}

// Calling code must remember ALL the rules
$user->setIsVerified(true);
$user->setVerifiedAt(new DateTimeImmutable()); // Easy to forget!
// State is inconsistent if one is forgotten
```

### GOOD: Behavior Methods

```php
final class User
{
    private Email $email;
    private UserStatus $status;
    private bool $isVerified = false;
    private ?DateTimeImmutable $verifiedAt = null;

    // No setters! Only behavior methods

    public function verify(): void
    {
        // Guard: can't verify twice
        if ($this->isVerified) {
            throw new UserAlreadyVerifiedException($this->id);
        }

        // Guard: must be active
        if ($this->status !== UserStatus::ACTIVE) {
            throw new CannotVerifyInactiveUserException($this->id);
        }

        // Atomic state change - BOTH fields updated together
        $this->isVerified = true;
        $this->verifiedAt = new DateTimeImmutable();

        // Domain event
        $this->raise(new UserVerified($this->id, $this->verifiedAt));
    }

    public function changeEmail(Email $newEmail): void
    {
        // Guard: no change needed
        if ($this->email->equals($newEmail)) {
            return;
        }

        $oldEmail = $this->email;
        $this->email = $newEmail;

        // Business rule: must re-verify after email change
        $this->isVerified = false;
        $this->verifiedAt = null;

        $this->raise(new UserEmailChanged($this->id, $oldEmail, $newEmail));
    }

    public function suspend(string $reason): void
    {
        if ($this->status === UserStatus::SUSPENDED) {
            return; // Already suspended
        }

        $this->status = UserStatus::SUSPENDED;

        $this->raise(new UserSuspended($this->id, $reason));
    }
}

// Calling code is simple and can't make mistakes
$user->verify(); // All invariants maintained automatically
```

## Exceptions Where Setters Are OK

1. **DTOs/Commands** - Data transfer objects don't have invariants
2. **Test builders** - For test setup convenience
3. **Doctrine hydration** - ORM needs to set values (but make them private)

```php
// DTO - setters OK
final class CreateUserRequest
{
    public string $email;
    public string $password;
}

// Test builder - setters OK
final class UserBuilder
{
    private string $email = 'default@example.com';

    public function withEmail(string $email): self
    {
        $this->email = $email;
        return $this;
    }

    public function build(): User
    {
        return User::create(Email::fromString($this->email), ...);
    }
}
```

## How to Detect

1. Presence of `setX()` methods on domain entities
2. Multiple related fields that should change together
3. State changes without validation
4. No domain events on important changes

## How to Fix

1. Remove all public setters from entities
2. Create behavior methods that encapsulate the change
3. Add guard clauses for business rules
4. Update related fields atomically
5. Emit domain events

## Rule

> Entities should expose WHAT they can do, not HOW they store data.
