# Stack-Specific Rules Reference

## PHP (Symfony)

### Always

```php
declare(strict_types=1);

final class User
{
    private function __construct(
        private readonly UserId $id,
        private readonly Email $email,
    ) {}

    public static function create(Email $email): self
    {
        return new self(UserId::generate(), $email);
    }

    public function changeEmail(Email $newEmail): void
    {
        // Behavior method, not setter
    }
}

// Value Object
final readonly class Email
{
    private function __construct(
        public string $value
    ) {}

    public static function create(string $value): self
    {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidEmail($value);
        }
        return new self($value);
    }
}
```

### Never

| Don't | Why |
|-------|-----|
| `// Comment explaining code` | Code should be self-explanatory |
| `public function setName()` | Use behavior methods |
| `catch (Exception $e) { }` | No empty catches |
| `new DateTime()` | Use Clock abstraction |
| `class Foo` without final | All classes must be final |

---

## TypeScript (React)

### Always

```typescript
// Branded types for Value Objects
type UserId = string & { readonly __brand: 'UserId' };
type Email = string & { readonly __brand: 'Email' };

// Discriminated unions for results
type Result<T> =
  | { success: true; data: T }
  | { success: false; error: string };

// Explicit return types
function createUser(email: Email): Result<User> {
  // ...
}

// Readonly by default
interface User {
  readonly id: UserId;
  readonly email: Email;
  readonly createdAt: Date;
}
```

### Never

| Don't | Why | Do Instead |
|-------|-----|------------|
| `any` | Type safety | `unknown` or proper type |
| `!` (non-null assertion) | Hides bugs | Handle null explicitly |
| `as Type` without validation | Unsafe | Type guards |
| `export default` | Harder to refactor | Named exports |
| Business logic in components | Separation | Use hooks/services |

---

## Testing

### Structure

```php
// PHP - Arrange-Act-Assert
public function test_should_reject_invalid_email(): void
{
    // Arrange
    $invalidEmail = 'not-an-email';

    // Act & Assert
    $this->expectException(InvalidEmail::class);
    Email::create($invalidEmail);
}
```

```typescript
// TypeScript - Describe-It
describe('Email', () => {
  it('should reject invalid email', () => {
    expect(() => createEmail('invalid')).toThrow();
  });
});
```

### Naming Convention

```
test_should_<expected_behavior>_when_<condition>
should_return_error_when_email_invalid
should_create_user_when_valid_data
```

---

## Security Essentials

| Risk | Prevention |
|------|------------|
| SQL Injection | Parameterized queries (Doctrine handles) |
| XSS | Output encoding, CSP headers |
| CSRF | Token validation (Symfony handles) |
| Auth bypass | Server-side permission check |
| Sensitive data | Encrypt at rest, HTTPS |

---

## Database

| Pattern | When |
|---------|------|
| Eager loading | Prevent N+1 |
| Indexes | Frequently queried columns |
| Pagination | Large datasets |
| Transactions | Multi-step operations |
| Read replicas | Heavy read loads |
