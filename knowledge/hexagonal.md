# Hexagonal Architecture (Ports & Adapters)

> An application should be driven equally by users, programs, automated tests, or batch scripts, and be developed and tested in isolation from its eventual run-time devices and databases.

Hexagonal Architecture is the same idea as [[clean-architecture]] seen from the outside in. Instead of concentric circles it draws one **application hexagon** surrounded by **adapters**, joined at **ports**. The hexagon has no favoured side: the UI and the database are both just adapters plugged into ports.

## The Core Idea

- The **application** (domain + use cases) sits inside the hexagon and depends on **nothing** outside it.
- A **port** is an interface **owned by the application** that describes a conversation it needs to have.
- An **adapter** is an implementation of a port that speaks to a specific technology (HTTP, CLI, Postgres, Stripe).
- To test the application, substitute a test adapter at the same port. Nothing inside the hexagon changes.

The hexagon shape carries no meaning beyond "more than four sides": it is a reminder that there are many ways in and many ways out, not just a UI on top and a database on the bottom.

## The Problem It Solves

The pattern exists to escape a recurring trap: business logic that leaks into the UI and gets entangled with the database, so the application can only ever be driven by one screen and tested against one live database. The symptoms are familiar: logic duplicated between a web controller and a batch job, a test suite that needs a running database, a rewrite forced by swapping a vendor. Ports & Adapters removes the asymmetry: the application is driven identically whether the driver is a person, another program, an automated test, or a batch script, and it is developed and tested in isolation from its eventual devices and databases.

## Two Kinds of Ports

The symmetry of the pattern is its whole point. Ports come in two families:

| | Driving (primary) | Driven (secondary) |
|---|-------------------|--------------------|
| Who starts the conversation | The **outside** calls the app | The **app** calls the outside |
| Port declared for | Use cases the app offers | Capabilities the app requires |
| Example port | `PlaceOrder`, `RegisterUser` | `OrderRepository`, `PaymentGateway`, `Clock` |
| Example adapter | REST controller, CLI command, message consumer, test harness | Doctrine repository, Stripe client, system clock, in-memory fake |
| Dependency direction | Adapter depends on app | Adapter depends on app (implements its port) |

Both adapter families depend on the application; the application depends on neither. That is the Dependency Rule restated: everything points at the hexagon.

## Port Placement in Code

A **driving port** is the use case's own input interface. A **driven port** is an interface the use case declares for what it needs and the infrastructure implements.

```php
// Driven port - declared INSIDE the hexagon (Application/Domain owns it)
namespace App\Application\Port;

interface PaymentGateway
{
    public function charge(Money $amount, CardToken $card): PaymentReceipt;
}

// Driving port - the use case the app offers to the outside
namespace App\Application\UseCase;

final class PlaceOrder
{
    public function __construct(
        private readonly OrderRepository $orders,   // driven port
        private readonly PaymentGateway $payments,  // driven port
    ) {}

    public function __invoke(PlaceOrderCommand $command): OrderId { /* ... */ }
}
```

```php
// Driven adapter - lives OUTSIDE the hexagon (Infrastructure), implements the port
namespace App\Infrastructure\Payment;

use App\Application\Port\PaymentGateway;

final class StripePaymentGateway implements PaymentGateway
{
    public function charge(Money $amount, CardToken $card): PaymentReceipt
    {
        // talk to the Stripe SDK here, and nowhere else
    }
}
```

```typescript
// Driving adapter - an HTTP controller plugs the web into the driving port
class PlaceOrderController {
  constructor(private readonly placeOrder: PlaceOrder) {}   // the use case

  async handle(req: HttpRequest): Promise<HttpResponse> {
    const command = PlaceOrderCommand.fromHttp(req.body);   // translate at the edge
    const orderId = await this.placeOrder.execute(command);
    return HttpResponse.created({ id: orderId.toString() });
  }
}
```

The controller's only job is **translation**: turn an HTTP request into a command, and a result into a response. No business rule ever lives in an adapter.

## Configurable Dependency: Wiring the Hexagon

The application never chooses its own adapters. A single **composition root** (the `Main` component in Clean Architecture) decides which adapter plugs into which port at startup. This is the only place that names both the port and the concrete adapter.

```php
// Composition root - the ONLY place that knows both sides.
$payments = $isTestRun
    ? new FakePaymentGateway()
    : new StripePaymentGateway($stripeClient);

$placeOrder = new PlaceOrder(
    orders:   new DoctrineOrderRepository($entityManager),
    payments: $payments,
);
```

Because wiring is external, switching a driven adapter (Stripe to Adyen, Postgres to an in-memory fake) is a one-line change in one file. Nothing inside the hexagon is touched, and no test needs the real service.

## Adding a Second Driving Adapter

The payoff of a driving port is that a new entry point is free. Once `PlaceOrder` exists as a use case, exposing it over the CLI as well as HTTP costs one thin adapter and zero domain changes:

