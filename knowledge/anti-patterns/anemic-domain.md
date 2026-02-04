# Anti-Pattern: Anemic Domain Model

## What It Is

An entity that is just a data bag - only getters and setters, no behavior.

## Why It's Bad

- Business logic scattered across services
- Entity can be put in invalid states
- No encapsulation of invariants
- Violates OOP principles

## Example

### BAD: Anemic Entity

```php
final class Order
{
    private string $id;
    private string $status;
    private int $total;
    private ?string $shippedAt;

    // Just getters and setters
    public function getStatus(): string { return $this->status; }
    public function setStatus(string $status): void { $this->status = $status; }

    public function getTotal(): int { return $this->total; }
    public function setTotal(int $total): void { $this->total = $total; }

    public function getShippedAt(): ?string { return $this->shippedAt; }
    public function setShippedAt(?string $at): void { $this->shippedAt = $at; }
}

// Business logic in service - WHERE'S THE VALIDATION?
final class OrderService
{
    public function ship(Order $order): void
    {
        // Anyone can call setStatus('shipped') directly!
        // No guarantee shippedAt is set!
        // No domain event!
        $order->setStatus('shipped');
        $order->setShippedAt((new DateTime())->format('c'));
        $this->repository->save($order);
    }

    public function cancel(Order $order): void
    {
        // What if order is already shipped?
        // This check might be forgotten elsewhere!
        if ($order->getStatus() === 'shipped') {
            throw new Exception('Cannot cancel');
        }
        $order->setStatus('cancelled');
    }
}
```

### GOOD: Rich Domain Model

```php
final class Order
{
    private function __construct(
        private readonly Uuid $id,
        private OrderStatus $status,
        private Money $total,
        private ?DateTimeImmutable $shippedAt,
        private array $domainEvents = [],
    ) {
    }

    public static function create(array $items): self
    {
        $order = new self(
            id: Uuid::v7(),
            status: OrderStatus::PENDING,
            total: self::calculateTotal($items),
            shippedAt: null,
        );

        $order->raise(new OrderCreated($order->id));

        return $order;
    }

    // BEHAVIOR with guards and events
    public function ship(): void
    {
        if (!$this->status->canTransitionTo(OrderStatus::SHIPPED)) {
            throw new InvalidOrderTransition($this->status, OrderStatus::SHIPPED);
        }

        $this->status = OrderStatus::SHIPPED;
        $this->shippedAt = new DateTimeImmutable();

        $this->raise(new OrderShipped($this->id, $this->shippedAt));
    }

    public function cancel(): void
    {
        if (!$this->status->canTransitionTo(OrderStatus::CANCELLED)) {
            throw new InvalidOrderTransition($this->status, OrderStatus::CANCELLED);
        }

        $this->status = OrderStatus::CANCELLED;

        $this->raise(new OrderCancelled($this->id));
    }

    // Read-only access
    public function id(): Uuid { return $this->id; }
    public function status(): OrderStatus { return $this->status; }
    public function total(): Money { return $this->total; }
    public function isShipped(): bool { return $this->status === OrderStatus::SHIPPED; }
}
```

## How to Detect

1. Entity has more getters/setters than behavior methods
2. Service classes contain business logic instead of orchestration
3. Entity state can be changed from outside without validation
4. No domain events for important state changes

## How to Fix

1. Move business logic INTO the entity
2. Replace setters with behavior methods
3. Add guard clauses (invariant protection)
4. Emit domain events for state changes
5. Use Value Objects for typed fields

## Rule

> "Tell, don't ask" - Tell the entity what to do, don't ask for its state and manipulate it externally.
