# Example: Create a User Entity with DDD

## Prompt

```
/craftsman:design
I need to create a User entity for an e-commerce platform.
Users can register, update their profile, and be deactivated.
```

## Expected Behavior

### Phase 1: Understanding (Claude asks questions)

```markdown
## Understanding

**Business Problem:** User identity and lifecycle management for e-commerce

**Domain Invariants:**
- [ ] Email must be unique and valid format
- [ ] User must have a name (non-empty)
- [ ] Status transitions: active <-> suspended -> deleted (one-way to deleted)
- [ ] Password must meet security requirements

**Events to Emit:**
- UserRegistered
- UserProfileUpdated
- UserSuspended
- UserReactivated
- UserDeleted

**Relationships:**
- User has many: Orders
- User has one: Cart
- User has many: Addresses
```

### Phase 2: Challenge (alternatives proposed)

```markdown
## Alternatives

### Option A: Rich Domain Entity
Entity with embedded Value Objects, behavior methods, domain events.
- Pros: Encapsulated business logic, testable
- Cons: More initial code
- When: Production systems with complex rules

### Option B: Anemic Entity + Service
Simple getters/setters, logic in service layer.
- Pros: Faster to write initially
- Cons: Logic scattered, hard to test
- When: Never (anti-pattern)
```

### Phase 3: Recommendation

```markdown
## Recommendation

**Type:** AggregateRoot
**Reason:** User owns its lifecycle and emits business events
**Trade-off:** More upfront code for better long-term maintainability

**Proceed with this design?**
```

### Phase 4: Generated Code

```php
<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\UserRegisteredEvent;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\UserId;

final class User
{
    /** @var object[] */
    private array $domainEvents = [];

    private function __construct(
        private readonly UserId $id,
        private Email $email,
        private string $name,
        private UserStatus $status,
    ) {
    }

    public static function register(
        UserId $id,
        Email $email,
        string $name,
    ): self {
        $user = new self($id, $email, $name, UserStatus::Active);
        $user->record(new UserRegisteredEvent($id, $email));

        return $user;
    }

    public function updateProfile(Email $newEmail, string $newName): void
    {
        $this->email = $newEmail;
        $this->name = $newName;
        $this->record(new UserProfileUpdatedEvent($this->id));
    }

    public function suspend(): void
    {
        if ($this->status === UserStatus::Deleted) {
            throw new CannotSuspendDeletedException();
        }
        $this->status = UserStatus::Suspended;
        $this->record(new UserSuspendedEvent($this->id));
    }

    // ... getters and releaseEvents()
}
```

## Test This Example

1. Open Claude Code in a Symfony project
2. Run `/craftsman:design`
3. Paste the prompt above
4. Verify Claude follows all 4 phases before generating code
