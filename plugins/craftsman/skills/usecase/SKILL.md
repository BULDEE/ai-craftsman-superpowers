---
name: usecase
description: |
  Scaffold Use Case with Command/Handler pattern for Symfony/PHP.
  Use when implementing application layer use cases.

  ACTIVATES AUTOMATICALLY when detecting: "use case", "command handler",
  "application service", "CQRS", PHP/Symfony context
model: sonnet
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
---

# UseCase Skill - Command/Handler Scaffolding (Symfony)

Scaffold a complete Use Case with Command, Handler, and Tests following CQRS principles.

## Generated Structure

```
src/
├── Application/
│   └── UseCase/
│       └── {UseCaseName}/
│           ├── {UseCaseName}Command.php
│           ├── {UseCaseName}Handler.php
│           └── {UseCaseName}Response.php (optional)
tests/
└── Unit/
    └── Application/
        └── UseCase/
            └── {UseCaseName}HandlerTest.php
```

## Command Template

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{UseCaseName};

final readonly class {UseCaseName}Command
{
    public function __construct(
        public string $userId,
        // Add other properties with explicit types
    ) {
    }
}
```

## Handler Template

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{UseCaseName};

use App\Domain\Repository\{Entity}RepositoryInterface;
use App\Domain\ValueObject\{Entity}Id;

final readonly class {UseCaseName}Handler
{
    public function __construct(
        private {Entity}RepositoryInterface $repository,
        // Other dependencies (max 3-4)
    ) {
    }

    public function __invoke({UseCaseName}Command $command): {UseCaseName}Response
    {
        // 1. Validate/Transform input
        $id = {Entity}Id::fromString($command->userId);

        // 2. Load domain objects
        $entity = $this->repository->findById($id)
            ?? throw {Entity}NotFoundException::withId($id);

        // 3. Execute domain logic
        $entity->doSomething();

        // 4. Persist changes
        $this->repository->save($entity);

        // 5. Return response
        return new {UseCaseName}Response($entity->id()->toString());
    }
}
```

## Response Template

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{UseCaseName};

final readonly class {UseCaseName}Response
{
    public function __construct(
        public string $id,
        // Other response fields
    ) {
    }
}
```

## Handler Test Template

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\UseCase;

use App\Application\UseCase\{UseCaseName}\{UseCaseName}Command;
use App\Application\UseCase\{UseCaseName}\{UseCaseName}Handler;
use App\Domain\Entity\{Entity};
use App\Domain\Repository\{Entity}RepositoryInterface;
use App\Domain\ValueObject\{Entity}Id;
use PHPUnit\Framework\TestCase;

final class {UseCaseName}HandlerTest extends TestCase
{
    private {Entity}RepositoryInterface $repository;
    private {UseCaseName}Handler $handler;

    protected function setUp(): void
    {
        $this->repository = $this->createMock({Entity}RepositoryInterface::class);
        $this->handler = new {UseCaseName}Handler($this->repository);
    }

    public function test_executes_successfully(): void
    {
        // Arrange
        $entityId = {Entity}Id::generate();
        $entity = {Entity}::create($entityId);

        $this->repository
            ->expects(self::once())
            ->method('findById')
            ->willReturn($entity);

        $this->repository
            ->expects(self::once())
            ->method('save');

        $command = new {UseCaseName}Command($entityId->toString());

        // Act
        $response = ($this->handler)($command);

        // Assert
        self::assertSame($entityId->toString(), $response->id);
    }

    public function test_throws_when_entity_not_found(): void
    {
        // Arrange
        $this->repository
            ->method('findById')
            ->willReturn(null);

        $command = new {UseCaseName}Command({Entity}Id::generate()->toString());

        // Assert
        $this->expectException({Entity}NotFoundException::class);

        // Act
        ($this->handler)($command);
    }
}
```

## Symfony Messenger Integration

```php
// config/services.yaml
services:
    App\Application\UseCase\{UseCaseName}\{UseCaseName}Handler:
        tags: [messenger.message_handler]
```

```php
// Usage in Controller
public function __invoke(
    {UseCaseName}Command $command,
    MessageBusInterface $bus,
): Response {
    $response = $bus->dispatch($command);

    return new JsonResponse(['id' => $response->id]);
}
```

## Rules Enforced

| Rule | Enforcement |
|------|-------------|
| Single Responsibility | One use case = one action |
| Command immutability | `readonly` class |
| Max 3-4 dependencies | Constructor injection |
| No business logic | Delegate to domain |
| Explicit types | All properties typed |

## Process

1. **Ask for use case name and action**
2. **Identify involved entities**
3. **Generate Command**
4. **Generate Handler**
5. **Generate Response (if needed)**
6. **Generate Tests**
7. **Verify**

```bash
vendor/bin/phpstan analyse src/Application/UseCase/{UseCaseName}/
vendor/bin/phpunit --filter={UseCaseName}HandlerTest
```

## Anti-Patterns to Avoid

- Handler doing too much (>1 responsibility)
- Business logic in handler (should be in domain)
- Missing error handling
- No tests
