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

---

## API Platform 4 (Symfony)

### State Providers (Read)

```php
// Replaces DataProvider from v2/v3
final class UserStateProvider implements ProviderInterface
{
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        if ($operation instanceof CollectionOperationInterface) {
            [$page, , $limit] = $this->pagination->getPagination($operation, $context);
            return $this->repository->findPaginated($page, $limit);
        }
        return $this->repository->findById(UserId::fromString($uriVariables['id']));
    }
}
```

### State Processors (Write)

```php
// Replaces DataPersister from v2/v3
final class CreateUserProcessor implements ProcessorInterface
{
    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        $this->commandBus->dispatch(CreateUserCommand::fromApiResource($data));
    }
}
```

### Resource Declaration

```php
#[ApiResource(operations: [
    new GetCollection(provider: UserStateProvider::class),
    new Get(provider: UserStateProvider::class),
    new Post(processor: CreateUserProcessor::class),
])]
final class UserResource { /* DTOs, not entities */ }
```

| Rule | Reason |
|------|--------|
| Providers/Processors are final | All classes MUST be final |
| Resources are DTOs, not Doctrine entities | Clean Architecture: domain decoupled from HTTP layer |
| Command Bus in Processors | Application layer owns use cases |

---

## Symfony Messenger

### Handler Pattern

```php
#[AsMessageHandler]
final class CreateUserHandler
{
    public function __invoke(CreateUserCommand $command): void
    {
        $user = User::create(UserId::generate(), Email::fromString($command->email));
        $this->repository->save($user);
        foreach ($user->releaseEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }
}
```

| Rule | Reason |
|------|--------|
| One `__invoke` per handler | Single Responsibility |
| Release domain events after save | Transactional consistency |
| No direct HTTP calls in handlers | Use sub-messages for fan-out |

---

## MapRequestPayload (Symfony 6.3+)

```php
#[Route('/api/users', methods: ['POST'])]
public function create(
    #[MapRequestPayload] CreateUserInput $input,
): JsonResponse {
    $this->commandBus->dispatch(CreateUserCommand::fromInput($input));
    return new JsonResponse(null, Response::HTTP_CREATED);
}
```

---

## API Platform Input DTOs

```php
#[ApiResource(
    operations: [
        new Post(
            input: CreateUserInput::class,
            processor: CreateUserProcessor::class,
        ),
    ]
)]
final class UserResource { }
```

---

## Symfony Scheduler (7.4+)

```php
#[AsSchedule('default')]
final class AppScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        return (new Schedule())
            ->add(RecurringMessage::every('1 hour', new CleanExpiredTokensCommand()))
            ->add(RecurringMessage::cron('0 2 * * *', new GenerateDailyReportCommand()));
    }
}
```

| Rule | Reason |
|------|--------|
| Scheduled tasks dispatch Commands | Handlers reusable from CLI and Scheduler |
| Use `RecurringMessage::cron()` for complex schedules | More expressive than `every()` |

---

## React 19 Server Components

### Decision tree

```
Is the component interactive? (onClick, useState, useEffect, browser APIs)
  YES → "use client"
  NO  → Server Component (default, no directive needed)
```

### Key rules

| Rule | Reason |
|------|--------|
| `async` functions for data fetching | Native async/await in Server Components |
| Wrap independently-fetched children in `<Suspense>` | Streaming — users see content earlier |
| `"use client"` boundaries should be leaves | Minimizes client bundle size |
| No `useState`/`useEffect` in Server Components | They run on server — no browser state |

---

## React Composition Patterns

### Compound Components

Use when sub-components are always used together and need coordinated state.

```tsx
// Context with null guard
const TabsContext = createContext<TabsContextType | null>(null);

function useTabsContext() {
  const ctx = use(TabsContext);
  if (ctx === null) throw new Error('Must be inside <Tabs>');
  return ctx;
}
```

### Render Props (Modern)

Use with `useSuspenseQuery` for data-driven render delegation.

```tsx
function DataLoader<T>({ queryKey, queryFn, children }: DataLoaderProps<T>) {
  const { data } = useSuspenseQuery({ queryKey, queryFn });
  return <>{children(data)}</>;
}
```

| Rule | Reason |
|------|--------|
| Context type includes `null` | Forces explicit error on misuse |
| Internal `useXxx` hook guards context access | Consumers never handle `null` manually |
| Compound component sub-parts exported as named exports | No default exports (TS rule ts-004) |

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
