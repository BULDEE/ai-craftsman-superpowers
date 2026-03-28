# Agent: Backend {{CONTEXT}} Context — Event-Sourced Aggregate

> Template for event-sourced aggregates with projections, snapshots, and replay
> Replace {{PLACEHOLDERS}} with actual values

## Mission

{{MISSION_DESCRIPTION}}

Implement a full event-sourced aggregate for the `{{CONTEXT}}` bounded context. The aggregate records domain events instead of mutating state directly. A projection rebuilds read models from the event stream. Snapshots cap replay cost when the event stream grows long.

## Context Files to Read

1. `backend/src/Domain/{{CONTEXT}}/` - Domain layer (aggregate, events, interfaces)
2. `backend/src/Application/{{CONTEXT}}/` - Use cases and projectors
3. `backend/src/Infrastructure/{{CONTEXT}}/` - Event store, snapshot store, read model
4. `backend/CLAUDE.md` - Architecture rules
5. `backend/config/packages/doctrine.yaml` - ORM configuration

## Domain Layer

### Aggregate Root: {{AGGREGATE_ROOT}}

The aggregate applies events to mutate its own state. It never exposes setters. All state-changing intent goes through behavioral methods that record an event, which is then applied immediately via `apply()`.

```php
<?php
// backend/src/Domain/{{CONTEXT}}/{{AGGREGATE_ROOT}}.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

use App\Domain\{{CONTEXT}}\Event\{{AGGREGATE_ROOT}}CreatedEvent;
{{#each EVENTS}}
use App\Domain\{{CONTEXT}}\Event\{{NAME}}Event;
{{/each}}
use App\Domain\Shared\AggregateRoot;
use App\Domain\Shared\DomainEventInterface;

final class {{AGGREGATE_ROOT}} extends AggregateRoot
{
    private {{AGGREGATE_ROOT}}Id $id;
    {{#each FIELDS}}
    private {{TYPE}} ${{NAME}};
    {{/each}}
    private int $version;

    private function __construct() {}

    public static function create(
        {{AGGREGATE_ROOT}}Id $id,
        {{#each CREATE_PARAMS}}
        {{TYPE}} ${{NAME}},
        {{/each}}
    ): self {
        $aggregate = new self();
        $aggregate->recordThat({{AGGREGATE_ROOT}}CreatedEvent::occur(
            $id,
            {{#each CREATE_PARAMS}}
            ${{NAME}},
            {{/each}}
        ));

        return $aggregate;
    }

    public static function reconstituteFromEvents(
        {{AGGREGATE_ROOT}}Id $id,
        DomainEventInterface ...$events,
    ): self {
        $aggregate = new self();
        $aggregate->id = $id;
        $aggregate->version = 0;

        foreach ($events as $event) {
            $aggregate->apply($event);
            ++$aggregate->version;
        }

        return $aggregate;
    }

    {{#each BEHAVIORS}}
    public function {{NAME}}({{PARAMS}}): void
    {
        $this->recordThat({{EVENT_CLASS}}::occur($this->id, {{ARGS}}));
    }

    {{/each}}
    public function id(): {{AGGREGATE_ROOT}}Id
    {
        return $this->id;
    }

    public function version(): int
    {
        return $this->version;
    }

    private function apply(DomainEventInterface $event): void
    {
        match (true) {
            $event instanceof {{AGGREGATE_ROOT}}CreatedEvent => $this->applyCreated($event),
            {{#each EVENTS}}
            $event instanceof {{NAME}}Event => $this->apply{{NAME}}($event),
            {{/each}}
            default => throw new \UnexpectedValueException(
                sprintf('Unhandled event type: %s', $event::class)
            ),
        };
    }

    private function applyCreated({{AGGREGATE_ROOT}}CreatedEvent $event): void
    {
        $this->id = $event->aggregateId();
        {{#each FIELDS}}
        $this->{{NAME}} = $event->{{NAME}}();
        {{/each}}
        $this->version = 0;
    }

    {{#each EVENTS}}
    private function apply{{NAME}}({{NAME}}Event $event): void
    {
        // Apply state change from {{NAME}}Event
    }

    {{/each}}
}
```

### Abstract AggregateRoot

```php
<?php
// backend/src/Domain/Shared/AggregateRoot.php
declare(strict_types=1);

namespace App\Domain\Shared;

abstract class AggregateRoot
{
    /** @var list<DomainEventInterface> */
    private array $recordedEvents = [];

    final protected function recordThat(DomainEventInterface $event): void
    {
        $this->recordedEvents[] = $event;
        $this->apply($event);
    }

    /** @return list<DomainEventInterface> */
    final public function recordedEvents(): array
    {
        return $this->recordedEvents;
    }

    final public function clearRecordedEvents(): void
    {
        $this->recordedEvents = [];
    }

    abstract private function apply(DomainEventInterface $event): void;
}
```

### Domain Events

Every domain event is immutable. It carries the aggregate ID, a version, and the data that caused the state transition.

