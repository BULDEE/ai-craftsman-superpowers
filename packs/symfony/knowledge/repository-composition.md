---
name: Repository Composition Pattern
description: Fine-grained repository interface composition — separate interfaces per use case instead of god repositories
type: methodology
---

# Repository Composition Pattern

The traditional Repository pattern defines one interface per aggregate: `UserRepository`, `OrderRepository`. This creates a "god repository" that grows with every new query requirement.

Repository Composition flips this: define **small, focused interfaces** per use case, then have the implementation satisfy multiple interfaces.

## Pattern: Composition Over Inheritance

In Metrikia, `LeadRepository` satisfies 7 distinct interface contracts:

```php
interface LeadRepositoryInterface extends
    LeadWriteRepositoryInterface,
    LeadTenantQueryRepositoryInterface,
    LeadDeduplicationRepositoryInterface,
    LeadAttributionRepositoryInterface,
    LeadGdprRepositoryInterface,
    LeadReportingRepositoryInterface,
    LeadTaskBoxRepositoryInterface
{
    // No methods — this is pure composition
}
```

Each interface defines methods for a specific business capability:

```php
// Write operations: persist, delete, update
interface LeadWriteRepositoryInterface
{
    public function save(Lead $lead): void;
    public function persist(Lead $lead): void;
    public function remove(Lead $lead): void;
}

// Tenant-scoped queries: the API's primary use case
interface LeadTenantQueryRepositoryInterface
{
    public function findByTenantWithFilters(Tenant $tenant, LeadQueryFilterDTO $filters): array;
    public function countByTenantWithFilters(Tenant $tenant, LeadQueryFilterDTO $filters): int;
    public function findByUserAndTenant(User $user, Tenant $tenant): array;
}

// Deduplication: find leads by email to prevent duplicates
interface LeadDeduplicationRepositoryInterface
{
    public function findByEmailAndTenant(Email $email, Tenant $tenant): ?Lead;
    public function findDuplicatesByEmail(Email $email): array;
}

// Attribution: retrieve leads for campaign-to-lead correlation
interface LeadAttributionRepositoryInterface
{
    public function findLeadsByDateRange(DateRange $range, Tenant $tenant): array;
    public function findLeadsWithAppointments(Tenant $tenant): array;
    public function findLeadsWithDeals(Tenant $tenant): array;
}

// GDPR: find and delete user data
interface LeadGdprRepositoryInterface
{
    public function findByEmail(Email $email): array;
    public function deleteByTenant(Tenant $tenant): void;
}

// Reporting: analytics and trend queries
interface LeadReportingRepositoryInterface
{
    public function countByStatus(Tenant $tenant, LeadStatus $status): int;
    public function countBySourceAndTenant(Tenant $tenant, string $source): int;
    public function getAverageConversionTime(Tenant $tenant): int;
}

// Task workflows: find leads for assignment/routing
interface LeadTaskBoxRepositoryInterface
{
    public function findUnassignedLeads(Tenant $tenant, int $limit): array;
    public function findLeadsAssignedToUser(User $user): array;
}
```

## Implementation

The concrete repository implements all interfaces:

```php
final class LeadRepository extends ServiceEntityRepository implements LeadRepositoryInterface
{
    public function __construct(RegistryInterface $registry)
    {
        parent::__construct($registry, Lead::class);
    }

    // LeadWriteRepositoryInterface
    public function save(Lead $lead): void
    {
        $this->getEntityManager()->persist($lead);
        $this->getEntityManager()->flush();
    }

    // LeadTenantQueryRepositoryInterface
    public function findByTenantWithFilters(Tenant $tenant, LeadQueryFilterDTO $filters): array
    {
        $qb = $this->createQueryBuilder('l')
            ->where('l.tenant = :tenant')
            ->setParameter('tenant', $tenant)
            ->addOrderBy('l.createdAt', $filters->sortOrder ?? 'DESC');

        if ($filters->status) {
            $qb->andWhere('l.status = :status')
                ->setParameter('status', $filters->status);
        }

        if ($filters->statusRestriction) {
            $qb->andWhere('l.status IN (:statuses)')
                ->setParameter('statuses', $filters->statusRestriction);
        }

        if ($filters->setter) {
            $qb->andWhere('l.setter = :setter')
                ->setParameter('setter', $filters->setter);
        }

        return $qb
            ->setFirstResult(($filters->page - 1) * $filters->limit)
            ->setMaxResults($filters->limit)
            ->getQuery()
            ->getResult();
    }

    public function countByTenantWithFilters(Tenant $tenant, LeadQueryFilterDTO $filters): int
    {
        $qb = $this->createQueryBuilder('l')
            ->select('COUNT(l.id)')
            ->where('l.tenant = :tenant')
            ->setParameter('tenant', $tenant);

        if ($filters->statusRestriction) {
            $qb->andWhere('l.status IN (:statuses)')
                ->setParameter('statuses', $filters->statusRestriction);
        }

        return (int) $qb->getQuery()->getSingleScalarResult();
    }

    // LeadDeduplicationRepositoryInterface
    public function findByEmailAndTenant(Email $email, Tenant $tenant): ?Lead
    {
        return $this->createQueryBuilder('l')
            ->where('l.email = :email')
            ->andWhere('l.tenant = :tenant')
            ->setParameter('email', $email->value())
            ->setParameter('tenant', $tenant)
            ->getQuery()
            ->getOneOrNullResult();
    }

    // ... other interface methods
}
```

