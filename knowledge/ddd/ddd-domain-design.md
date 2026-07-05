# DDD Tactical Design: Domain Modeling

> "The heart of software is its ability to solve domain-related problems for its user." - Eric Evans

Tactical Domain-Driven Design gives the building blocks for a domain model that is expressive, invariant-safe, and independent of any framework. These patterns are language-agnostic; the examples use PHP and TypeScript, but the ideas hold in any object-capable language. They live in the innermost circle of [[clean-architecture]] and depend on nothing outward.

## Entities and Aggregate Roots

An **Entity** has identity that persists through change. An **Aggregate** is a cluster of entities and value objects treated as one consistency boundary, guarded by a single **Aggregate Root**. All external access goes through the root, which enforces the aggregate's invariants.

- Reference other aggregates by **identity** (an id), never by holding the whole object.
- Load and save aggregates **whole**, through the root; children are never persisted independently.
- Keep aggregates **small**: one transaction should modify one aggregate.

```php
final class Order  // aggregate root
{
    /** @var OrderLine[] */
    private array $lines = [];

    private function __construct(
        private readonly OrderId $id,
        private readonly CustomerId $customerId,   // reference by identity, not the Customer object
        private OrderStatus $status,
    ) {}

    public function addLine(Sku $sku, Quantity $qty, Money $unitPrice): void
    {
        if ($this->status !== OrderStatus::Draft) {
            throw OrderException::cannotModifyConfirmedOrder($this->id);
        }
        $this->lines[] = OrderLine::of($sku, $qty, $unitPrice); // invariant enforced at the root
    }
}
```

## Behavioral Methods, Not Setters

An entity exposes **business operations**, not data accessors. A method name states an intent (`confirm`, `assignToSetter`, `markAsContacted`); a setter states nothing and lets any caller put the object into an invalid state.

```php
// Bad - anemic setters; any caller can corrupt the state
$lead->setStatus("contacted");
$lead->setContactedAt($now);

// Good - one behavioral method that enforces the transition
$lead->markAsContacted($clock->now());
```

```php
public function markAsContacted(DateTimeImmutable $at): void
{
    if ($this->status !== LeadStatus::New) {
        throw LeadStatusException::cannotTransition($this->status, LeadStatus::Contacted);
    }
    $this->status = LeadStatus::Contacted;
    $this->recordDomainEvent(new LeadContactedEvent($this->id, $at));
}
```

A private constructor plus a static factory (`Lead::create(...)`) forces every instance through the invariants; there is no way to build an invalid entity.

## Value Objects

A **Value Object** is an immutable type with no identity, compared by value. Model every domain primitive (Email, Money, Quantity, Percentage) as one; a bare `string` or `int` carries no rules and no meaning.

```php
final readonly class Email
{
    private function __construct(private string $value) {}

    public static function of(string $raw): self
    {
        $normalized = strtolower(trim($raw));
        if (!filter_var($normalized, FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::invalidFormat($raw);
        }
        return new self($normalized);
    }

    public function domain(): string { return substr($this->value, strpos($this->value, '@') + 1); }
    public function equals(self $other): bool { return $this->value === $other->value; }
}
```

```typescript
// The same value object in TypeScript, using a branded type for identity safety.
type Email = string & { readonly __brand: "Email" };
export function email(raw: string): Email {
  const normalized = raw.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized)) throw new Error(`invalid email: ${raw}`);
  return normalized as Email;
}
```

Validate **on construction** so an invalid value object cannot exist in memory. Money is the canonical case: store integer minor units (cents), never floats, and reject cross-currency arithmetic.

### Value Object Collections

Wrap a collection in a value object when it carries its own invariants (no duplicates, ordering, a maximum size). The wrapper offers domain operations (`add`, `byStatus`) and returns a new instance rather than mutating in place.

## Domain Events

A **Domain Event** is an immutable fact about something that already happened, named in the past tense (`OrderConfirmed`, `LeadCreated`). It records only business-relevant data.

```php
final readonly class LeadCreatedEvent implements DomainEvent
{
    public function __construct(
        public LeadId $leadId,
        public DateTimeImmutable $occurredAt,
    ) {}
    public function aggregateId(): string { return $this->leadId->toString(); }
    public function eventName(): string { return "lead.created"; }
}
```

