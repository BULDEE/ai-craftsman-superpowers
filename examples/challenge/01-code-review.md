# Example: Code Review with /challenge

## Prompt

```
/craftsman:challenge

Review this PHP code:

<?php

namespace App\Service;

use Doctrine\ORM\EntityManagerInterface;

class UserService
{
    private $em;
    private $mailer;

    public function __construct(EntityManagerInterface $em, $mailer)
    {
        $this->em = $em;
        $this->mailer = $mailer;
    }

    public function createUser($data)
    {
        $user = new \App\Entity\User();
        $user->setEmail($data['email']);
        $user->setPassword($data['password']);
        $user->setCreatedAt(new \DateTime());

        $this->em->persist($user);
        $this->em->flush();

        $this->mailer->send($user->getEmail(), 'Welcome!', 'Welcome to our platform');

        return $user;
    }

    public function getUsers($filters = [])
    {
        $qb = $this->em->createQueryBuilder()
            ->select('u')
            ->from(\App\Entity\User::class, 'u');

        if (isset($filters['status'])) {
            $qb->where("u.status = '" . $filters['status'] . "'");
        }

        return $qb->getQuery()->getResult();
    }
}
```

## Expected Response

```markdown
# Architecture Review: UserService

## Summary

| Metric | Value |
|--------|-------|
| **Verdict** | REJECT |
| **Blocking Issues** | 3 |
| **Must Fix** | 5 |
| **Suggestions** | 4 |

---

## BLOCKING Issues (Must fix before merge)

### 1. SQL Injection Vulnerability
**Location:** Line 35
**Severity:** CRITICAL

```php
// VULNERABLE
$qb->where("u.status = '" . $filters['status'] . "'");
```

**Fix:**
```php
$qb->where('u.status = :status')
   ->setParameter('status', $filters['status']);
```

### 2. Plain Text Password Storage
**Location:** Line 18
**Severity:** CRITICAL

Password stored without hashing. Use `password_hash()` or Symfony's PasswordHasher.

### 3. Missing `declare(strict_types=1)`
**Location:** File header
**Severity:** BLOCKING (per project rules)

---

## MUST FIX Issues

### 4. Missing `final` class keyword
Per project standards, all classes must be `final`.

### 5. Untyped parameters
`$data`, `$mailer` lack type hints.

### 6. Public setters (anemic domain)
`setEmail()`, `setPassword()` expose internal state.

### 7. `new \DateTime()`
Use injected Clock abstraction per project rules.

### 8. God Service
Service handles user creation AND querying. Split responsibilities.

---

## Suggestions

1. Use Email Value Object instead of raw string
2. Emit UserCreatedEvent for side effects
3. Move mailer to event subscriber
4. Add unit tests

---

## Recommended Refactoring

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase;

final class CreateUserHandler
{
    public function __construct(
        private readonly UserRepositoryInterface $users,
        private readonly PasswordHasherInterface $hasher,
        private readonly ClockInterface $clock,
    ) {
    }

    public function __invoke(CreateUserCommand $command): UserId
    {
        $user = User::register(
            UserId::generate(),
            Email::fromString($command->email),
            $this->hasher->hash($command->password),
            $this->clock->now(),
        );

        $this->users->save($user);

        return $user->id();
    }
}
```
```

## Test This Example

1. Save the bad code to a test file
2. Run `/craftsman:challenge`
3. Paste the code
4. Verify Claude identifies ALL issues (minimum 10)
5. Check verdict is REJECT for blocking issues
