---
name: craft-usecase
description: Scaffold a use case with command, handler, and tests following CQRS patterns.
---

# /craft usecase - Use Case Scaffolding

Generate a complete use case following CQRS and Clean Architecture patterns.

## Usage

```
/craft usecase <UseCaseName>
/craft usecase CreateUser
/craft usecase GetUserProfile --query
```

## Process

### Step 1: Gather Requirements

1. **Name**: What action does this use case perform?
2. **Type**: Command (write) or Query (read)?
3. **Input**: What data is required?
4. **Output**: What does it return?
5. **Dependencies**: What repositories/services are needed?

### Step 2: Generate Files

For Command:
```
{config.paths.application}/UseCase/{Name}/
├── {Name}Command.php
├── {Name}Handler.php
└── {Name}Result.php (optional)

{config.paths.tests_unit}/Application/UseCase/{Name}Test.php
```

For Query:
```
{config.paths.application}/UseCase/{Name}/
├── {Name}Query.php
├── {Name}Handler.php
└── {Name}Response.php

{config.paths.tests_unit}/Application/UseCase/{Name}Test.php
```

## Generated Code (Command)

### Command DTO

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

final readonly class {Name}Command
{
    public function __construct(
        public string $field1,
        public string $field2,
        // ... input fields
    ) {
    }
}
```

### Handler

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

use App\Domain\Entity\{Entity};
use App\Domain\Repository\{Entity}RepositoryInterface;

final readonly class {Name}Handler
{
    public function __construct(
        private {Entity}RepositoryInterface $repository,
        // ... other dependencies
    ) {
    }

    public function __invoke({Name}Command $command): {ReturnType}
    {
        // 1. Validate / Load existing data

        // 2. Execute domain logic
        $entity = {Entity}::create(
            // map from command
        );

        // 3. Persist
        $this->repository->save($entity);

        // 4. Return result
        return $entity->id();
    }
}
```

### Result DTO (if complex return)

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

final readonly class {Name}Result
{
    public function __construct(
        public string $id,
        public bool $success,
        public ?string $message = null,
    ) {
    }

    public static function success(string $id): self
    {
        return new self($id, true);
    }

    public static function failure(string $message): self
    {
        return new self('', false, $message);
    }
}
```

## Generated Code (Query)

### Query DTO

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

final readonly class {Name}Query
{
    public function __construct(
        public string $id,
        // ... filter/criteria fields
    ) {
    }
}
```

### Handler

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

use App\Domain\Repository\{Entity}RepositoryInterface;

final readonly class {Name}Handler
{
    public function __construct(
        private {Entity}RepositoryInterface $repository,
    ) {
    }

    public function __invoke({Name}Query $query): ?{Name}Response
    {
        $entity = $this->repository->findById($query->id);

        if ($entity === null) {
            return null;
        }

        return {Name}Response::fromEntity($entity);
    }
}
```

### Response DTO

```php
<?php

declare(strict_types=1);

namespace App\Application\UseCase\{Name};

use App\Domain\Entity\{Entity};

final readonly class {Name}Response
{
    public function __construct(
        public string $id,
        public string $field1,
        // ... output fields
    ) {
    }

    public static function fromEntity({Entity} $entity): self
    {
        return new self(
            id: $entity->id()->toString(),
            field1: $entity->field1()->value(),
        );
    }
}
```

## Unit Test

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Application\UseCase;

use App\Application\UseCase\{Name}\{Name}Command;
use App\Application\UseCase\{Name}\{Name}Handler;
use App\Domain\Repository\{Entity}RepositoryInterface;
use PHPUnit\Framework\TestCase;

final class {Name}HandlerTest extends TestCase
{
    public function test_executes_successfully(): void
    {
        // Arrange
        $repository = $this->createMock({Entity}RepositoryInterface::class);
        $repository->expects(self::once())->method('save');

        $handler = new {Name}Handler($repository);
        $command = new {Name}Command(
            field1: 'value1',
            field2: 'value2',
        );

        // Act
        $result = $handler($command);

        // Assert
        self::assertNotNull($result);
    }

    public function test_validates_input(): void
    {
        // Test validation/guard clauses
    }
}
```

## Options

```
--query       Generate as Query (read operation)
--no-result   Skip result DTO (return entity ID directly)
--no-test     Skip test generation (not recommended)
```

## Naming Conventions

| Action | Command Name | Handler Return |
|--------|--------------|----------------|
| Create | `Create{Entity}Command` | Entity ID |
| Update | `Update{Entity}Command` | void or Result |
| Delete | `Delete{Entity}Command` | void |
| Get | `Get{Entity}Query` | Response DTO |
| List | `List{Entities}Query` | Collection of Response |

## Rules Applied

- Commands are immutable (`readonly`)
- Handlers have single responsibility
- Dependencies injected via constructor
- No framework coupling in Application layer
