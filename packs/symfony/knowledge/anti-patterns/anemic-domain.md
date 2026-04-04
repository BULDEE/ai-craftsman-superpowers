# Anti-Pattern: Anemic Domain Model

## Problem

Entities with only getters/setters and no business logic. All behavior lives in services, turning entities into dumb data bags.

## Bad

```php
final class Order
{
    private string $status = 'draft';

    public function getStatus(): string { return $this->status; }
    public function setStatus(string $status): void { $this->status = $status; }
}

// Service does all the work
final class OrderService
{
    public function cancel(Order $order): void
    {
        if ($order->getStatus() === 'shipped') {
            throw new \DomainException('Cannot cancel shipped order');
        }
        $order->setStatus('cancelled');
    }
}
```

## Good

```php
final class Order
{
    private OrderStatus $status;

    private function __construct(OrderStatus $status)
    {
        $this->status = $status;
    }

    public static function create(): self
    {
        return new self(OrderStatus::Draft);
    }

    public function cancel(): void
    {
        if ($this->status === OrderStatus::Shipped) {
            throw OrderException::cannotCancelShipped();
        }
        $this->status = OrderStatus::Cancelled;
    }
}
```

## Why It Matters

- Invariants scattered across services instead of enforced by the entity
- No encapsulation: any service can set any state
- Logic duplication when multiple services manipulate the same entity
- Violates Tell Don't Ask principle

## Detection

Rule PHP005 warns on public setters. Entities with only getters and no behavior methods are suspicious.
