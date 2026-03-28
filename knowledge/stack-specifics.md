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

## Symfony Messenger

Source: https://symfony.com/doc/current/messenger.html

### Handler declaration

```php
// Auto-discovered — no services.yaml tag needed
#[AsMessageHandler]
final readonly class CreateOrderHandler
{
    public function __invoke(CreateOrderCommand $command): void { }
}
```

### Routing (YAML)

```yaml
# Wildcard MUST be at the END of the namespace prefix
framework:
    messenger:
        routing:
            'App\Application\UseCase\*': async
            'App\Application\Query\*': sync
```

### Retry strategy keys

```yaml
retry_strategy:
    max_retries: 3
    delay: 1000       # ms before first retry
    multiplier: 2     # 1s → 2s → 4s
    max_delay: 0      # 0 = no cap
    jitter: 0.1       # randomness factor (0–1.0)
```

### Never

| Don't | Why |
|-------|-----|
| `tags: [messenger.message_handler]` | Replaced by `#[AsMessageHandler]` attribute |
| Read return value of `dispatch()` | Returns `Envelope`, not handler output |
| Non-void handler return with async transport | Result is never accessible to caller |

---

## Symfony Scheduler

Source: https://symfony.com/doc/current/scheduler.html

```php
#[AsSchedule('default')]  // 'default' is the default; transport: scheduler_default
final class MyScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        return $this->schedule ??= (new Schedule())
            ->with(
                RecurringMessage::cron('0 8 * * 1', new WeeklyReportMessage()),
                RecurringMessage::every('1 hour', new SyncInventoryMessage()),
            );
    }
}
```

### RecurringMessage signatures

```php
RecurringMessage::cron(string $spec, object $message, ?\DateTimeZone $tz = null): self
RecurringMessage::every(string|int|\DateInterval $freq, object $message, ?\DateTimeImmutable $from = null, ?string $until = null): self
```

### Cron shorthand aliases

`@daily`, `@weekly`, `@monthly`, `@hourly` — all valid in `cron()` spec.

### Consume

```bash
php bin/console messenger:consume scheduler_default
```

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

## React 19 — New Hooks (verified)

Sources:
- https://react.dev/reference/react/use
- https://react.dev/reference/react/useOptimistic
- https://react.dev/reference/react/useTransition
- https://react.dev/reference/rsc/use-server

### `use(resource)` — replaces `useContext`, reads Promises

```typescript
import { use } from 'react';

// Read context — preferred over useContext() in React 19
// Advantage: works inside conditionals and loops
const theme = use(ThemeContext);

// Read a Promise passed from a Server Component
// Must be wrapped in <Suspense> (loading) and <ErrorBoundary> (errors)
const user = use(userPromise);
```

TypeScript signature: `function use<T>(resource: Promise<T> | Context<T>): T`

Constraints:
- Cannot be called in `try-catch` blocks
- Cannot be called in event handlers
- Create Promises in Server Components and pass to Client Components — Client-side Promises recreate on every render

### `useOptimistic` — optimistic UI updates

```typescript
import { useOptimistic } from 'react';

// Signature: useOptimistic(state, reducer?)
// Returns: [optimisticState, setOptimistic]
// Source: https://react.dev/reference/react/useOptimistic

const [optimisticItems, addOptimisticItem] = useOptimistic(
  items,
  (currentItems, newItem: Item) => [...currentItems, newItem],
);

// MUST be called inside a Transition or Server Action
startTransition(async () => {
  addOptimisticItem(newItem);      // Immediate UI update
  await serverApi.save(newItem);   // Real update — reverts if it fails
});
```

Constraints:
- `setOptimistic` MUST be called inside `startTransition` or a form action
- Calling outside a Transition produces a warning and the update reverts immediately
- Optimistic state is temporary — automatically converges to real state after the action completes

### `useTransition` — non-urgent state updates

```typescript
import { useTransition } from 'react';

// Returns: [isPending, startTransition]
// isPending: boolean — true while the transition is processing
// Source: https://react.dev/reference/react/useTransition

const [isPending, startTransition] = useTransition();

startTransition(async () => {
  await updateServer(newValue);
  // State updates after await need another startTransition:
  startTransition(() => setState(result));
});
```

Constraints:
- Cannot use with controlled inputs (`<input value={...}>`)
- `setTimeout` inside `startTransition` is NOT marked as a Transition — wrap the callback inside `startTransition` after the `await`
- Prefer `useTransition` over manual `useState` loading flags (Vercel rule 6.11)

### `useActionState` — form actions with state (React 19)