The aggregate **records** events as it mutates; the application layer reads and dispatches them after the operation, then clears them. Keep dispatch out of the domain, so the domain stays free of infrastructure.

```php
trait RecordsDomainEvents
{
    private array $domainEvents = [];
    protected function recordDomainEvent(DomainEvent $e): void { $this->domainEvents[] = $e; }
    public function releaseEvents(): array { $e = $this->domainEvents; $this->domainEvents = []; return $e; }
}
```

## Aggregate Boundaries

The root is the only entry point. Children (an `Appointment` under a `Lead`, an `OrderLine` under an `Order`) are reachable and mutable only through root methods, which is where the invariants live.

```php
public function closeDeal(DealId $dealId, Money $amount): void
{
    $deal = $this->requireDeal($dealId);      // child access mediated by the root
    $deal->close($amount);
    $this->status = LeadStatus::ClosedWon;    // the root keeps itself consistent
    $this->recordDomainEvent(new DealClosedEvent($this->id, $dealId, $amount));
}
```

Never expose the internal collection; hand out copies or query methods, never the array itself.

### Designing an aggregate: the rules in one place

Four questions size an aggregate correctly:

| Question | Guidance |
|----------|----------|
| What must always be true together? | That invariant defines the boundary; everything the rule needs is inside. |
| What can be eventually consistent? | Put it in a *separate* aggregate, referenced by id. |
| How big is one transaction? | One transaction should modify one aggregate. |
| Do children have independent lifecycles? | If yes, they are probably their own aggregates. |

```php
// The factory enforces the creation invariant; behaviors enforce the rest.
final class Order
{
    private function __construct(
        private readonly OrderId $id,
        private array $lines,
        private OrderStatus $status,
    ) {}

    public static function place(CustomerId $customer, array $lines): self
    {
        if ($lines === []) {
            throw OrderException::cannotPlaceEmptyOrder(); // invariant at construction
        }
        return new self(OrderId::generate(), $lines, OrderStatus::Draft);
    }

    public function confirm(): void
    {
        if ($this->status !== OrderStatus::Draft) {
            throw OrderException::alreadyConfirmed($this->id);
        }
        $this->status = OrderStatus::Confirmed;
        $this->recordDomainEvent(new OrderConfirmed($this->id));
    }
}
```

There is no path to an invalid `Order`: no public constructor, no setters, every transition guarded.

## Bounded Contexts

A large domain is not one model but several. A **Bounded Context** is a boundary within which a term has one precise meaning. "Customer" in Sales is not "Customer" in Billing; forcing one shared class couples the two and makes both wrong.

| Context | Aggregate Root | Its language |
|---------|----------------|--------------|
| CRM | Lead | Email, Phone, LeadStatus, Source |
| Attribution | TouchPoint | AttributionModel, Credit |
| Billing | Invoice | Money, TaxRate, DueDate |

- Give each context its **own** value objects; a shared `Email` across contexts is a coupling smell unless it truly means the same thing everywhere.
- Put genuinely universal concepts in a small **Shared Kernel**, and keep it deliberately tiny.
- Contexts communicate by **domain events** and, at their edges, an anti-corruption layer (see [[legacy/strangler-fig]] and [[hexagonal]]).

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Anemic entity (only getters/setters) | Behavior scatters into services; the model states nothing | Behavioral methods that own the invariants |
| Primitive obsession (`string $email`) | No validation, no meaning, duplicated rules | A value object per domain primitive |
| Public setters | Any caller can create an invalid state | Private constructor + factory + behaviors |
| Referencing whole aggregates | Large loads, blurred boundaries, coupled transactions | Reference other aggregates by id |
| Fat shared model across contexts | One term, conflicting meanings, tight coupling | Separate model per bounded context |
| Events with redundant payload | Bloat; hard to evolve | Record only business-relevant facts |

## Related

- [[ddd/ddd-cqrs-architecture]] - use cases, commands/queries, and the layered structure these patterns live in.
- [[clean-architecture]] - entities and use cases are the two inner circles; the Dependency Rule keeps them pure.
- [[hexagonal]] - repository interfaces are driven ports; aggregates are the core inside the hexagon.
- [[principles]] - value objects and small aggregates are SRP and encapsulation made concrete.
