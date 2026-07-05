# Anti-Pattern: God Object

## What It Is

A single class that knows too much and does too much: it orchestrates, persists, formats, validates, and decides. Everything routes through it, so every change touches it. This plugin flags it structurally as `GOD001` (too many methods/responsibilities/dependencies in one class).

## Why It's Bad

- Violates Single Responsibility: it has many reasons to change.
- Impossible to unit-test in isolation; every test needs the whole world.
- A merge-conflict magnet, because every feature edits the same file.
- Hides missing boundaries: the class is where an architecture should have been drawn (see [[clean-architecture]]).

## Example

### BAD: One class does everything

```php
final class OrderManager
{
    public function placeOrder(array $request): array
    {
        // validation
        if (empty($request['items'])) { throw new \Exception('no items'); }
        // pricing rule
        $total = 0;
        foreach ($request['items'] as $i) { $total += $i['price'] * $i['qty']; }
        // persistence
        $this->db->insert('orders', ['total' => $total]);
        // payment (third party)
        $this->stripe->charge($total, $request['card']);
        // formatting the response
        return ['status' => 'ok', 'total' => number_format($total / 100, 2)];
    }
}
```

### GOOD: Responsibilities split behind boundaries

```php
// Use case orchestrates; each collaborator has one job.
final readonly class PlaceOrder
{
    public function __construct(
        private OrderRepository $orders,      // persistence
        private PaymentGateway $payments,     // third party, behind a port
    ) {}

    public function __invoke(PlaceOrderCommand $command): OrderId
    {
        $order = Order::place($command->customerId, $command->lines); // rules in the entity
        $this->payments->charge($order->total(), $command->card);
        $this->orders->save($order);
        return $order->id();
    }
}
```

Pricing lives in the `Order` entity, persistence behind `OrderRepository`, payment behind `PaymentGateway`, formatting in a presenter. No single class owns all of it.

## How to Detect

1. `GOD001` fires (high method count, many dependencies, large class).
2. The class name ends in `Manager`, `Helper`, `Util`, or `Service` and keeps growing.
3. You cannot describe the class's responsibility in one sentence without "and".
4. Every feature branch edits this file.

## How to Fix

1. List the distinct responsibilities the class currently holds.
2. Extract each into its own class (Extract Class - see [[refactoring-techniques]]).
3. Push business rules into the relevant entity or value object.
4. Put I/O and third-party calls behind ports ([[hexagonal]]).
5. Reduce the original class to a thin orchestrator (a use case) or delete it.

## Rule

> If you cannot state a class's single responsibility in one sentence, it has more than one.