```typescript
import { useActionState } from 'react';

// Handles Server Action return values and pending state
// Source: https://react.dev/reference/rsc/use-server

async function submitForm(prevState: FormState, formData: FormData): Promise<FormState> {
  'use server';
  const name = formData.get('name');
  if (typeof name !== 'string') return { error: 'Name is required' };
  await userApi.updateName(name);
  return { success: true };
}

// In Client Component:
const [state, action, isPending] = useActionState(submitForm, { success: false });

return (
  <form action={action}>
    <input name="name" />
    {state.error && <p>{state.error}</p>}
    <button disabled={isPending}>Save</button>
  </form>
);
```

### `<form action={fn}>` — React 19 Server Actions in forms

This is **real React 19**, not a Next.js-only feature.

```typescript
// Progressive enhancement: works before JavaScript loads
// Automatic FormData as first argument
// Automatic Transition wrapping

async function createUser(formData: FormData): Promise<void> {
  'use server';
  // Validate and authorize — treat all arguments as untrusted
  const email = formData.get('email');
  if (typeof email !== 'string') return;
  await userApi.create({ email });
}

export function CreateUserForm(): ReactNode {
  return (
    <form action={createUser}>
      <input type="email" name="email" />
      <button type="submit">Create</button>
    </form>
  );
}
```

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

## API Platform 4 (Symfony)

> Verified against official docs: https://api-platform.com/docs/core/state-providers/,
> https://api-platform.com/docs/core/state-processors/, https://api-platform.com/docs/core/dto/,
> https://api-platform.com/docs/core/pagination/

### Interface Signatures (exact — AP4)

```php
// ProviderInterface — ApiPlatform\State\ProviderInterface
public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null;

// ProcessorInterface — ApiPlatform\State\ProcessorInterface
// Generic hint: @implements ProcessorInterface<T, T|void>
public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed;
```

### Key Namespaces

| Symbol | Namespace |
|--------|-----------|
| `ProviderInterface` | `ApiPlatform\State\ProviderInterface` |
| `ProcessorInterface` | `ApiPlatform\State\ProcessorInterface` |
| `Operation` | `ApiPlatform\Metadata\Operation` |
| `CollectionOperationInterface` | `ApiPlatform\Metadata\CollectionOperationInterface` |
| `DeleteOperationInterface` | `ApiPlatform\Metadata\DeleteOperationInterface` |
| `ArrayPaginator` | `ApiPlatform\State\Pagination\ArrayPaginator` |
| `TraversablePaginator` | `ApiPlatform\State\Pagination\TraversablePaginator` |
| `PaginatorInterface` | `ApiPlatform\State\Pagination\PaginatorInterface` |
| `PartialPaginatorInterface` | `ApiPlatform\State\Pagination\PartialPaginatorInterface` |
| `#[Map]` attribute | `Symfony\Component\ObjectMapper\Attribute\Map` |
| `Options` (Doctrine) | `ApiPlatform\Doctrine\Orm\State\Options` |

### DTO-First Pattern (recommended in AP4)

AP4 recommends using API Resources (DTOs) separate from Doctrine entities:

```php
#[ApiResource(
    stateOptions: new Options(entityClass: BookEntity::class),
    operations: [
        new Get(provider: BookProvider::class),
        new GetCollection(output: BookCollection::class),
        new Post(input: CreateBook::class, processor: BookProcessor::class),
        new Patch(input: UpdateBook::class, processor: BookProcessor::class),
    ],
)]
#[Map(source: BookEntity::class)]
final class Book { /* DTO fields */ }
```

Input DTO (write):
```php
#[Map(target: BookEntity::class)]
final class CreateBook
{
    #[Map(target: 'title')]
    public string $name;
}
```

Output DTO (read, collection):
```php
#[Map(source: BookEntity::class)]
final class BookCollection
{
    #[Map(source: 'title')]
    public string $name;
}
```

### State Provider: Collection vs Item

Use `CollectionOperationInterface` to branch — **still valid in AP4**:

```php
use ApiPlatform\Metadata\CollectionOperationInterface;

public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
{
    if ($operation instanceof CollectionOperationInterface) {
        return $this->repository->findAll();
    }
    return $this->repository->findById($uriVariables['id']);
}
```

### Built-in Service IDs (Symfony autowire)

```php
#[Autowire(service: 'api_platform.doctrine.orm.state.item_provider')]
#[Autowire(service: 'api_platform.doctrine.orm.state.persist_processor')]
#[Autowire(service: 'api_platform.doctrine.orm.state.remove_processor')]
```

### Pagination — Custom State Providers

For custom providers, return an instance of `PaginatorInterface` or `PartialPaginatorInterface`,
not a plain array, to get Hydra pagination links (first/last/next/prev):