## Dependency Injection by Interface

Code depends on specific interfaces, not the full repository:

```php
// API Provider receives only what it needs
final readonly class LeadCollectionProvider
{
    public function __construct(
        private LeadTenantQueryRepositoryInterface $leadRepository,  // Only query methods
        private Security $security,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): iterable
    {
        // Can only call findByTenantWithFilters(), countByTenantWithFilters()
        // Cannot accidentally call save(), deleteByTenant(), etc.
    }
}

// Deduplication service receives only deduplication methods
final readonly class DeduplicateLeadHandler
{
    public function __construct(
        private LeadDeduplicationRepositoryInterface $leadRepository,  // Only dedup methods
    ) {}

    public function handle(DeduplicateLeadCommand $command): void
    {
        $existing = $this->leadRepository->findByEmailAndTenant(
            $command->email,
            $command->tenant
        );
        // Cannot access $this->leadRepository->deleteByTenant() — method doesn't exist
    }
}

// GDPR processor receives only GDPR methods
final readonly class DeleteUserDataProcessor implements ProcessorInterface
{
    public function __construct(
        private LeadGdprRepositoryInterface $leadRepository,  // Only GDPR methods
    ) {}

    public function process(DeleteUserCommand $command): void
    {
        $leads = $this->leadRepository->findByEmail($command->email);
        // Cannot access reporting methods or write operations
    }
}
```

## Advantages

| Advantage | Example |
|-----------|---------|
| **Interface Segregation** | API Provider doesn't see dedup/GDPR/reporting methods. Can't misuse. |
| **Testability** | Mock only the interface needed, not 40 methods. |
| **Clear Intent** | `LeadTenantQueryRepositoryInterface` tells you: this is for filtered tenant queries. |
| **Evolutionary** | Add new interface (e.g., `LeadCacheRepositoryInterface`) without touching existing code. |
| **Self-Documenting** | Repository interfaces are the spec. 7 interfaces = 7 distinct use cases. |

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| God Repository | One interface with 50+ methods; every class depends on all of them | Use 5-7 small interfaces, each focused |
| Inheritance-based repos | `ExtendedOrderRepository extends OrderRepository` coupling | Compose interfaces instead; let one class implement many |
| Method names that say what, not why | `getLeadsByStatus()` vs `findLeadsInSettingPhase()` | Name for the use case (`TenantQuery`, `Attribution`) |
| Sharing repositories across contexts | Lead repository used by CRM *and* Reporting *and* Onboarding | Define bounded-context-specific interfaces; let infrastructure implement both |
| Parameterized load methods | `find($entityId, $eager=true, $cache=false, $lock=true)` | Separate interfaces per load strategy |

## Real-World Example: When to Create a New Interface

```php
// Scenario: Analytics team needs to calculate lead conversion funnel
// This is NOT a TenantQuery use case (doesn't support filtering by user role)
// This is NOT an Attribution use case (different metrics)

// Create new interface in Domain/Repository/
interface LeadFunnelRepositoryInterface
{
    public function countByStatusAndDateRange(Tenant $tenant, DateRange $range): array;
    public function getAverageTimeInStatus(Tenant $tenant, LeadStatus $status): int;
    public function countDropoffsAtStatus(Tenant $tenant, LeadStatus $status): int;
}

// Implement in Infrastructure/Persistence/Doctrine/
final class LeadRepository extends ServiceEntityRepository implements LeadFunnelRepositoryInterface
{
    public function countByStatusAndDateRange(Tenant $tenant, DateRange $range): array
    {
        return $this->createQueryBuilder('l')
            ->select('l.status, COUNT(l.id) as count')
            ->where('l.tenant = :tenant')
            ->andWhere('l.createdAt BETWEEN :start AND :end')
            ->groupBy('l.status')
            ->getQuery()
            ->getResult();
    }
}

// Inject in Analytics service
final readonly class FunnelAnalyzer
{
    public function __construct(
        private LeadFunnelRepositoryInterface $leadRepository,
    ) {}

    public function analyze(Tenant $tenant): FunnelReport
    {
        $counts = $this->leadRepository->countByStatusAndDateRange(
            $tenant,
            DateRange::thisMonth()
        );
        // ... analysis logic
    }
}
```

## Naming Convention

| Interface Name | When to Use |
|----------------|------------|
| `{Entity}WriteRepositoryInterface` | Insert, update, delete operations |
| `{Entity}{Context}QueryRepositoryInterface` | Context-specific queries (TenantQuery, Attribution, Reporting) |
| `{Entity}DeduplicationRepositoryInterface` | Duplicate detection (email, phone, external ID) |
| `{Entity}GdprRepositoryInterface` | Data deletion, privacy compliance |
| `{Entity}CacheRepositoryInterface` | Cache read-through, write-back patterns |
| `{Entity}ReportingRepositoryInterface` | Analytics, aggregations, trends |

This ensures developers know the interface purpose at a glance.
