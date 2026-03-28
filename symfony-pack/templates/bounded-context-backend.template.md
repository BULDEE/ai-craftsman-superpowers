# Agent: Backend {{CONTEXT}} Context

> Template for backend bounded context agents
> Replace {{PLACEHOLDERS}} with actual values

## Mission

{{MISSION_DESCRIPTION}}

## Context Files to Read

1. `backend/src/Domain/{{CONTEXT}}/` - Domain layer
2. `backend/src/Application/{{CONTEXT}}/` - Use cases
3. `backend/CLAUDE.md` - Architecture rules

## Domain Layer

### Aggregate Root: {{AGGREGATE_ROOT}}

```php
// backend/src/Domain/{{CONTEXT}}/Entity/{{AGGREGATE_ROOT}}.php
final class {{AGGREGATE_ROOT}}
{
    private Uuid $id;
    {{#each FIELDS}}
    private {{TYPE}} ${{NAME}};
    {{/each}}
    private DateTimeImmutable $createdAt;

    private function __construct(...) { }

    public static function create({{PARAMS}}): self { }

    {{#each BEHAVIORS}}
    public function {{NAME}}({{PARAMS}}): {{RETURN}} { }
    {{/each}}
}
```

### Entities

{{#each ENTITIES}}
#### {{NAME}}

```php
final class {{NAME}}
{
    // {{DESCRIPTION}}
}
```
{{/each}}

### Value Objects

{{#each VALUE_OBJECTS}}
- `{{NAME}}` - {{DESCRIPTION}}
{{/each}}

### Domain Services

{{#each SERVICES}}
- `{{NAME}}` - {{DESCRIPTION}}
{{/each}}

### Repositories

{{#each REPOSITORIES}}
- `{{NAME}}RepositoryInterface`
{{/each}}

### Domain Events

{{#each EVENTS}}
- `{{NAME}}Event` - {{DESCRIPTION}}
{{/each}}

## Application Layer

### Use Cases

{{#each USE_CASES}}
#### {{NAME}}

```php
final readonly class {{NAME}}Command
{
    public function __construct(
        {{#each PARAMS}}
        public {{TYPE}} ${{NAME}},
        {{/each}}
    ) { }
}

final readonly class {{NAME}}Handler
{
    public function __invoke({{NAME}}Command $command): {{RETURN}}
    {
        // {{DESCRIPTION}}
    }
}
```
{{/each}}

## Infrastructure Layer

### Files to Create

```
backend/src/Infrastructure/Persistence/{{CONTEXT}}/
{{#each REPOSITORIES}}
├── Doctrine{{NAME}}Repository.php
{{/each}}
backend/src/Infrastructure/ApiPlatform/State/
├── {{AGGREGATE_ROOT}}StateProvider.php
├── Create{{AGGREGATE_ROOT}}Processor.php
```

## API Platform 4 Integration

### State Providers (Read operations)

State Providers replace DataProviders from API Platform v2/v3. They decouple read logic from Doctrine and allow any persistence backend.

```php
<?php
declare(strict_types=1);

namespace App\Infrastructure\ApiPlatform\State;

use ApiPlatform\Metadata\CollectionOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\Pagination\Pagination;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Repository\{{AGGREGATE_ROOT}}RepositoryInterface;
use App\Domain\ValueObject\{{AGGREGATE_ROOT}}Id;

final class {{AGGREGATE_ROOT}}StateProvider implements ProviderInterface
{
    public function __construct(
        private readonly {{AGGREGATE_ROOT}}RepositoryInterface $repository,
        private readonly Pagination $pagination,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        if ($operation instanceof CollectionOperationInterface) {
            [$page, $offset, $limit] = $this->pagination->getPagination($operation, $context);

            return $this->repository->findPaginated($page, $limit);
        }

        return $this->repository->findById(
            {{AGGREGATE_ROOT}}Id::fromString($uriVariables['id'])
        );
    }
}
```

### State Processors (Write operations)

State Processors handle POST/PUT/PATCH/DELETE. Wire them to your Command Bus to keep API Platform as a thin adapter over your application layer.

```php
<?php
declare(strict_types=1);

namespace App\Infrastructure\ApiPlatform\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Application\UseCase\Create{{AGGREGATE_ROOT}}\Create{{AGGREGATE_ROOT}}Command;
use App\Shared\Application\CommandBusInterface;

final class Create{{AGGREGATE_ROOT}}Processor implements ProcessorInterface
{
    public function __construct(
        private readonly CommandBusInterface $commandBus,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        $this->commandBus->dispatch(
            Create{{AGGREGATE_ROOT}}Command::fromApiResource($data)
        );
    }
}
```

### Resource Declaration

```php
<?php
declare(strict_types=1);

namespace App\Infrastructure\ApiPlatform\Resource;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Post;
use App\Infrastructure\ApiPlatform\State\{{AGGREGATE_ROOT}}StateProvider;
use App\Infrastructure\ApiPlatform\State\Create{{AGGREGATE_ROOT}}Processor;

#[ApiResource(
    operations: [
        new GetCollection(provider: {{AGGREGATE_ROOT}}StateProvider::class),
        new Get(provider: {{AGGREGATE_ROOT}}StateProvider::class),
        new Post(processor: Create{{AGGREGATE_ROOT}}Processor::class),
    ]
)]
final class {{AGGREGATE_ROOT}}Resource
{
    public function __construct(
        public readonly string $id,
        {{#each API_FIELDS}}
        public readonly {{TYPE}} ${{NAME}},
        {{/each}}
    ) {}
}
```

## Symfony Messenger

### Async Command Handler

```php
<?php
declare(strict_types=1);

namespace App\Application\UseCase\Create{{AGGREGATE_ROOT}};

use App\Domain\Entity\{{AGGREGATE_ROOT}};
use App\Domain\Repository\{{AGGREGATE_ROOT}}RepositoryInterface;
use App\Domain\ValueObject\{{AGGREGATE_ROOT}}Id;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Messenger\MessageBusInterface;

#[AsMessageHandler]
final class Create{{AGGREGATE_ROOT}}Handler
{
    public function __construct(
        private readonly {{AGGREGATE_ROOT}}RepositoryInterface $repository,
        private readonly MessageBusInterface $eventBus,
    ) {}

    public function __invoke(Create{{AGGREGATE_ROOT}}Command $command): void
    {
        $entity = {{AGGREGATE_ROOT}}::create(
            {{AGGREGATE_ROOT}}Id::generate(),
            // map $command fields to Value Objects
        );

        $this->repository->save($entity);

        foreach ($entity->releaseEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }
}
```

### Messenger Transport Configuration

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        transports:
            async:
                dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
                retry_strategy:
                    max_retries: 3
                    delay: 1000
                    multiplier: 2

        routing:
            'App\Application\UseCase\**\*Command': async
```

### Scheduler Patterns (Symfony 7.4+)

```php
<?php
declare(strict_types=1);

namespace App\Infrastructure\Scheduler;

use Symfony\Component\Scheduler\Attribute\AsSchedule;
use Symfony\Component\Scheduler\RecurringMessage;
use Symfony\Component\Scheduler\Schedule;
use Symfony\Component\Scheduler\ScheduleProviderInterface;

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

## API Endpoints

```
{{#each ENDPOINTS}}
{{METHOD}} {{PATH}}  # {{DESCRIPTION}}
{{/each}}
```

## Validation Commands

```bash
make phpstan
make test -- --filter={{CONTEXT}}
```

## Invariants

{{#each INVARIANTS}}
- {{RULE}}
{{/each}}

## Do NOT

{{#each ANTI_PATTERNS}}
- {{RULE}}
{{/each}}
