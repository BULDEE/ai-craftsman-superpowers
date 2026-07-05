# DDD + CQRS Architecture

> "Treat the domain model as the heart, and keep everything else at arm's length."

This file is the structural companion to [[ddd/ddd-domain-design]]: how the tactical building blocks are arranged into layers, how use cases orchestrate them, and how Command-Query Separation scales into CQRS. It is framework-agnostic; the [[clean-architecture]] Dependency Rule is the law that holds it together.

## The Layers

The layout is the four circles of Clean Architecture made into folders. Dependencies point strictly inward.

```
Domain/          # imports NOTHING - pure business rules
  Entity/        # aggregates and entities
  ValueObject/   # immutable, self-validating types
  Repository/    # interfaces only (driven ports)
  Event/         # domain events (immutable facts)
  Service/       # domain services (cross-aggregate rules)
  Exception/     # domain-specific errors

Application/     # imports Domain only
  UseCase/       # one class = one use case
  Command/       # write intentions
  Query/         # read intentions
  DTO/           # typed input/output at the boundary
  Port/          # output interfaces the domain needs

Infrastructure/  # imports Domain + Application
  Persistence/   # repository implementations
  External/      # third-party clients (driven adapters)

Presentation/    # imports Domain + Application
  Api/           # controllers (driving adapters)
  Console/       # CLI commands
```

The one rule that matters, mechanically checkable:

```bash
# Domain must import nothing from outer layers.
grep -rq 'Infrastructure\|Presentation' src/Domain/ && echo VIOLATION || echo OK
```

For a large system, subdivide `Domain/` by [[ddd/ddd-domain-design]] bounded context (`Domain/Crm/`, `Domain/Billing/`, `Domain/SharedKernel/`) rather than by technical type.

## The Use Case Pattern

A use case is one class with one responsibility: orchestrate entities to fulfill one application-specific operation. It receives its dependencies as interfaces and its input as a typed DTO.

```php
final readonly class PlaceOrder
{
    public function __construct(
        private OrderRepository $orders,   // driven port, not a concrete DB class
        private Clock $clock,              // injected, never `new DateTime()`
    ) {}

    public function __invoke(PlaceOrderCommand $command): OrderId
    {
        $order = Order::place(
            $command->customerId,
            $command->lines,
            $this->clock->now(),
        );
        $this->orders->save($order);
        return $order->id();
    }
}
```

Four rules keep use cases clean:

| Rule | Why |
|------|-----|
| Depend on repository **interfaces** | The use case stays free of persistence details |
| Inject a **Clock**, never `new DateTime()` | Time becomes testable and deterministic |
| Accept a typed **DTO/Command**, not a raw request | The web format never leaks inward |
| Build entities via a **factory** (`Order::place`) | Invariants are enforced at construction |

## Command-Query Separation, Then CQRS

CQS is the small-scale rule: a method either **changes state** (command, returns nothing meaningful) or **returns data** (query, no side effect), never both. CQRS scales this to the application: model writes and reads as separate paths.

- **Commands** express a write intention (`PlaceOrderCommand`, `SyncDataSourceCommand`). A single handler mutates one aggregate and returns at most an id.
- **Queries** express a read intention and return a **read model** shaped for the caller, often bypassing the aggregate entirely and reading a projection.

```php
// Command handler - writes, returns nothing but an id.
final readonly class ConfirmOrderHandler
{
    public function __construct(private OrderRepository $orders) {}
    public function __invoke(ConfirmOrderCommand $c): void
    {
        $order = $this->orders->require(new OrderId($c->orderId));
        $order->confirm();
        $this->orders->save($order);
    }
}
```

Do not reach for full CQRS everywhere: separate read models earn their cost when reads and writes have genuinely different shapes or scaling needs. Until then, CQS within a single model is enough.

## Repository Pattern

The domain declares the repository as an **interface** (a driven port); infrastructure implements it. The domain never names the ORM.

```php
// Domain/Repository/OrderRepository.php - a port, lives in the domain
interface OrderRepository
{
    public function save(Order $order): void;
    public function find(OrderId $id): ?Order;
    public function require(OrderId $id): Order;   // throws if absent
}
```

A repository deals in **whole aggregates**, not partial rows. If you need a flat projection for a screen, that is a read model on the query side, not a repository method.

## Read Models and Projections

Queries return **read models**: plain, read-optimized structures denormalized for a specific view. They are not entities and carry no behavior. Building them from domain events (a projection) keeps the write model small while serving fast, tailored reads. This is the same Humble Object idea from [[clean-architecture]]: hard-to-change persistence sits behind a simple, replaceable shape.

## Anti-Patterns

| Anti-Pattern | Correct Pattern |
|--------------|-----------------|
| Domain imports Infrastructure | Domain imports nothing |
| `new DateTime()` in a use case | Inject a `Clock` |
| `new Entity(...)` | `Entity::create(...)` factory |
| Persistence manager inside a use case | Depend on a repository interface |
| Raw array or request object as input | A typed DTO / Command |
| A command that also returns domain data | Separate query from modifier (CQS) |
| Business logic in a controller | Logic in a use case; controller only translates |

## Related

- [[ddd/ddd-domain-design]] - the entities, value objects, and events these layers orchestrate.
- [[clean-architecture]] - the Dependency Rule and the circle-to-folder mapping.
- [[hexagonal]] - repositories as driven ports, controllers as driving adapters, the composition root.
- [[event-driven]] - dispatching the domain events that drive projections and cross-context communication.
