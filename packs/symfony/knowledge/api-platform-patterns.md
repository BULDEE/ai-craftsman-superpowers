# API Platform Patterns

## Resource Declaration

```php
#[ApiResource(
    operations: [
        new GetCollection(),
        new Get(),
        new Post(processor: CreateOrderProcessor::class),
    ],
    normalizationContext: ['groups' => ['order:read']],
    denormalizationContext: ['groups' => ['order:write']],
)]
final class Order
{
    #[Groups(['order:read'])]
    public readonly int $id;

    #[Groups(['order:read', 'order:write'])]
    #[Assert\NotBlank]
    public string $reference;
}
```

## State Providers & Processors

API Platform is **100% independent of the persistence system**.

```php
// State Provider: reads data from any source
final class OrderProvider implements ProviderInterface
{
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        // Query database, API, cache, filesystem...
    }
}

// State Processor: writes data to any destination
final class CreateOrderProcessor implements ProcessorInterface
{
    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        // Business logic + persistence
    }
}
```

## Architecture: DTOs Over Entities

Separate API contract from domain model:

```php
// API Resource (DTO) — public contract
#[ApiResource]
final class OrderOutput
{
    public readonly int $id;
    public readonly string $reference;
    public readonly string $status;
}

// Domain Entity — internal model (no #[ApiResource])
final class Order
{
    // Rich domain model with behavior
}

// Provider maps entity → DTO
// Processor maps DTO → entity
```

## Serialization Groups

Control what's exposed per operation:

```php
#[ApiResource(
    normalizationContext: ['groups' => ['order:read']],
    operations: [
        new GetCollection(normalizationContext: ['groups' => ['order:list']]),
        new Get(normalizationContext: ['groups' => ['order:read', 'order:detail']]),
    ],
)]
```

## Validation

Constraints on the resource class, auto-validated by API Platform:

```php
#[Assert\NotBlank]
#[Assert\Length(min: 3, max: 255)]
public string $reference;

#[Assert\Range(min: 0)]
public int $quantity;
```

Errors returned in Hydra format with field-level detail.

## Filters & Pagination

```php
#[ApiResource(paginationItemsPerPage: 30)]
#[ApiFilter(SearchFilter::class, properties: ['reference' => 'partial'])]
#[ApiFilter(OrderFilter::class, properties: ['createdAt'])]
#[ApiFilter(DateFilter::class, properties: ['createdAt'])]
final class Order { }
```

## Security

```php
#[ApiResource(
    operations: [
        new Get(security: "is_granted('VIEW', object)"),
        new Put(security: "is_granted('EDIT', object)"),
        new Delete(security: "is_granted('ROLE_ADMIN')"),
    ],
)]
```

Use Symfony Voters for complex authorization (not inline expressions).

## HTTP Caching

Built-in cache invalidation with Varnish:

```php
#[ApiResource(
    cacheHeaders: ['max_age' => 3600, 'shared_max_age' => 7200],
)]
```

## Content Negotiation

Supported formats: JSON-LD (default), JSON:API, HAL, GraphQL, OpenAPI, CSV, XML.

## Anti-Patterns

| Anti-Pattern | Instead |
|-------------|---------|
| Exposing Doctrine entities directly | Use DTOs as API resources |
| Business logic in processors | Domain model with behavior |
| Complex security expressions | Symfony Voters |
| Manual OpenAPI docs | Auto-generated from attributes |
| Custom serialization logic | Serialization groups |
| Raw SQL in providers | Repository pattern |
| Pagination disabled | Default 30 items, customize per resource |
