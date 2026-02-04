---
name: entity
description: |
  Scaffold DDD Entity with Value Objects, Events, and Tests for Symfony/PHP.
  Use when creating domain entities in a Symfony project.

  ACTIVATES AUTOMATICALLY when detecting: "entity", "aggregate",
  "Doctrine entity", "create [noun] entity", PHP/Symfony context
model: sonnet
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
---

# Entity Skill - DDD Entity Scaffolding (Symfony)

Scaffold a complete DDD Entity with Value Objects, Domain Events, and Tests.

## Prerequisites

Verify Symfony/PHP project:
- `composer.json` exists
- `src/Domain/` or `src/Entity/` structure
- PHPUnit configured

## Generated Structure

```
src/
├── Domain/
│   ├── Entity/
│   │   └── {Name}.php
│   ├── ValueObject/
│   │   └── {Name}Id.php
│   ├── Event/
│   │   └── {Name}CreatedEvent.php
│   └── Exception/
│       └── Invalid{Name}Exception.php
tests/
└── Unit/
    └── Domain/
        ├── Entity/
        │   └── {Name}Test.php
        └── ValueObject/
            └── {Name}IdTest.php
```

## Entity Template

```php
<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\{Name}CreatedEvent;
use App\Domain\ValueObject\{Name}Id;

final class {Name}
{
    /** @var object[] */
    private array $domainEvents = [];

    private function __construct(
        private readonly {Name}Id $id,
        // Add other properties
    ) {
    }

    public static function create(
        {Name}Id $id,
        // Constructor parameters
    ): self {
        $entity = new self($id);
        $entity->record(new {Name}CreatedEvent($id));

        return $entity;
    }

    public function id(): {Name}Id
    {
        return $this->id;
    }

    // Behavior methods (not setters!)

    /** @return object[] */
    public function releaseEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }

    private function record(object $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

## Value Object Template (ID)

```php
<?php

declare(strict_types=1);

namespace App\Domain\ValueObject;

use Symfony\Component\Uid\Uuid;

final class {Name}Id
{
    private function __construct(
        private readonly string $value,
    ) {
    }

    public static function generate(): self
    {
        return new self(Uuid::v7()->toString());
    }

    public static function fromString(string $value): self
    {
        if (!Uuid::isValid($value)) {
            throw new \InvalidArgumentException(
                sprintf('Invalid {Name}Id: %s', $value)
            );
        }

        return new self($value);
    }

    public function toString(): string
    {
        return $this->value;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }
}
```

## Domain Event Template

```php
<?php

declare(strict_types=1);

namespace App\Domain\Event;

use App\Domain\ValueObject\{Name}Id;

final readonly class {Name}CreatedEvent
{
    public function __construct(
        public {Name}Id $id,
        public \DateTimeImmutable $occurredAt = new \DateTimeImmutable(),
    ) {
    }
}
```

## Test Template

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Entity;

use App\Domain\Entity\{Name};
use App\Domain\Event\{Name}CreatedEvent;
use App\Domain\ValueObject\{Name}Id;
use PHPUnit\Framework\TestCase;

final class {Name}Test extends TestCase
{
    public function test_can_be_created(): void
    {
        $id = {Name}Id::generate();

        ${name} = {Name}::create($id);

        self::assertTrue($id->equals(${name}->id()));
    }

    public function test_records_created_event(): void
    {
        $id = {Name}Id::generate();

        ${name} = {Name}::create($id);
        $events = ${name}->releaseEvents();

        self::assertCount(1, $events);
        self::assertInstanceOf({Name}CreatedEvent::class, $events[0]);
    }

    public function test_releases_events_only_once(): void
    {
        ${name} = {Name}::create({Name}Id::generate());

        ${name}->releaseEvents();
        $secondRelease = ${name}->releaseEvents();

        self::assertEmpty($secondRelease);
    }
}
```

## Rules Enforced

| Rule | Enforcement |
|------|-------------|
| `final class` | All classes are final |
| `declare(strict_types=1)` | Every file |
| Private constructor | Factory method pattern |
| No setters | Behavior methods only |
| Domain events | State changes emit events |
| Value Objects | IDs are always VOs |

## Process

### Step 0: MANDATORY - Load Canonical Examples

**BEFORE generating any code, you MUST use the Read tool to load:**

```
Read: knowledge/canonical/php-entity.php
Read: knowledge/canonical/php-value-object.php
Read: knowledge/anti-patterns/php-anemic-domain.md
```

This ensures generated code matches project standards exactly.

### Steps

1. **Load canonical examples** (Step 0 above - NON-NEGOTIABLE)
2. **Ask for entity name and properties**
3. **Generate ID Value Object + Test**
4. **Generate Entity + Test**
5. **Generate Domain Event**
6. **Run verification**

```bash
vendor/bin/phpstan analyse src/Domain/Entity/{Name}.php
vendor/bin/phpunit --filter={Name}Test
```

## Anti-Patterns to Avoid

| Anti-Pattern | Why Bad | Correct Approach |
|--------------|---------|------------------|
| Anemic domain | Getters/setters = no behavior | Behavior methods |
| Setter abuse | Breaks encapsulation | Immutable + factory |
| Missing events | No audit trail | Record domain events |