```php
// A second driving adapter for the SAME use case - no logic duplicated.
final class PlaceOrderCommand extends Command
{
    public function __construct(private readonly PlaceOrder $placeOrder) { parent::__construct(); }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $orderId = ($this->placeOrder)(
            new PlaceOrderCommandDto($input->getArgument('customer'), $input->getArgument('sku'), 1)
        );
        $output->writeln("Order {$orderId} placed");
        return Command::SUCCESS;
    }
}
```

When the same rule must run from a web request, a queue consumer, and a nightly batch, hexagonal architecture is the difference between writing it once and writing it three times.

## Ports for Messages and Events

Ports are not only request/response. An **event** an aggregate publishes is a driven port (the app announces something happened); the messaging infrastructure is the adapter that delivers it. An incoming message on a queue is a driving adapter that translates the payload into a command, exactly like the HTTP controller. Keep the domain event a plain object; let the adapter serialize it. See [[event-driven]] for the delivery patterns.

## Testing at the Port

The reason to build hexagonally is that you can drive the application from a test with fakes at every driven port:

```python
def test_place_order_charges_the_customer():
    payments = FakePaymentGateway()          # test adapter at a driven port
    orders = InMemoryOrderRepository()        # test adapter at a driven port
    place_order = PlaceOrder(orders, payments)

    place_order(PlaceOrderCommand(customer_id="c1", sku="BOOK", quantity=2))

    assert payments.was_charged(Money.euros(30))
    assert orders.count() == 1
```

No web server, no database, no network. This is the same "testable" property Clean Architecture promises, obtained by substituting adapters rather than by mocking framework internals. Prefer a **fake** (a real, simple implementation of the port) over a mock: it exercises the contract instead of the call sequence.

## Correspondence: Hexagonal to Clean Architecture to This Plugin

The vocabularies map cleanly onto one another and onto the pack layout:

| Hexagonal | Clean Architecture | This plugin's layer |
|-----------|--------------------|---------------------|
| Application core (domain) | Entities | `Domain/` |
| Application core (use cases) | Use Cases | `Application/` |
| Driving port | Use Case input port | `Application/UseCase` interface |
| Driven port | Use Case output / data-access port | `Application/Port` or `Domain` repository interface |
| Driving adapter | Controller / Presenter | `Presentation/` |
| Driven adapter | Gateway / Repository impl | `Infrastructure/` |

A repository interface in `Domain/` (the classic DDD `OrderRepositoryInterface`) **is** a driven port; its Doctrine implementation in `Infrastructure/` **is** a driven adapter.

## Common Mistakes

| Mistake | Why it breaks the hexagon | Fix |
|---------|---------------------------|-----|
| Port defined in `Infrastructure/` | The app now depends on the adapter's package | Move the interface inside the hexagon |
| Business logic inside a controller | A driving adapter holds policy | Push the rule into a use case (controller-leak signal) |
| Use case depends on a concrete Doctrine repository | The hexagon depends on a driven adapter | Depend on the port; inject the adapter |
| DTO leaking framework types across a port | Outer format entered the hexagon | Translate to a plain command/response at the edge |
| One "port" with 20 methods | Fat interface, adapters implement unused methods | Segregate ports by conversation (ISP) |
| Mocking the adapter in tests | Couples the test to the driver's internals | Substitute a fake at the port instead |
| The application constructs its own adapters | The hexagon depends on concrete infrastructure | Wire adapters in the composition root only |

## When Hexagonal Is Worth It

Ports & Adapters is not free: every port is an interface and an extra indirection. Apply it where the value is real:

- **Yes**: swappable infrastructure (payment providers, storage), high-value domain logic that must be unit-tested fast, systems driven from several entry points (HTTP + CLI + queue).
- **Not yet**: a thin CRUD screen with no rules, a throwaway script, a prototype whose domain is still being discovered. Introduce ports when a second adapter or a testability need actually appears.

## Naming Ports by Conversation

Name a port after the conversation, not the technology behind it. `PaymentGateway`, not `StripeClient`; `Clock`, not `SystemTime`; `OrderRepository`, not `DoctrineOrders`. The name should survive replacing the adapter.

```php
// The port speaks the domain's language; the adapter's tech never leaks into the name.
interface NotificationSender { public function send(Notification $n): void; }  // port
final class TwilioSmsSender implements NotificationSender { /* ... */ }        // adapter
final class SendGridEmailSender implements NotificationSender { /* ... */ }    // adapter
```

## Rule

> Every conversation the application has with the outside world is a port it owns, implemented by an adapter it never names. Test by swapping adapters, not by mocking internals.

## Related

- [[clean-architecture]] - the same law drawn as concentric circles, with the Dependency Rule stated formally.
- [[principles]] - DIP is the mechanism that makes every port work; ISP keeps ports thin.
- [[ddd/ddd-domain-design]] - repository interfaces as driven ports; aggregates as the entities inside the hexagon.
- [[patterns]] - Adapter, Strategy, and Facade recur at the port boundary.
