---
name: DDD Symfony Implementation
description: Symfony/Doctrine/API Platform/Messenger specifics for implementing the language-agnostic DDD tactical patterns
type: methodology
---

# DDD Implementation in Symfony

The framework-agnostic tactical patterns live in the core knowledge (`knowledge/ddd/ddd-domain-design.md` and `knowledge/ddd/ddd-cqrs-architecture.md`). This file covers the **Symfony-specific** mechanics: how those patterns map onto Doctrine, API Platform, and Messenger.

## Doctrine and Entities

Doctrine proxies require inheritance, so the usual "all classes are `final`" rule has one carve-out:

- **Do not** mark Doctrine-mapped entities `final` (proxies subclass them).
- **Do** keep Value Objects, Domain Events, and Use Cases `final readonly`.
- Persist through the domain factory (`Entity::create(...)`), never `new Entity()`.

```php
// Domain/Repository declares the interface; Infrastructure implements it with Doctrine.
final class DoctrineOrderRepository extends ServiceEntityRepository implements OrderRepository
{
    public function save(Order $order): void
    {
        $this->getEntityManager()->persist($order);
        $this->getEntityManager()->flush();
    }

    public function require(OrderId $id): Order
    {
        return $this->find($id->toRfc4122()) ?? throw OrderNotFound::withId($id);
    }
}
```

Map value objects with Doctrine custom types or embeddables so the domain keeps its rich types while the column stays primitive.

## API Platform: State Providers and Processors

Keep controllers thin by driving API Platform through the Application layer. **Providers** handle reads, **Processors** handle writes; both delegate to use cases and never contain business rules.

```php
// Write path - a Processor delegates to a use case.
final readonly class OrderProcessor implements ProcessorInterface
{
    public function __construct(private PlaceOrder $placeOrder) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        return ($this->placeOrder)(PlaceOrderCommand::fromInput($data));
    }
}

// Read path - a Provider delegates to a repository/read model.
final readonly class CampaignCollectionProvider implements ProviderInterface
{
    public function __construct(private CampaignRepository $repository, private Security $security) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): iterable
    {
        return $this->repository->findByTenant($this->security->getUser()->tenantId());
    }
}
```

Declaring `#[ApiResource]` directly on a Domain entity is a pragmatic shortcut **only** when Symfony is the single delivery mechanism; it does couple the entity to a transport concern, so prefer separate resource DTOs when more than one delivery mechanism is likely. Use `stateOptions: new Options(fetchInstead: true)` so State Providers, not Doctrine, own reads.

## CQRS with Messenger

Messenger is the command/query bus. Commands are plain messages; handlers live in the Application layer and carry the `#[AsMessageHandler]` attribute.

```php
final readonly class SyncDataSourceCommand
{
    public function __construct(public string $dataSourceId, public string $tenantId) {}
}

#[AsMessageHandler]
final readonly class SyncDataSourceHandler
{
    public function __construct(private DataSourceRepository $repository, private SyncService $sync) {}

    public function __invoke(SyncDataSourceCommand $command): void
    {
        $dataSource = $this->repository->require(DataSourceId::fromString($command->dataSourceId));
        $this->sync->sync($dataSource);
    }
}
```

Dispatch domain events recorded by aggregates through Messenger after the use case completes, then clear them.

## Multi-Tenancy and Security

Every business entity carries a `TenantId`, and isolation is enforced at the security layer with **Voters**, not with inline `if` checks scattered through the code.

```php
$dataSource = DataSource::create($user->tenant(), $user, $dto->type, $dto->name, $clock->now());
// Access control lives in a Voter, invoked by $this->denyAccessUnlessGranted(...).
```

## Symfony-Specific Anti-Patterns

| Anti-Pattern | Correct Pattern |
|--------------|-----------------|
| `final` on a Doctrine entity | Leave entities non-final; keep VOs/events/use cases `final` |
| Business logic in a State Processor | Processor delegates to a use case |
| EntityManager injected into a use case | Inject a domain repository interface |
| `new DateTime()` | `ClockInterface::now()` |
| Inline tenant checks | Symfony Voters |
| Doctrine `Query` inside the domain | Query lives in Infrastructure; domain stays pure |

## See Also

- `knowledge/ddd/ddd-domain-design.md` - the agnostic entity/value-object/event patterns this implements.
- `knowledge/ddd/ddd-cqrs-architecture.md` - the layered structure and use-case pattern.
- `knowledge/clean-architecture.md` - the Dependency Rule these folders enforce.