```php
<?php
// backend/src/Domain/Shared/DomainEventInterface.php
declare(strict_types=1);

namespace App\Domain\Shared;

interface DomainEventInterface
{
    public function aggregateId(): AggregateIdInterface;

    public function occurredOn(): \DateTimeImmutable;

    public function version(): int;

    public function eventType(): string;
}
```

```php
<?php
// backend/src/Domain/Shared/AbstractDomainEvent.php
declare(strict_types=1);

namespace App\Domain\Shared;

abstract class AbstractDomainEvent implements DomainEventInterface
{
    private \DateTimeImmutable $occurredOn;
    private int $version;

    protected function __construct(
        private readonly AggregateIdInterface $aggregateId,
        int $version = 1,
    ) {
        $this->occurredOn = new \DateTimeImmutable();
        $this->version = $version;
    }

    final public function aggregateId(): AggregateIdInterface
    {
        return $this->aggregateId;
    }

    final public function occurredOn(): \DateTimeImmutable
    {
        return $this->occurredOn;
    }

    final public function version(): int
    {
        return $this->version;
    }

    final public function eventType(): string
    {
        return static::class;
    }
}
```

```php
<?php
// backend/src/Domain/{{CONTEXT}}/Event/{{AGGREGATE_ROOT}}CreatedEvent.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}}\Event;

use App\Domain\Shared\AbstractDomainEvent;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;

final class {{AGGREGATE_ROOT}}CreatedEvent extends AbstractDomainEvent
{
    private function __construct(
        {{AGGREGATE_ROOT}}Id $aggregateId,
        {{#each CREATE_PARAMS}}
        private readonly {{TYPE}} ${{NAME}},
        {{/each}}
    ) {
        parent::__construct($aggregateId);
    }

    public static function occur(
        {{AGGREGATE_ROOT}}Id $id,
        {{#each CREATE_PARAMS}}
        {{TYPE}} ${{NAME}},
        {{/each}}
    ): self {
        return new self($id, {{#each CREATE_PARAMS}}${{NAME}}, {{/each}});
    }

    {{#each CREATE_PARAMS}}
    public function {{NAME}}(): {{TYPE}}
    {
        return $this->{{NAME}};
    }

    {{/each}}
}
```

{{#each EVENTS}}
```php
<?php
// backend/src/Domain/{{CONTEXT}}/Event/{{NAME}}Event.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}}\Event;

use App\Domain\Shared\AbstractDomainEvent;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;

final class {{NAME}}Event extends AbstractDomainEvent
{
    private function __construct(
        {{AGGREGATE_ROOT}}Id $aggregateId,
        {{#each PARAMS}}
        private readonly {{TYPE}} ${{NAME}},
        {{/each}}
    ) {
        parent::__construct($aggregateId);
    }

    public static function occur(
        {{AGGREGATE_ROOT}}Id $id,
        {{#each PARAMS}}
        {{TYPE}} ${{NAME}},
        {{/each}}
    ): self {
        return new self($id, {{#each PARAMS}}${{NAME}}, {{/each}});
    }

    {{#each PARAMS}}
    public function {{NAME}}(): {{TYPE}}
    {
        return $this->{{NAME}};
    }

    {{/each}}
}
```
{{/each}}

### Event Store Interface

```php
<?php
// backend/src/Domain/{{CONTEXT}}/EventStoreInterface.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

use App\Domain\Shared\DomainEventInterface;

interface EventStoreInterface
{
    /** @param list<DomainEventInterface> $events */
    public function append({{AGGREGATE_ROOT}}Id $id, array $events, int $expectedVersion): void;

    /** @return list<DomainEventInterface> */
    public function load({{AGGREGATE_ROOT}}Id $id, int $fromVersion = 0): array;

    public function countEvents({{AGGREGATE_ROOT}}Id $id): int;
}
```

### Snapshot Store Interface

```php
<?php
// backend/src/Domain/{{CONTEXT}}/SnapshotStoreInterface.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

interface SnapshotStoreInterface
{
    public function save({{AGGREGATE_ROOT}}Snapshot $snapshot): void;

    public function findLatest({{AGGREGATE_ROOT}}Id $id): ?{{AGGREGATE_ROOT}}Snapshot;
}
```

```php
<?php
// backend/src/Domain/{{CONTEXT}}/{{AGGREGATE_ROOT}}Snapshot.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

final class {{AGGREGATE_ROOT}}Snapshot
{
    private function __construct(
        private readonly {{AGGREGATE_ROOT}}Id $aggregateId,
        private readonly int $version,
        private readonly array $state,
        private readonly \DateTimeImmutable $takenAt,
    ) {}

    public static function create(
        {{AGGREGATE_ROOT}}Id $aggregateId,
        int $version,
        array $state,
    ): self {
        return new self($aggregateId, $version, $state, new \DateTimeImmutable());
    }

    public function aggregateId(): {{AGGREGATE_ROOT}}Id
    {
        return $this->aggregateId;
    }

    public function version(): int
    {
        return $this->version;
    }

    public function state(): array
    {
        return $this->state;
    }

    public function takenAt(): \DateTimeImmutable
    {
        return $this->takenAt;
    }
}
```

### {{AGGREGATE_ROOT}} Repository Interface

```php
<?php
// backend/src/Domain/{{CONTEXT}}/{{AGGREGATE_ROOT}}RepositoryInterface.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

interface {{AGGREGATE_ROOT}}RepositoryInterface
{
    public function save({{AGGREGATE_ROOT}} $aggregate): void;

    public function load({{AGGREGATE_ROOT}}Id $id): {{AGGREGATE_ROOT}};
}
```

### Value Objects

```php
<?php
// backend/src/Domain/{{CONTEXT}}/{{AGGREGATE_ROOT}}Id.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

use App\Domain\Shared\AggregateIdInterface;
use Symfony\Component\Uid\Uuid;

final class {{AGGREGATE_ROOT}}Id implements AggregateIdInterface
{
    private function __construct(private readonly string $value) {}

    public static function generate(): self
    {
        return new self(Uuid::v7()->toRfc4122());
    }

    public static function fromString(string $value): self
    {
        if (!Uuid::isValid($value)) {
            throw new \InvalidArgumentException(
                sprintf('Invalid {{AGGREGATE_ROOT}}Id: %s', $value)
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

{{#each VALUE_OBJECTS}}
```php
<?php
// backend/src/Domain/{{CONTEXT}}/{{NAME}}.php
declare(strict_types=1);

namespace App\Domain\{{CONTEXT}};

final class {{NAME}}
{
    private function __construct(private readonly {{INNER_TYPE}} $value) {}

    public static function fromString(string $value): self
    {
        // {{VALIDATION}}
        return new self($value);
    }

    public function value(): {{INNER_TYPE}}
    {
        return $this->value;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }
}
```
{{/each}}

## Application Layer

### {{AGGREGATE_ROOT}} Repository (Event-Sourced)

The repository reconstructs the aggregate from events or from a snapshot + trailing events. It also triggers a snapshot when the event count exceeds `{{SNAPSHOT_THRESHOLD}}`.

```php
<?php
// backend/src/Application/{{CONTEXT}}/{{AGGREGATE_ROOT}}Repository.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}};

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}};
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}NotFoundException;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}RepositoryInterface;
use App\Domain\{{CONTEXT}}\EventStoreInterface;
use App\Domain\{{CONTEXT}}\SnapshotStoreInterface;

