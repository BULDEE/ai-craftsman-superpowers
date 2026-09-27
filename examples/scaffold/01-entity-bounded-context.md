# Example: Scaffold a Domain Entity

## Prompt

```
/craftsman:scaffold entity Order
We need an Order entity for our e-commerce domain with total, status tracking, and payment handling.
```

## Expected Behavior

### Phase 1: Context

The skill reads `.craft-config.yml`, lists `scaffold_types:` from each
`packs/*/pack.yml`, checks that `entity` is among them, then loads the
canonical example the Iron Law names for the type.

```markdown
**symfony:** entity, usecase, api-resource
**react:** component, hook

Canonical example loaded: packs/symfony/knowledge/canonical/php-entity.php
```

Before generating an `entity`, the skill offers the Symfony template variants
shipped in `packs/symfony/templates/`: `bounded-context-backend` (standard DDD
entity), `crud-api` (API Platform 4 CRUD), `event-sourced` (Event Sourcing +
Projections). The user picks `bounded-context-backend`: the order is a domain
aggregate, not a CRUD resource.

### Phase 2: Generate

The entity copies the canonical shape: `final class`, private constructor,
static `create()`, strict types, injected `Clock`, no setters, recorded events.

```php
<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\OrderPaid;
use App\Domain\Event\OrderPlaced;
use App\Domain\ValueObject\Money;
use App\Domain\ValueObject\OrderId;
use App\Shared\Domain\Aggregate\AggregateRoot;
use App\Shared\Domain\Clock\Clock;

final class Order extends AggregateRoot
{
    private function __construct(
        private readonly OrderId $id,
        private readonly Money $total,
        private OrderStatus $status,
        private readonly \DateTimeImmutable $placedAt,
        private ?\DateTimeImmutable $paidAt = null,
    ) {}

    public static function create(Money $total, Clock $clock): self
    {
        $order = new self(
            id: OrderId::generate(),
            total: $total,
            status: OrderStatus::PENDING,
            placedAt: $clock->now(),
        );

        $order->record(new OrderPlaced($order->id, $order->total));

        return $order;
    }

    public function markPaid(Clock $clock): void
    {
        if ($this->status !== OrderStatus::PENDING) {
            throw new OrderNotPayableException($this->id);
        }

        $this->status = OrderStatus::PAID;
        $this->paidAt = $clock->now();

        $this->record(new OrderPaid($this->id));
    }

    public function status(): OrderStatus
    {
        return $this->status;
    }
}
```

Tests are generated alongside, one behavior each, on a frozen clock:

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Domain\Entity;

use App\Domain\Entity\Order;
use App\Domain\Entity\OrderNotPayableException;
use App\Domain\Entity\OrderStatus;
use App\Domain\ValueObject\Money;
use App\Tests\Support\FrozenClock;
use PHPUnit\Framework\TestCase;

final class OrderTest extends TestCase
{
    public function test_a_pending_order_can_be_paid(): void
    {
        $clock = FrozenClock::at('2026-01-01');
        $order = Order::create(Money::ofCents(4999, 'EUR'), $clock);

        $order->markPaid($clock);

        self::assertSame(OrderStatus::PAID, $order->status());
    }

    public function test_a_paid_order_cannot_be_paid_twice(): void
    {
        $clock = FrozenClock::at('2026-01-01');
        $order = Order::create(Money::ofCents(4999, 'EUR'), $clock);
        $order->markPaid($clock);

        $this->expectException(OrderNotPayableException::class);

        $order->markPaid($clock);
    }
}
```

`OrderId`, `Money`, `OrderStatus` and the two events are named as the next
files to scaffold, not invented here; a migration follows only if needed.

### Phase 3: Verify

The gate ran on each write; `/craftsman:verify` then shows commands and output:

```markdown
## Verification Summary

| Check | Command | Status | Evidence |
|-------|---------|--------|----------|
| Unit Tests | `vendor/bin/phpunit tests/Unit/Domain/Entity/OrderTest.php` | pass | 2/2 passed |
| PHPStan | `vendor/bin/phpstan analyse src/Domain/Entity/Order.php` | pass | No errors |

**VERDICT:** ALL VERIFICATIONS PASSED
```

## Key Points

- The canonical example is loaded before any code is generated (the Iron Law);
  the entity copies its shape, including `Clock` injection instead of
  `new \DateTimeImmutable()`
- The template variant is chosen before generation, because moving from a DDD
  aggregate to an event-sourced one later is a refactoring, not a regeneration
- Generated code must pass the quality gate on write; the hook output on the new
  files and the chosen variant are the evidence