```php
use ApiPlatform\State\Pagination\ArrayPaginator;

// ArrayPaginator(iterable $results, int $firstResult, int $maxResults, int $totalItems)
return new ArrayPaginator($items, $offset, $limit, $total);
```

### Never

| Don't | Why | Do Instead |
|-------|-----|------------|
| Doctrine entity directly as `#[ApiResource]` | Couples persistence to API surface | Separate DTO Resource class |
| Return plain `array` for collections in custom providers | Breaks pagination/Hydra response | Return `PaginatorInterface` implementation |
| `input:` at `#[ApiResource]` level | Not how AP4 DTOs work | Declare `input:` on each operation |

---

## Vercel React Best Practices (verified)

Source: https://github.com/vercel-labs/agent-skills/blob/main/skills/react-best-practices/AGENTS.md
(40+ rules across 8 categories — full list at source. Top 10 most impactful below.)

### 1. Avoid Barrel File Imports (CRITICAL — 200–800ms cost)

Import directly from source files. Barrel files force loading all re-exported modules.

```typescript
// BAD
import { Button, Input } from '@/components/ui';
// GOOD
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
```

See: `knowledge/anti-patterns/barrel-imports.md`

### 2. Strategic Suspense Boundaries (CRITICAL)

Use `<Suspense>` to show the wrapper UI faster while data loads, instead of awaiting everything before returning JSX.

```tsx
// BAD — blocks entire page on slow data
export async function Page(): Promise<ReactNode> {
  const [user, activities] = await Promise.all([getUser(), getActivities()]);
  return <Layout><UserCard user={user} /><Feed items={activities} /></Layout>;
}

// GOOD — layout renders immediately, data streams in
export async function Page(): Promise<ReactNode> {
  return (
    <Layout>
      <Suspense fallback={<Skeleton />}><UserCard /></Suspense>
      <Suspense fallback={<Skeleton />}><Feed /></Suspense>
    </Layout>
  );
}
```

### 3. Promise.all() for Independent Operations (CRITICAL)

Never await independent async operations sequentially.

```typescript
// BAD — sequential (slow)
const user = await getUser(id);
const posts = await getPosts(id);

// GOOD — parallel
const [user, posts] = await Promise.all([getUser(id), getPosts(id)]);
```

### 4. Do Not Define Components Inside Components (MEDIUM)

Inline components remount on every parent render, destroying state.
See: `knowledge/anti-patterns/inline-components.md`

### 5. Use Transitions for Non-Urgent Updates (MEDIUM)

Prefer `useTransition` over manual `useState` loading flags.

```typescript
// BAD
const [isLoading, setIsLoading] = useState(false);
const handleClick = async () => { setIsLoading(true); await action(); setIsLoading(false); };

// GOOD
const [isPending, startTransition] = useTransition();
const handleClick = () => startTransition(async () => { await action(); });
```

### 6. Per-Request Deduplication with React.cache() (HIGH)

Deduplicate identical async operations within a single request in Server Components.

```typescript
import { cache } from 'react';

const getUser = cache(async (id: UserId): Promise<User> => {
  return db.users.findById(id);
});
// Multiple components can call getUser(id) — only one DB query per request
```

### 7. Authenticate Server Actions Like API Routes (HIGH)

Every Server Action is a public endpoint. Always verify auth and authorization inside.

```typescript
async function deletePost(postId: string): Promise<void> {
  'use server';
  const session = await getServerSession();
  if (!session) throw new Error('Unauthorized');
  const post = await db.posts.findById(postId);
  if (post.authorId !== session.userId) throw new Error('Forbidden');
  await db.posts.delete(postId);
}
```

### 8. Minimize Serialization at RSC Boundaries (HIGH)

Pass only fields the client component actually uses across the Server/Client boundary.

```typescript
// BAD — entire user object serialized (including sensitive fields)
<ClientCard user={user} />

// GOOD — only needed fields
<ClientCard name={user.name} avatarUrl={user.avatarUrl} />
```

### 9. Calculate Derived State During Rendering (MEDIUM)

Compute values from current props/state during render — never store them in state or update them in effects.

```typescript
// BAD
const [fullName, setFullName] = useState('');
useEffect(() => { setFullName(`${firstName} ${lastName}`); }, [firstName, lastName]);

// GOOD
const fullName = `${firstName} ${lastName}`; // Computed during render
```

### 10. Use Explicit Conditional Rendering — Ternary Over && (MEDIUM)

`&&` renders falsy values like `0` and `NaN`. Always use ternary for safety.

```tsx
// BAD — renders "0" when count is 0
{count && <Badge>{count}</Badge>}

// GOOD
{count > 0 ? <Badge>{count}</Badge> : null}
```

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
