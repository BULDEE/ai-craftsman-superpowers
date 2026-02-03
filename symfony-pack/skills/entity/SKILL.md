---
name: craft-entity
description: Scaffold a DDD entity with value objects, events, repository interface, and tests.
---

# /craft entity - DDD Entity Scaffolding

Generate a complete DDD entity following Clean Architecture patterns.

## Usage

```
/craft entity <EntityName>
/craft entity User
/craft entity Order --aggregate
```

## Process

### Step 1: Gather Requirements

Ask the user:

1. **Entity name**: What is the entity called?
2. **Is aggregate root?**: Is this the main entry point for a bounded context?
3. **Fields**: What data does it hold?
4. **Behaviors**: What actions can it perform?
5. **Events**: What state changes should emit events?

### Step 2: Field Definition

For each field, determine:

```
Field: email
- Type: Value Object (Email) or Primitive (string)?
- Required: Yes/No
- Immutable: Yes/No

Recommendation: Use Value Object for domain primitives
```

### Step 3: Generate Files

```
{config.paths.domain}/Entity/{Name}.php
{config.paths.domain}/Event/{Name}CreatedEvent.php
{config.paths.domain}/Repository/{Name}RepositoryInterface.php
{config.paths.tests_unit}/Domain/Entity/{Name}Test.php
```

## Generated Code

### Entity

```php
<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\{Name}CreatedEvent;
use App\Domain\ValueObject\{Field}; // For each VO field
use DateTimeImmutable;
use Symfony\Component\Uid\Uuid;

final class {Name}
{
    /** @var array<DomainEventInterface> */
    private array $domainEvents = [];

    private function __construct(
        private readonly Uuid $id,
        private {FieldType} ${fieldName},
        // ... other fields
        private readonly DateTimeImmutable $createdAt,
        private ?DateTimeImmutable $updatedAt = null,
    ) {
    }

    public static function create(
        {FieldType} ${fieldName},
        // ... required fields
    ): self {
        $entity = new self(
            id: Uuid::v7(),
            {fieldName}: ${fieldName},
            createdAt: new DateTimeImmutable(),
        );

        $entity->raise(new {Name}CreatedEvent(
            id: $entity->id,
            occurredAt: $entity->createdAt,
        ));

        return $entity;
    }

    // Getters (readonly)
    public function id(): Uuid
    {
        return $this->id;
    }

    public function {fieldName}(): {FieldType}
    {
        return $this->{fieldName};
    }

    // Behavior methods (not setters!)
    public function {behaviorMethod}({params}): void
    {
        // Validation/guards
        // State change
        // Raise event
        $this->updatedAt = new DateTimeImmutable();
    }

    // Domain events
    private function raise(DomainEventInterface $event): void
    {
        $this->domainEvents[] = $event;
    }

    /** @return array<DomainEventInterface> */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];
        return $events;
    }
}
```

### Domain Event

```php
<?php

declare(strict_types=1);

namespace App\Domain\Event;

use App\Domain\Event\DomainEventInterface;
use DateTimeImmutable;
use Symfony\Component\Uid\Uuid;

final readonly class {Name}CreatedEvent implements DomainEventInterface
{
    public function __construct(
        public Uuid $id,
        public DateTimeImmutable $occurredAt,
    ) {
    }

    public function occurredAt(): DateTimeImmutable
    {
        return $this->occurredAt;
    }
}
```

### Repository Interface

```php
<?php

declare(strict_types=1);

namespace App\Domain\Repository;

use App\Domain\Entity\{Name};
use Symfony\Component\Uid\Uuid;

interface {Name}RepositoryInterface
{
    public function save({Name} $entity): void;

    public function findById(Uuid $id): ?{Name};

    public function remove({Name} $entity): void;
}
```

### Unit Test

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Entity;

use App\Domain\Entity\{Name};
use App\Domain\Event\{Name}CreatedEvent;
use PHPUnit\Framework\TestCase;

final class {Name}Test extends TestCase
{
    public function test_can_be_created(): void
    {
        // Arrange
        ${fieldName} = /* valid value */;

        // Act
        $entity = {Name}::create(${fieldName});

        // Assert
        self::assertNotNull($entity->id());
        self::assertEquals(${fieldName}, $entity->{fieldName}());
    }

    public function test_raises_created_event(): void
    {
        // Arrange & Act
        $entity = {Name}::create(/* params */);
        $events = $entity->pullDomainEvents();

        // Assert
        self::assertCount(1, $events);
        self::assertInstanceOf({Name}CreatedEvent::class, $events[0]);
    }

    public function test_{behavior}_changes_state(): void
    {
        // Arrange
        $entity = {Name}::create(/* params */);

        // Act
        $entity->{behavior}(/* params */);

        // Assert
        self::assertEquals(/* expected */, $entity->/* getter */());
    }
}
```

## Options

```
--aggregate    Mark as aggregate root
--no-events    Skip event generation
--no-test      Skip test generation (not recommended)
```

## Rules Applied

From `.craft-config.yml`:

- `final_classes: true` → All classes are final
- `private_constructors: true` → Private constructor + static factory
- `no_setters: true` → Behavior methods only
- `strict_types: true` → declare(strict_types=1)
