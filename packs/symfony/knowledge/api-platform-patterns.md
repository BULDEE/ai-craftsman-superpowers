# API Platform Patterns

## State-Driven Architecture

API Platform 4.0 introduced State Providers/Processors as the core pattern. Unlike traditional controllers, state handlers own read/write logic.

## Pattern: State Provider for Collection Reads

The `LeadCollectionProvider` demonstrates role-based filtering at query level:

```php
final readonly class LeadCollectionProvider implements ProviderInterface
{
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): iterable
    {
        $user = $this->security->getUser();
        $tenant = $user->getTenant();
        $tenantRole = $user->getTenantRole();

        $filters = $context['filters'] ?? [];
        $page = (int) ($filters['page'] ?? 1);

        if ($tenantRole === TenantRole::SETTER) {
            $filterDTO = LeadQueryFilterDTO::create(
                setter: $user,
                statusRestriction: $this->getSettingPhaseStatuses(),
                page: $page,
                limit: 30,
            );
        } else {
            return [];
        }

        $leads = $this->leadRepository->findByTenantWithFilters($tenant, $filterDTO);
        $totalItems = $this->leadRepository->countByTenantWithFilters($tenant, $filterDTO);

        return new TraversablePaginator(
            new \ArrayIterator($leads),
            $page,
            30,
            $totalItems,
        );
    }
}
```

**Why:** Authorization happens in SQL WHERE (efficient). Filters are validated once. Role-based restrictions are explicit.

## Declarative Operations on Entity

Operations declared on entity via attributes (no separate Resource class):

```php
#[ApiResource(
    operations: [
        new GetCollection(uriTemplate: '/leads', pagination: true),
        new Get(uriTemplate: '/leads/{id}'),
        new Post(processor: CreateLeadProcessor::class),
        new Patch(processor: UpdateLeadProcessor::class),
    ],
    stateOptions: new Options(fetchInstead: true),
)]
class Lead
{
    #[Groups(['lead:read', 'lead:write'])]
    private LeadId $id;

    #[Groups(['lead:read', 'lead:write'])]
    #[SerializedName('email_address')]
    private Email $email;

    #[Groups(['lead:read'])]
    private LeadStatus $status;
}
```

**Why:** Single source of truth. `fetchInstead: true` ensures State Provider controls reads.

## State Processors for Writes

Processors transform HTTP input → entity → persistence:

```php
final readonly class CreateLeadProcessor implements ProcessorInterface
{
    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        $user = $this->security->getUser();
        $tenant = $user->getTenant();

        if (!$data instanceof CreateLeadDTO) {
            throw InvalidInputException::unexpectedType($data);
        }

        $lead = $this->leadFactory->createFromDTO($data, $tenant);
        $this->leadRepository->save($lead);

        foreach ($lead->getDomainEvents() as $event) {
            $this->eventDispatcher->dispatch(
                new GenericEvent($event, ['event' => $event]),
                $event->eventName()
            );
        }

        return $lead;
    }
}
```

## Input DTOs with Validation

Validation on DTO, not entity:

```php
final class CreateLeadDTO
{
    #[Assert\NotBlank]
    #[Assert\Email]
    public string $email;

    #[Assert\Choice(['website', 'social', 'referral'])]
    public string $source;
}
```

**Why:** Decouples API contract from domain model. Entity uses factory pattern; DTO uses validation.

## Pagination with TraversablePaginator

Returns paginated iterator:

```php
return new TraversablePaginator(
    new \ArrayIterator($leads),
    $page,
    $itemsPerPage,
    $totalItems,
);
```

API Platform adds pagination metadata:
- `hydra:totalItems` (total count)
- `hydra:view.hydra:first|last|next` (pagination links)
- `hydra:member` (current page)

## Tag-Based Cache Invalidation

Cache with tenant-scoped tags:

```php
$this->performanceCache->get($cacheKey, function (ItemInterface $item) use (...) {
    $item->expiresAfter($ttl);
    $item->tag([$this->cacheTagManager->forPerformance($tenant)]);
    return $this->repository->getCampaignData($user, $dateRange);
});
```

Invalidate on state changes:

```php
$this->performanceCache->invalidateTags([
    $this->cacheTagManager->forPerformance($tenant),
]);
```

**Why:** One sync invalidates all campaign caches. Tenant-scoped prevents cross-tenant pollution. TTL differs: historical (30d, stable) vs realtime (15min, volatile).

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|-------------|---------|----------|
| Returning raw arrays from providers | Type-unsafe | Return entity objects |
| Filtering after query | N+1 queries on large sets | Apply filters in WHERE clause |
| Authorization in serialization groups | Hidden data still loaded from DB | Apply authorization in State Provider |
| Single processor for all operations | Tangled validation rules | Separate Input DTOs per operation |
| Forgetting cache invalidation | Stale data served | Use tag-based invalidation |