final class {{AGGREGATE_ROOT}}Repository implements {{AGGREGATE_ROOT}}RepositoryInterface
{
    private const SNAPSHOT_THRESHOLD = {{SNAPSHOT_THRESHOLD}};

    public function __construct(
        private readonly EventStoreInterface $eventStore,
        private readonly SnapshotStoreInterface $snapshotStore,
        private readonly {{AGGREGATE_ROOT}}ProjectorInterface $projector,
    ) {}

    public function save({{AGGREGATE_ROOT}} $aggregate): void
    {
        $events = $aggregate->recordedEvents();

        if ($events === []) {
            return;
        }

        $this->eventStore->append(
            $aggregate->id(),
            $events,
            $aggregate->version() - count($events),
        );

        foreach ($events as $event) {
            $this->projector->project($event);
        }

        $aggregate->clearRecordedEvents();

        $totalEvents = $this->eventStore->countEvents($aggregate->id());

        if ($totalEvents > 0 && $totalEvents % self::SNAPSHOT_THRESHOLD === 0) {
            $this->snapshotStore->save($aggregate->toSnapshot());
        }
    }

    public function load({{AGGREGATE_ROOT}}Id $id): {{AGGREGATE_ROOT}}
    {
        $snapshot = $this->snapshotStore->findLatest($id);
        $fromVersion = $snapshot?->version() ?? 0;
        $events = $this->eventStore->load($id, $fromVersion);

        if ($snapshot === null && $events === []) {
            throw {{AGGREGATE_ROOT}}NotFoundException::withId($id);
        }

        if ($snapshot !== null) {
            return {{AGGREGATE_ROOT}}::reconstituteFromSnapshot($snapshot, ...$events);
        }

        return {{AGGREGATE_ROOT}}::reconstituteFromEvents($id, ...$events);
    }
}
```

### Use Cases

{{#each USE_CASES}}
```php
<?php
// backend/src/Application/{{CONTEXT}}/UseCase/{{NAME}}/{{NAME}}Command.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}}\UseCase\{{NAME}};

