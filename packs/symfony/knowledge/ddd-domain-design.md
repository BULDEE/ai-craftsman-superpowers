---
name: DDD Domain Design
description: Domain-Driven Design patterns — entities, value objects, aggregates, domain events, and bounded contexts in Symfony
type: methodology
---

# DDD Domain Design in Symfony

## Entities as Aggregate Roots

Entities in DDD are not data containers — they are behavioral aggregates that encapsulate business logic and enforce invariants.

### Pattern: API Platform Native Attributes

In Metrikia, entities declare API Platform operations directly via attributes:

```php
#[ApiResource(
    operations: [
        new GetCollection(
            uriTemplate: '/leads',
            name: 'lead_collection',
            pagination: true,
        ),
        new Get(uriTemplate: '/leads/{id}'),
        new Post(uriTemplate: '/leads'),
        new Patch(uriTemplate: '/leads/{id}'),
        new Delete(uriTemplate: '/leads/{id}'),
    ],
    stateOptions: new Options(
        fetchInstead: true,  // Use State Provider
    ),
)]
class Lead implements AggregateRoot, TenantAware
{
    // Entity definition
}
```

**Why:** API Platform operations declared on the entity eliminate duplication with separate resource classes. The `fetchInstead` option ensures State Providers (not Doctrine) control reads.

### Pattern: Behavioral Methods Over Getters

Entities expose business behavior, not data:

```php
final class Lead
{
    private function __construct(
        private readonly LeadId $id,
        private readonly Tenant $tenant,
        private readonly Email $email,
        private LeadStatus $status = LeadStatus::NEW,
        private ?User $setter = null,
        private readonly DateTime $createdAt,
    ) {}

    public static function create(
        LeadId $id,
        Tenant $tenant,
        Email $email,
        ?User $setter = null,
    ): self {
        $self = new self($id, $tenant, $email);
        $self->recordDomainEvent(new LeadCreatedEvent($id, $tenant, $email));
        return $self;
    }

    public function assignToSetter(User $setter): void
    {
        if ($this->setter?->getId()->equals($setter->getId())) {
            return;  // Already assigned
        }
        $this->setter = $setter;
        $this->recordDomainEvent(new LeadAssignedEvent($this->id, $setter));
    }

    public function markAsContacted(): void
    {
        if ($this->status !== LeadStatus::NEW) {
            throw LeadStatusException::cannotTransition($this->status, LeadStatus::CONTACTED);
        }
        $this->status = LeadStatus::CONTACTED;
    }
}
```

**Why:**
- `assignToSetter()` prevents duplicate assignments by checking identity before recording event
- `markAsContacted()` enforces state transitions — not all statuses can transition to CONTACTED
- Private constructor + factory enforces creation invariants
- No `setStatus()` or `setSetter()` — state changes are explicit business operations

## Value Objects

Value Objects are immutable domain primitives. They model concepts like Email, Money, UserId as first-class types.

### Pattern: Immutable Factory + Validation

```php
final readonly class Email implements \Stringable
{
    private string $value;

    private function __construct(string $value)
    {
        $normalized = strtolower(trim($value));

        if ($normalized === '') {
            throw InvalidEmailException::emptyEmail();
        }

        if (!filter_var($normalized, \FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::invalidFormat($value);
        }

        $this->value = $normalized;
    }

    public static function fromString(string $value): self
    {
        return new self($value);
    }

    public function domain(): string
    {
        $atPosition = strpos($this->value, '@');
        if ($atPosition === false) {
            return '';
        }
        return substr($this->value, $atPosition + 1);
    }

    public function hash(): string
    {
        return hash('sha256', EmailNormalizer::normalize($this->value));
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }
}
```

**Why:**
- Private constructor forces construction through factory
- Validation on construction prevents invalid Email objects in memory
- `equals()` compares value identity, not object identity
- `hash()` provides deterministic hashing for deduplication
- Methods like `domain()` and `localPart()` encapsulate string extraction logic

### Pattern: Value Object Collections

```php
final readonly class DealPipeline
{
    /** @var array<Deal> */
    private array $deals;

    private function __construct(array $deals)
    {
        // Validate: no duplicate deal IDs
        $ids = array_map(fn(Deal $d) => $d->getId()->value(), $deals);
        if (count($ids) !== count(array_unique($ids))) {
            throw DealException::duplicateDeals();
        }
        $this->deals = $deals;
    }

    public static function create(Deal ...$deals): self
    {
        return new self(array_values($deals));
    }

    public function add(Deal $deal): self
    {
        $updated = [...$this->deals, $deal];
        return new self($updated);
    }

    public function byStatus(DealStatus $status): self
    {
        $filtered = array_filter($this->deals, fn(Deal $d) => $d->getStatus()->equals($status));
        return new self(array_values($filtered));
    }
}
```

**Why:** Collections enforce invariants (no duplicates) and provide domain-specific operations like filtering by status.

## Domain Events

Domain Events record business-significant changes. They are immutable facts about what happened.

