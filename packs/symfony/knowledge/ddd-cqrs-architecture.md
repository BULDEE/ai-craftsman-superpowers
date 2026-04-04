# DDD + CQRS Architecture with Symfony & API Platform

Real-world patterns extracted from production Symfony + API Platform + DDD projects.

## Layer Architecture

```
src/
├── Domain/              # IMPORTS NOTHING — Pure business logic
│   ├── Entity/          # Aggregates and entities (Doctrine-mapped)
│   ├── ValueObject/     # Immutable, self-validating types
│   ├── Repository/      # Interfaces only (contracts)
│   ├── Event/           # Domain events (immutable facts)
│   ├── Enum/            # Domain enumerations
│   ├── Service/         # Domain services (cross-aggregate logic)
│   ├── Exception/       # Domain-specific exceptions
│   ├── ReadModel/       # Read-optimized projections
│   ├── Constants/       # Domain constants
│   └── DTO/             # Domain transfer objects
│
├── Application/         # Imports Domain only
│   ├── UseCase/         # Business logic orchestration (1 class = 1 use case)
│   ├── DTO/             # Application-level DTOs (input/output)
│   ├── Command/         # CQRS commands (Messenger messages)
│   ├── CommandHandler/  # Messenger command handlers
│   ├── Service/         # Application services
│   └── Port/            # Output interfaces (adapters pattern)
│
├── Infrastructure/      # Imports Domain, Application
│   ├── Persistence/     # Doctrine repository implementations
│   ├── Doctrine/        # Custom types, filters
│   ├── External/        # Third-party API connectors
│   ├── Security/        # Voters, encryption
│   ├── Cache/           # Cache strategies
│   └── Messenger/       # Transport config, middleware
│
└── Presentation/        # Imports Domain, Application
    ├── State/           # API Platform state providers/processors
    ├── Api/             # REST controllers
    └── Console/         # CLI commands
```

### Critical Rule

**Domain imports NOTHING.** Validate with:
```bash
grep -r 'Infrastructure\|Presentation' src/Domain/ && echo 'VIOLATION' || echo 'OK'
```

## Bounded Contexts (Optional)

For large domains, organize by bounded context under Domain:

```
Domain/
├── Calendar/
│   ├── Entity/
│   ├── ValueObject/
│   ├── Repository/
│   ├── Enum/
│   └── Event/
├── Prospect/
│   ├── Entity/
│   ├── ValueObject/
│   └── Repository/
└── SharedKernel/
    └── ValueObject/   # Email, Money — shared across contexts
```

## Value Objects

Self-validating, immutable, with `readonly` and private constructor:

```php
<?php

declare(strict_types=1);

namespace App\Domain\ValueObject;

final readonly class Email implements \Stringable
{
    private string $value;

    private function __construct(string $value)
    {
        $normalized = strtolower(trim($value));
        if (!filter_var($normalized, \FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::invalidFormat($value);
        }
        $this->value = $normalized;
    }

    public static function fromString(string $value): self
    {
        return new self($value);
    }

    public function value(): string
    {
        return $this->value;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
```

### Money (cents-based arithmetic):

```php
final readonly class Money implements \Stringable
{
    private function __construct(
        public int $amount,     // Always in cents
        public string $currency = 'EUR',
    ) {}

    public static function create(int $amount, string $currency = 'EUR'): self
    {
        return new self($amount, $currency);
    }

    public static function fromFloat(float $amount, string $currency = 'EUR'): self
    {
        return new self((int) round($amount * 100), $currency);
    }

    public function add(self $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->amount + $other->amount, $this->currency);
    }
}
```

## Repository Pattern

Domain declares interface, Infrastructure implements:

```php
// Domain/Repository/LeadRepositoryInterface.php
interface LeadRepositoryInterface
{
    public function save(Lead $lead): void;
    public function find(Uuid $id): ?Lead;
    public function findByTenant(Tenant $tenant): array;
    public function remove(Lead $lead): void;
}

// Infrastructure/Persistence/Doctrine/LeadRepository.php
final class LeadRepository extends ServiceEntityRepository implements LeadRepositoryInterface
{
    public function save(Lead $lead): void
    {
        $this->getEntityManager()->persist($lead);
        $this->getEntityManager()->flush();
    }
}
```

## Domain Events

Immutable facts about what happened:

```php
final readonly class LeadCreatedEvent implements DomainEventInterface
{
    public function __construct(
        private string $leadId,
        private string $tenantId,
        private \DateTimeImmutable $occurredAt,
    ) {}

    public function aggregateId(): string { return $this->leadId; }
    public function eventName(): string { return 'lead.created'; }

    public function toArray(): array
    {
        return [
            'leadId' => $this->leadId,
            'tenantId' => $this->tenantId,
            'occurredAt' => $this->occurredAt->format(\DateTimeInterface::ATOM),
        ];
    }
}
```

## UseCase Pattern

One class, one responsibility, `final readonly`:

```php
final readonly class CreateDataSourceUseCase
{
    public function __construct(
        private DataSourceRepositoryInterface $repository,
        private ClockInterface $clock,
    ) {}

    public function execute(User $user, CreateDataSourceDTO $dto): DataSource
    {
        $this->validateRequiredFields($dto);

        $dataSource = DataSource::create(
            $user->getTenant(),
            $user,
            $dto->type,
            $dto->name,
            $this->clock->now(),
        );

        $this->repository->save($dataSource);

        return $dataSource;
    }
}
```

### Key rules:
- **Never inject `DateTime`** — use `ClockInterface`
- **DTO as input** — not raw arrays or request objects
- **Repository interface** — not Doctrine EntityManager directly
- **Entity factory** — `Entity::create()`, never `new Entity()`

## API Platform Integration

### State Processor (write operations):

```php
final readonly class LeadProcessor implements ProcessorInterface
{
    public function __construct(
        private UnitOfWorkInterface $unitOfWork,
        private Security $security,
        private CreateLeadUseCase $createUseCase,
        private ValidatorInterface $validator,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): Lead
    {
        if ($operation instanceof Post) {
            return $this->handlePost($context);
        }

        if ($operation instanceof Patch) {
            $this->handlePatch($data, $context);
        }

        $this->unitOfWork->flush();
        return $data;
    }
}
```

### State Provider (read operations):

```php
final readonly class CampaignCollectionProvider implements ProviderInterface
{
    public function __construct(
        private CampaignRepositoryInterface $repository,
        private Security $security,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): array
    {
        $user = $this->security->getUser();
        return $this->repository->findByTenant($user->getTenant());
    }
}
```

## Entity Patterns

Entities use behavioral methods, not setters:

```php
// GOOD: Behavioral method with business meaning
$lead->transitionTo(LeadStatus::Qualified, $clock->now());
$lead->scheduleNurturing($dueDate, $clock->now());
$lead->assignAdSource($adSource, $clock->now());

// BAD: Anemic setters
$lead->setStatus('qualified');
$lead->setNurturingDate($date);
```

### Entity exceptions:
- **No `final`** on Doctrine entities (proxies require inheritance)
- `#[ApiResource]` on Domain entities is a pragmatic choice when Symfony is the only framework

## CQRS with Messenger

```php
// Command (write intention)
final readonly class SyncDataSourceCommand
{
    public function __construct(
        public string $dataSourceId,
        public string $tenantId,
    ) {}
}

// Handler (in Application layer)
#[AsMessageHandler]
final readonly class SyncDataSourceHandler
{
    public function __construct(
        private DataSourceRepositoryInterface $repository,
        private SyncService $syncService,
    ) {}

    public function __invoke(SyncDataSourceCommand $command): void
    {
        $dataSource = $this->repository->find(Uuid::fromString($command->dataSourceId));
        $this->syncService->sync($dataSource);
    }
}
```

## Multi-Tenancy

Every business entity carries a `TenantId`:

```php
$entity = Entity::create(
    tenantId: $user->getTenant()->getId(),
    // ...
);
```

Voters enforce tenant isolation at security level.

## Anti-Patterns

| Anti-Pattern | Correct Pattern |
|-------------|-----------------|
| Domain imports Infrastructure | Domain imports NOTHING |
| `new DateTime()` | `ClockInterface::now()` |
| `new Entity(...)` | `Entity::create(...)` |
| `$entity->setStatus()` | `$entity->transitionTo()` |
| Logic in Controller | Logic in UseCase |
| `string $email` parameter | `Email` Value Object |
| EntityManager in UseCase | Repository Interface |
| Raw array as DTO | Typed DTO class |
| `final` on Doctrine entities | Only `final` on VOs, Events, UseCases |
| Inline ACL checks | Symfony Voters |
