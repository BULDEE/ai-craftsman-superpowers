# Example: Extract a Value Object from a Primitive Field

## Prompt

```
/craftsman:refactor
The User entity uses a plain string for the email field. I want to extract it into a proper Value Object.
```

## Expected Behavior

### Phase 1: Analysis (Claude identifies the smell)

```markdown
## Refactoring Analysis

**Smell:** Primitive Obsession on `User::$email` (plain `string`)
**Impact:** Validation logic duplicated across services, no type safety at domain boundary
**Risk:** Low -- single field extraction, no external API surface change

**Affected files:**
- `src/Domain/Entity/User.php` -- field type change
- `src/Application/Command/RegisterUserHandler.php` -- construction site
- `tests/Domain/Entity/UserTest.php` -- assertions on email
```

### Phase 2: Behavior Preservation (test baseline)

```markdown
## Behavior Preservation

**Existing tests:** 12 pass, 0 fail
**Invariants to preserve:**
- Email format validated before entity creation
- Email uniqueness enforced at repository level
- Email compared by value, not by reference

**Strategy:** Replace `string` with `Email` VO, run tests after each step
```

### Phase 3: Refactoring Steps

```markdown
## Plan

1. Create `Email` Value Object with self-validation
2. Update `User` entity to accept `Email` instead of `string`
3. Update construction sites (handlers, factories)
4. Update tests to use `Email::create()`
5. Run full test suite -- confirm green
```

### Phase 4: Generated Code

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

    public static function create(string $value): self
    {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidEmailException($value);
        }

        return new self(mb_strtolower($value));
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function toString(): string
    {
        return $this->value;
    }
}
```

Updated entity:

```php
public static function register(
    UserId $id,
    Email $email,
    string $name,
): self {
    return new self($id, $email, $name, UserStatus::Active);
}
```

### Phase 5: Verification

```markdown
## Post-Refactoring

- [x] All 12 existing tests pass
- [x] 3 new tests added for Email VO (valid, invalid, normalization)
- [x] No behavioral change -- only type strengthened
- [x] No string email left in domain layer
```

## Test This Example

1. Open Claude Code in a Symfony project with a `User` entity using `string $email`
2. Run `/craftsman:refactor`
3. Paste the prompt above
4. Verify Claude analyzes before touching code, preserves tests, and extracts the VO step by step