```php
final readonly class LeadCreatedEvent implements DomainEventInterface
{
    public function __construct(
        private readonly LeadId $leadId,
        private readonly TenantId $tenantId,
        private readonly Email $email,
        private readonly string $sourceName,
        private readonly DateTime $occurredAt = new DateTime(),
    ) {}

    public function aggregateId(): string
    {
        return $this->leadId->value();
    }

    public function eventName(): string
    {
        return 'lead.created';
    }

    public function toArray(): array
    {
        return [
            'lead_id' => $this->leadId->value(),
            'tenant_id' => $this->tenantId->value(),
            'email' => $this->email->value(),
            'source_name' => $this->sourceName,
            'occurred_at' => $this->occurredAt->format(\DateTime::ATOM),
        ];
    }
}
```

**Why:**
- Minimal structure — only business-relevant data
- `aggregateId()` and `eventName()` enable event sourcing and handlers
- `toArray()` provides serialization for persistence/messaging
- Immutable — once created, event facts don't change

### Pattern: Domain Event Recording

```php
trait RecordsDomainEvents
{
    /** @var array<DomainEventInterface> */
    private array $domainEvents = [];

    protected function recordDomainEvent(DomainEventInterface $event): void
    {
        $this->domainEvents[] = $event;
    }

    /** @return array<DomainEventInterface> */
    public function getDomainEvents(): array
    {
        return $this->domainEvents;
    }

    public function clearDomainEvents(): void
    {
        $this->domainEvents = [];
    }
}
```

Application layer (event dispatcher) reads domain events after entity operations and publishes them:

```php
// In command handler or use case:
$lead = $leadRepository->find($leadId);
$lead->assignToSetter($newSetter);

// Dispatch all recorded events
foreach ($lead->getDomainEvents() as $event) {
    $this->eventDispatcher->dispatch(
        new GenericEvent($event, ['event' => $event]),
        $event->eventName()
    );
}
$lead->clearDomainEvents();
```

## Aggregate Roots and Boundaries

An Aggregate Root controls access to its child entities. In Metrikia, Lead is the root; Appointments and Deals are children.

```php
final class Lead implements AggregateRoot
{
    /** @var array<Appointment> */
    private array $appointments = [];

    /** @var array<Deal> */
    private array $deals = [];

    public function addAppointment(Appointment $appointment): void
    {
        if ($appointment->getLeadId() !== $this->id) {
            throw AppointmentException::invalidLead();
        }
        $this->appointments[] = $appointment;
        $this->recordDomainEvent(new AppointmentAddedEvent($this->id, $appointment->getId()));
    }

    public function closeDeal(DealId $dealId, Money $amount): void
    {
        $deal = $this->findDeal($dealId);
        if (!$deal) {
            throw DealException::notFound($dealId);
        }
        $deal->close($amount);
        $this->status = LeadStatus::CLOSED_WON;
        $this->recordDomainEvent(new DealClosedEvent($this->id, $dealId, $amount));
    }

    private function findDeal(DealId $dealId): ?Deal
    {
        foreach ($this->deals as $deal) {
            if ($deal->getId()->equals($dealId)) {
                return $deal;
            }
        }
        return null;
    }
}
```

**Why:**
- All Appointment/Deal modifications go through Lead methods
- Lead enforces invariants (Appointment must belong to this Lead)
- No external access to `$appointments` array — only through behaviors
- Repositories only load/save the aggregate root; children are fetched with it

## Bounded Contexts

Metrikia models multiple independent domains:

| Context | Root Entity | Key Value Objects |
|---------|------------|-------------------|
| **CRM** | Lead | Email, Phone, LeadStatus, LeadSource |
| **Attribution** | TouchPoint | AttributionModel, TouchpointType, Credit |
| **Ads** | Campaign | CampaignId, Spend, CPC, CPA |
| **Deals** | Deal | DealId, DealStatus, Money, Pipeline |
| **Onboarding** | DataSource | DataSourceId, SyncToken, SyncStatus |

Each context has:
- Separate entity definitions (no shared entity classes)
- Isolated repositories
- Event-driven communication between contexts (via domain events and handlers)

Example: When a Lead is created in CRM, a `LeadCreatedEvent` is published. The Attribution context subscribes and creates an initial TouchPoint; the Ads context subscribes and can link lead attribution to campaigns.

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Entities as DTOs | Blurs behavior and data; lose domain intent | Always use behavioral methods (`assignToSetter()` not `setSetter()`) |
| Shared value objects across contexts | Tight coupling; context-specific requirements conflict | Define separate value objects per context (CRM Email ≠ Notification Email) |
| Lazy-loaded relationships in aggregates | N+1 queries; unclear loading strategy | Eager load children in repository; explicit in domain |
| Domain logic in controllers | Logic scattered; testability lost | Place logic in entities/services; controllers orchestrate |
| Events with redundant data | Bloat; difficult to evolve | Record only business-relevant facts; consumers hydrate from read models |