final readonly class {{NAME}}Command
{
    public function __construct(
        {{#each PARAMS}}
        public readonly {{TYPE}} ${{NAME}},
        {{/each}}
    ) {}
}
```

```php
<?php
// backend/src/Application/{{CONTEXT}}/UseCase/{{NAME}}/{{NAME}}Handler.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}}\UseCase\{{NAME}};

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}RepositoryInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final class {{NAME}}Handler
{
    public function __construct(
        private readonly {{AGGREGATE_ROOT}}RepositoryInterface $repository,
    ) {}

    public function __invoke({{NAME}}Command $command): void
    {
        // {{DESCRIPTION}}
    }
}
```
{{/each}}

### Projector Interface

```php
<?php
// backend/src/Application/{{CONTEXT}}/{{AGGREGATE_ROOT}}ProjectorInterface.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}};

use App\Domain\Shared\DomainEventInterface;

interface {{AGGREGATE_ROOT}}ProjectorInterface
{
    public function project(DomainEventInterface $event): void;
}
```

### Sync Projector Implementation

The projector builds and maintains the read model. It handles each event type via a private `when*()` method.

```php
<?php
// backend/src/Application/{{CONTEXT}}/{{AGGREGATE_ROOT}}SyncProjector.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}};

use App\Domain\{{CONTEXT}}\Event\{{AGGREGATE_ROOT}}CreatedEvent;
{{#each EVENTS}}
use App\Domain\{{CONTEXT}}\Event\{{NAME}}Event;
{{/each}}
use App\Domain\Shared\DomainEventInterface;
use App\Infrastructure\{{CONTEXT}}\ReadModel\{{AGGREGATE_ROOT}}ReadModelRepositoryInterface;

final class {{AGGREGATE_ROOT}}SyncProjector implements {{AGGREGATE_ROOT}}ProjectorInterface
{
    public function __construct(
        private readonly {{AGGREGATE_ROOT}}ReadModelRepositoryInterface $readModelRepository,
    ) {}

    public function project(DomainEventInterface $event): void
    {
        match (true) {
            $event instanceof {{AGGREGATE_ROOT}}CreatedEvent => $this->when{{AGGREGATE_ROOT}}Created($event),
            {{#each EVENTS}}
            $event instanceof {{NAME}}Event => $this->when{{NAME}}($event),
            {{/each}}
            default => null,
        };
    }

    private function when{{AGGREGATE_ROOT}}Created({{AGGREGATE_ROOT}}CreatedEvent $event): void
    {
        $readModel = {{AGGREGATE_ROOT}}ReadModel::create(
            $event->aggregateId()->toString(),
            {{#each CREATE_PARAMS}}
            $event->{{NAME}}(),
            {{/each}}
            $event->occurredOn(),
        );

        $this->readModelRepository->save($readModel);
    }

    {{#each EVENTS}}
    private function when{{NAME}}({{NAME}}Event $event): void
    {
        $readModel = $this->readModelRepository->getById(
            $event->aggregateId()->toString()
        );

        // Update read model fields from {{NAME}}Event
        $readModel->apply{{NAME}}($event);

        $this->readModelRepository->save($readModel);
    }

    {{/each}}
}
```

### Read Model

```php
<?php
// backend/src/Application/{{CONTEXT}}/ReadModel/{{AGGREGATE_ROOT}}ReadModel.php
declare(strict_types=1);

namespace App\Application\{{CONTEXT}}\ReadModel;

final class {{AGGREGATE_ROOT}}ReadModel
{
    private function __construct(
        private string $id,
        {{#each READ_MODEL_FIELDS}}
        private {{TYPE}} ${{NAME}},
        {{/each}}
        private \DateTimeImmutable $createdAt,
        private \DateTimeImmutable $updatedAt,
    ) {}

    public static function create(
        string $id,
        {{#each READ_MODEL_FIELDS}}
        {{TYPE}} ${{NAME}},
        {{/each}}
        \DateTimeImmutable $createdAt,
    ): self {
        return new self(
            $id,
            {{#each READ_MODEL_FIELDS}}
            ${{NAME}},
            {{/each}}
            $createdAt,
            $createdAt,
        );
    }

    public function id(): string
    {
        return $this->id;
    }

    {{#each READ_MODEL_FIELDS}}
    public function {{NAME}}(): {{TYPE}}
    {
        return $this->{{NAME}};
    }

    {{/each}}
    public function createdAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function updatedAt(): \DateTimeImmutable
    {
        return $this->updatedAt;
    }

    {{#each EVENTS}}
    public function apply{{NAME}}(/* {{NAME}}Event */ $event): void
    {
        // Update denormalized fields from event
        $this->updatedAt = $event->occurredOn();
    }

    {{/each}}
}
```

## Infrastructure Layer

### File Structure

```
backend/src/Infrastructure/{{CONTEXT}}/
├── EventStore/
│   └── DoctrineEventStore.php
├── SnapshotStore/
│   └── DoctrineSnapshotStore.php
├── ReadModel/
│   ├── {{AGGREGATE_ROOT}}ReadModelRepositoryInterface.php
│   └── Doctrine{{AGGREGATE_ROOT}}ReadModelRepository.php
└── Console/
    └── Replay{{AGGREGATE_ROOT}}EventsCommand.php
```

### Doctrine Event Store

```php
<?php
// backend/src/Infrastructure/{{CONTEXT}}/EventStore/DoctrineEventStore.php
declare(strict_types=1);

namespace App\Infrastructure\{{CONTEXT}}\EventStore;

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\EventStoreInterface;
use App\Domain\Shared\DomainEventInterface;
use Doctrine\DBAL\Connection;

final class DoctrineEventStore implements EventStoreInterface
{
    public function __construct(private readonly Connection $connection) {}

    public function append({{AGGREGATE_ROOT}}Id $id, array $events, int $expectedVersion): void
    {
        $this->connection->transactional(function () use ($id, $events, $expectedVersion): void {
            $currentVersion = $this->currentVersion($id);

            if ($currentVersion !== $expectedVersion) {
                throw new OptimisticConcurrencyException(
                    sprintf(
                        'Concurrency conflict on aggregate %s: expected version %d but got %d',
                        $id->toString(),
                        $expectedVersion,
                        $currentVersion,
                    )
                );
            }

            foreach ($events as $position => $event) {
                $this->connection->insert('{{CONTEXT_SNAKE}}_events', [
                    'aggregate_id' => $id->toString(),
                    'type'         => $event->eventType(),
                    'payload'      => json_encode($this->serialize($event), JSON_THROW_ON_ERROR),
                    'version'      => $event->version(),
                    'position'     => $expectedVersion + $position + 1,
                    'occurred_on'  => $event->occurredOn()->format('Y-m-d H:i:s.u'),
                ]);
            }
        });
    }

    public function load({{AGGREGATE_ROOT}}Id $id, int $fromVersion = 0): array
    {
        $rows = $this->connection->fetchAllAssociative(
            'SELECT type, payload, version, occurred_on
             FROM {{CONTEXT_SNAKE}}_events
             WHERE aggregate_id = :aggregateId AND position > :fromVersion
             ORDER BY position ASC',
            ['aggregateId' => $id->toString(), 'fromVersion' => $fromVersion],
        );

        return array_map(fn (array $row): DomainEventInterface => $this->deserialize($row), $rows);
    }

    public function countEvents({{AGGREGATE_ROOT}}Id $id): int
    {
        return (int) $this->connection->fetchOne(
            'SELECT COUNT(*) FROM {{CONTEXT_SNAKE}}_events WHERE aggregate_id = :aggregateId',
            ['aggregateId' => $id->toString()],
        );
    }

    private function currentVersion({{AGGREGATE_ROOT}}Id $id): int
    {
        return (int) $this->connection->fetchOne(
            'SELECT COALESCE(MAX(position), 0) FROM {{CONTEXT_SNAKE}}_events WHERE aggregate_id = :aggregateId',
            ['aggregateId' => $id->toString()],
        );
    }

    private function serialize(DomainEventInterface $event): array
    {
        // Map event class to serializable array — implement per event type
        return [];
    }

    private function deserialize(array $row): DomainEventInterface
    {
        $payload = json_decode($row['payload'], true, 512, JSON_THROW_ON_ERROR);

        // Map type string back to domain event class — implement per event type
        return match ($row['type']) {
            default => throw new \UnexpectedValueException(
                sprintf('Unknown event type: %s', $row['type'])
            ),
        };
    }
}
```

### Database Migration

```php
<?php
// backend/migrations/Version{{MIGRATION_TIMESTAMP}}.php
declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version{{MIGRATION_TIMESTAMP}} extends AbstractMigration
{
    public function up(Schema $schema): void
    {
        $this->addSql(<<<'SQL'
            CREATE TABLE {{CONTEXT_SNAKE}}_events (
                id          BIGSERIAL PRIMARY KEY,
                aggregate_id UUID          NOT NULL,
                type        VARCHAR(255)  NOT NULL,
                payload     JSONB         NOT NULL,
                version     SMALLINT      NOT NULL,
                position    INT           NOT NULL,
                occurred_on TIMESTAMP(6)  NOT NULL,
                UNIQUE (aggregate_id, position)
            )
        SQL);

        $this->addSql('CREATE INDEX idx_{{CONTEXT_SNAKE}}_events_aggregate_id ON {{CONTEXT_SNAKE}}_events (aggregate_id)');

        $this->addSql(<<<'SQL'
            CREATE TABLE {{CONTEXT_SNAKE}}_snapshots (
                id           BIGSERIAL PRIMARY KEY,
                aggregate_id UUID         NOT NULL,
                version      INT          NOT NULL,
                state        JSONB        NOT NULL,
                taken_at     TIMESTAMP(6) NOT NULL,
                UNIQUE (aggregate_id, version)
            )
        SQL);

        $this->addSql('CREATE INDEX idx_{{CONTEXT_SNAKE}}_snapshots_aggregate_id ON {{CONTEXT_SNAKE}}_snapshots (aggregate_id)');

        $this->addSql(<<<'SQL'
            CREATE TABLE {{CONTEXT_SNAKE}}_read_model (
                id         UUID         PRIMARY KEY,
                {{#each READ_MODEL_COLUMNS}}
                {{NAME}}   {{SQL_TYPE}} NOT NULL,
                {{/each}}
                created_at TIMESTAMP(6) NOT NULL,
                updated_at TIMESTAMP(6) NOT NULL
            )
        SQL);
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE {{CONTEXT_SNAKE}}_read_model');
        $this->addSql('DROP TABLE {{CONTEXT_SNAKE}}_snapshots');
        $this->addSql('DROP TABLE {{CONTEXT_SNAKE}}_events');
    }
}
```

### Doctrine Snapshot Store

```php
<?php
// backend/src/Infrastructure/{{CONTEXT}}/SnapshotStore/DoctrineSnapshotStore.php
declare(strict_types=1);

namespace App\Infrastructure\{{CONTEXT}}\SnapshotStore;

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Snapshot;
use App\Domain\{{CONTEXT}}\SnapshotStoreInterface;
use Doctrine\DBAL\Connection;

final class DoctrineSnapshotStore implements SnapshotStoreInterface
{
    public function __construct(private readonly Connection $connection) {}

    public function save({{AGGREGATE_ROOT}}Snapshot $snapshot): void
    {
        $this->connection->insert('{{CONTEXT_SNAKE}}_snapshots', [
            'aggregate_id' => $snapshot->aggregateId()->toString(),
            'version'      => $snapshot->version(),
            'state'        => json_encode($snapshot->state(), JSON_THROW_ON_ERROR),
            'taken_at'     => $snapshot->takenAt()->format('Y-m-d H:i:s.u'),
        ]);
    }

    public function findLatest({{AGGREGATE_ROOT}}Id $id): ?{{AGGREGATE_ROOT}}Snapshot
    {
        $row = $this->connection->fetchAssociative(
            'SELECT aggregate_id, version, state, taken_at
             FROM {{CONTEXT_SNAKE}}_snapshots
             WHERE aggregate_id = :aggregateId
             ORDER BY version DESC
             LIMIT 1',
            ['aggregateId' => $id->toString()],
        );

        if ($row === false) {
            return null;
        }

        return {{AGGREGATE_ROOT}}Snapshot::create(
            {{AGGREGATE_ROOT}}Id::fromString($row['aggregate_id']),
            (int) $row['version'],
            json_decode($row['state'], true, 512, JSON_THROW_ON_ERROR),
        );
    }
}
```

### Read Model Repository

```php
<?php
// backend/src/Infrastructure/{{CONTEXT}}/ReadModel/{{AGGREGATE_ROOT}}ReadModelRepositoryInterface.php
declare(strict_types=1);

namespace App\Infrastructure\{{CONTEXT}}\ReadModel;

use App\Application\{{CONTEXT}}\ReadModel\{{AGGREGATE_ROOT}}ReadModel;

interface {{AGGREGATE_ROOT}}ReadModelRepositoryInterface
{
    public function save({{AGGREGATE_ROOT}}ReadModel $readModel): void;

    public function getById(string $id): {{AGGREGATE_ROOT}}ReadModel;

    /** @return list<{{AGGREGATE_ROOT}}ReadModel> */
    public function findAll(int $page, int $limit): array;
}
```

```php
<?php
// backend/src/Infrastructure/{{CONTEXT}}/ReadModel/Doctrine{{AGGREGATE_ROOT}}ReadModelRepository.php
declare(strict_types=1);

namespace App\Infrastructure\{{CONTEXT}}\ReadModel;

use App\Application\{{CONTEXT}}\ReadModel\{{AGGREGATE_ROOT}}ReadModel;
use Doctrine\DBAL\Connection;

final class Doctrine{{AGGREGATE_ROOT}}ReadModelRepository implements {{AGGREGATE_ROOT}}ReadModelRepositoryInterface
{
    public function __construct(private readonly Connection $connection) {}

    public function save({{AGGREGATE_ROOT}}ReadModel $readModel): void
    {
        $this->connection->executeStatement(<<<'SQL'
            INSERT INTO {{CONTEXT_SNAKE}}_read_model (id, {{#each READ_MODEL_COLUMNS}}{{NAME}}, {{/each}}created_at, updated_at)
            VALUES (:id, {{#each READ_MODEL_COLUMNS}}:{{NAME}}, {{/each}}:created_at, :updated_at)
            ON CONFLICT (id) DO UPDATE SET
                {{#each READ_MODEL_COLUMNS}}
                {{NAME}} = EXCLUDED.{{NAME}},
                {{/each}}
                updated_at = EXCLUDED.updated_at
        SQL, [
            'id' => $readModel->id(),
            {{#each READ_MODEL_COLUMNS}}
            '{{NAME}}' => $readModel->{{NAME}}(),
            {{/each}}
            'created_at' => $readModel->createdAt()->format('Y-m-d H:i:s.u'),
            'updated_at' => $readModel->updatedAt()->format('Y-m-d H:i:s.u'),
        ]);
    }

    public function getById(string $id): {{AGGREGATE_ROOT}}ReadModel
    {
        $row = $this->connection->fetchAssociative(
            'SELECT * FROM {{CONTEXT_SNAKE}}_read_model WHERE id = :id',
            ['id' => $id],
        );

        if ($row === false) {
            throw new \RuntimeException(sprintf('{{AGGREGATE_ROOT}} read model not found: %s', $id));
        }

        return $this->hydrate($row);
    }

    public function findAll(int $page, int $limit): array
    {
        $rows = $this->connection->fetchAllAssociative(
            'SELECT * FROM {{CONTEXT_SNAKE}}_read_model ORDER BY created_at DESC LIMIT :limit OFFSET :offset',
            ['limit' => $limit, 'offset' => ($page - 1) * $limit],
        );

        return array_map($this->hydrate(...), $rows);
    }

    private function hydrate(array $row): {{AGGREGATE_ROOT}}ReadModel
    {
        return {{AGGREGATE_ROOT}}ReadModel::create(
            $row['id'],
            {{#each READ_MODEL_COLUMNS}}
            $row['{{NAME}}'],
            {{/each}}
            new \DateTimeImmutable($row['created_at']),
        );
    }
}
```

### Replay Console Command

```php
<?php
// backend/src/Infrastructure/{{CONTEXT}}/Console/Replay{{AGGREGATE_ROOT}}EventsCommand.php
declare(strict_types=1);

namespace App\Infrastructure\{{CONTEXT}}\Console;

use App\Application\{{CONTEXT}}\{{AGGREGATE_ROOT}}ProjectorInterface;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\EventStoreInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

#[AsCommand(
    name: 'app:events:replay',
    description: 'Replay events to rebuild the {{AGGREGATE_ROOT}} read model',
)]
final class Replay{{AGGREGATE_ROOT}}EventsCommand extends Command
{
    public function __construct(
        private readonly EventStoreInterface $eventStore,
        private readonly {{AGGREGATE_ROOT}}ProjectorInterface $projector,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption(
            'aggregate',
            'a',
            InputOption::VALUE_OPTIONAL,
            'Replay a single aggregate by ID',
        );
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $aggregateOption = $input->getOption('aggregate');

        if ($aggregateOption !== null) {
            $this->replaySingle({{AGGREGATE_ROOT}}Id::fromString($aggregateOption), $io);
            return Command::SUCCESS;
        }

        $this->replayAll($io);
        return Command::SUCCESS;
    }

    private function replaySingle({{AGGREGATE_ROOT}}Id $id, SymfonyStyle $io): void
    {
        $io->section(sprintf('Replaying aggregate %s', $id->toString()));
        $events = $this->eventStore->load($id);
        $count = 0;

        foreach ($events as $event) {
            $this->projector->project($event);
            ++$count;
        }

        $io->success(sprintf('Replayed %d events for aggregate %s', $count, $id->toString()));
    }

    private function replayAll(SymfonyStyle $io): void
    {
        $io->section('Replaying all {{AGGREGATE_ROOT}} events');
        $io->warning('This will truncate the read model table before replaying.');

        if (!$io->confirm('Proceed?', false)) {
            $io->comment('Aborted.');
            return;
        }

        // Truncate + replay — implement full-scan in event store or use a dedicated method
        $io->success('Replay complete.');
    }
}
```

## Tests

### Aggregate Behavior Test

```php
<?php
// backend/tests/Unit/Domain/{{CONTEXT}}/{{AGGREGATE_ROOT}}Test.php
declare(strict_types=1);

namespace Tests\Unit\Domain\{{CONTEXT}};

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}};
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\Event\{{AGGREGATE_ROOT}}CreatedEvent;
{{#each EVENTS}}
use App\Domain\{{CONTEXT}}\Event\{{NAME}}Event;
{{/each}}
use PHPUnit\Framework\TestCase;

final class {{AGGREGATE_ROOT}}Test extends TestCase
{
    public function testCreateRecordsCreatedEvent(): void
    {
        $id = {{AGGREGATE_ROOT}}Id::generate();

        $aggregate = {{AGGREGATE_ROOT}}::create(
            $id,
            // constructor args
        );

        $events = $aggregate->recordedEvents();

        self::assertCount(1, $events);
        self::assertInstanceOf({{AGGREGATE_ROOT}}CreatedEvent::class, $events[0]);
        self::assertTrue($id->equals($events[0]->aggregateId()));
    }

    public function testReconstitutionFromEventsRestoresState(): void
    {
        $id = {{AGGREGATE_ROOT}}Id::generate();

        $original = {{AGGREGATE_ROOT}}::create($id, /* args */);
        $events = $original->recordedEvents();

        $restored = {{AGGREGATE_ROOT}}::reconstituteFromEvents($id, ...$events);

        self::assertEquals($original->id()->toString(), $restored->id()->toString());
    }

    {{#each BEHAVIORS}}
    public function test{{NAME}}Records{{EVENT_CLASS}}(): void
    {
        $aggregate = {{AGGREGATE_ROOT}}::create({{AGGREGATE_ROOT}}Id::generate(), /* args */);
        $aggregate->clearRecordedEvents();

        $aggregate->{{NAME}}(/* args */);

        $events = $aggregate->recordedEvents();
        self::assertCount(1, $events);
        self::assertInstanceOf({{EVENT_CLASS}}::class, $events[0]);
    }

    {{/each}}
}
```

### Event Store Integration Test

```php
<?php
// backend/tests/Integration/Infrastructure/{{CONTEXT}}/DoctrineEventStoreTest.php
declare(strict_types=1);

namespace Tests\Integration\Infrastructure\{{CONTEXT}};

use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}};
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Infrastructure\{{CONTEXT}}\EventStore\DoctrineEventStore;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;

final class DoctrineEventStoreTest extends KernelTestCase
{
    private DoctrineEventStore $eventStore;

    protected function setUp(): void
    {
        self::bootKernel();
        $this->eventStore = self::getContainer()->get(DoctrineEventStore::class);
    }

    public function testAppendAndLoadRoundTrip(): void
    {
        $id = {{AGGREGATE_ROOT}}Id::generate();

        $aggregate = {{AGGREGATE_ROOT}}::create($id, /* args */);
        $events = $aggregate->recordedEvents();

        $this->eventStore->append($id, $events, 0);

        $loaded = $this->eventStore->load($id);

        self::assertCount(count($events), $loaded);
        self::assertEquals($events[0]->aggregateId()->toString(), $loaded[0]->aggregateId()->toString());
    }

    public function testConcurrencyConflictThrows(): void
    {
        $id = {{AGGREGATE_ROOT}}Id::generate();
        $aggregate = {{AGGREGATE_ROOT}}::create($id, /* args */);
        $events = $aggregate->recordedEvents();

        $this->eventStore->append($id, $events, 0);

        $this->expectException(\App\Infrastructure\{{CONTEXT}}\EventStore\OptimisticConcurrencyException::class);

        $this->eventStore->append($id, $events, 0);
    }
}
```

### Projector Test

```php
<?php
// backend/tests/Unit/Application/{{CONTEXT}}/{{AGGREGATE_ROOT}}SyncProjectorTest.php
declare(strict_types=1);

namespace Tests\Unit\Application\{{CONTEXT}};

use App\Application\{{CONTEXT}}\{{AGGREGATE_ROOT}}SyncProjector;
use App\Domain\{{CONTEXT}}\{{AGGREGATE_ROOT}}Id;
use App\Domain\{{CONTEXT}}\Event\{{AGGREGATE_ROOT}}CreatedEvent;
use App\Infrastructure\{{CONTEXT}}\ReadModel\{{AGGREGATE_ROOT}}ReadModelRepositoryInterface;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

final class {{AGGREGATE_ROOT}}SyncProjectorTest extends TestCase
{
    private {{AGGREGATE_ROOT}}ReadModelRepositoryInterface&MockObject $readModelRepository;
    private {{AGGREGATE_ROOT}}SyncProjector $projector;

    protected function setUp(): void
    {
        $this->readModelRepository = $this->createMock({{AGGREGATE_ROOT}}ReadModelRepositoryInterface::class);
        $this->projector = new {{AGGREGATE_ROOT}}SyncProjector($this->readModelRepository);
    }

    public function testProjectCreatedEventSavesReadModel(): void
    {
        $event = {{AGGREGATE_ROOT}}CreatedEvent::occur(
            {{AGGREGATE_ROOT}}Id::generate(),
            // args
        );

        $this->readModelRepository->expects(self::once())->method('save');

        $this->projector->project($event);
    }

    public function testProjectUnknownEventDoesNothing(): void
    {
        $this->readModelRepository->expects(self::never())->method('save');

        // create an unrelated event stub
        $event = $this->createMock(\App\Domain\Shared\DomainEventInterface::class);

        $this->projector->project($event);
    }
}
```

## Validation Commands

```bash
make phpstan
make test -- --filter={{CONTEXT}}
bin/console app:events:replay --aggregate={{SAMPLE_UUID}}
bin/console doctrine:migrations:status
```

## Invariants

{{#each INVARIANTS}}
- {{RULE}}
{{/each}}

## Do NOT

- Expose setters on the aggregate — all mutation goes through behavioral methods that record events
- Modify `recordedEvents()` output after `clearRecordedEvents()` has been called
- Load the aggregate from the read model — always reconstitute from the event store
- Dispatch domain events directly from a handler — the repository's `save()` drives the projector
- Skip the optimistic concurrency check in `DoctrineEventStore::append()`
- Snapshot more often than `{{SNAPSHOT_THRESHOLD}}` events — snapshots are not free
- Delete events from `{{CONTEXT_SNAKE}}_events` — the table is append-only by design

{{#each ANTI_PATTERNS}}
- {{RULE}}
{{/each}}
