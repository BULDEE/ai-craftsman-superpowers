# Design Patterns

> Reference: [refactoring.guru/design-patterns](https://refactoring.guru/design-patterns)

## Creational Patterns

### Factory Method

> Create objects without specifying exact class.

```php
interface NotificationFactory
{
    public function create(string $type): Notification;
}

final class NotificationFactoryImpl implements NotificationFactory
{
    public function create(string $type): Notification
    {
        return match($type) {
            'email' => new EmailNotification(),
            'sms' => new SmsNotification(),
            'push' => new PushNotification(),
            default => throw new InvalidNotificationType($type),
        };
    }
}
```

### Builder

> Construct complex objects step by step.

```php
final class QueryBuilder
{
    private array $select = [];
    private ?string $from = null;
    private array $where = [];

    public function select(string ...$columns): self
    {
        $this->select = $columns;
        return $this;
    }

    public function from(string $table): self
    {
        $this->from = $table;
        return $this;
    }

    public function where(string $condition): self
    {
        $this->where[] = $condition;
        return $this;
    }

    public function build(): Query
    {
        return new Query($this->select, $this->from, $this->where);
    }
}

// Usage
$query = (new QueryBuilder())
    ->select('id', 'name')
    ->from('users')
    ->where('active = true')
    ->build();
```

## Structural Patterns

### Adapter

> Convert interface of a class into another interface clients expect.

```php
interface PaymentGateway
{
    public function charge(Money $amount, Card $card): PaymentResult;
}

// Third-party SDK with different interface
final class StripeAdapter implements PaymentGateway
{
    public function __construct(private StripeClient $stripe) { }

    public function charge(Money $amount, Card $card): PaymentResult
    {
        $stripeResult = $this->stripe->charges->create([
            'amount' => $amount->cents(),
            'currency' => $amount->currency(),
            'source' => $card->token(),
        ]);

        return PaymentResult::fromStripe($stripeResult);
    }
}
```

### Decorator

> Add behavior to objects dynamically.

```php
interface Logger
{
    public function log(string $message): void;
}

final class FileLogger implements Logger
{
    public function log(string $message): void
    {
        file_put_contents('app.log', $message . PHP_EOL, FILE_APPEND);
    }
}

final class TimestampDecorator implements Logger
{
    public function __construct(private Logger $inner) { }

    public function log(string $message): void
    {
        $this->inner->log('[' . date('Y-m-d H:i:s') . '] ' . $message);
    }
}

// Usage
$logger = new TimestampDecorator(new FileLogger());
```

## Behavioral Patterns

### Strategy

> Define family of algorithms, encapsulate each one.

```php
interface PricingStrategy
{
    public function calculate(Order $order): Money;
}

final class RegularPricing implements PricingStrategy
{
    public function calculate(Order $order): Money
    {
        return $order->subtotal();
    }
}

final class PremiumPricing implements PricingStrategy
{
    public function calculate(Order $order): Money
    {
        return $order->subtotal()->multiply(0.9); // 10% discount
    }
}

final class OrderService
{
    public function __construct(private PricingStrategy $pricing) { }

    public function calculateTotal(Order $order): Money
    {
        return $this->pricing->calculate($order);
    }
}
```

### Observer (Event-Driven)

> Notify dependents of state changes.

```php
interface DomainEventInterface
{
    public function occurredAt(): DateTimeImmutable;
}

final readonly class UserRegistered implements DomainEventInterface
{
    public function __construct(
        public UserId $userId,
        public Email $email,
        public DateTimeImmutable $occurredAt,
    ) { }
}

// Listener
final class SendWelcomeEmailListener
{
    public function __invoke(UserRegistered $event): void
    {
        $this->mailer->send(
            $event->email,
            'Welcome!',
            'welcome.html.twig'
        );
    }
}
```

### Command

> Encapsulate request as an object.

```php
final readonly class CreateUserCommand
{
    public function __construct(
        public string $email,
        public string $name,
        public string $password,
    ) { }
}

final class CreateUserHandler
{
    public function __construct(
        private UserRepositoryInterface $repository,
        private PasswordHasher $hasher,
    ) { }

    public function __invoke(CreateUserCommand $command): UserId
    {
        $user = User::create(
            Email::fromString($command->email),
            Name::fromString($command->name),
            $this->hasher->hash($command->password),
        );

        $this->repository->save($user);

        return $user->id();
    }
}
```

### State

> Allow object to alter behavior when internal state changes.

```php
interface OrderState
{
    public function confirm(Order $order): void;
    public function ship(Order $order): void;
    public function cancel(Order $order): void;
}

final class PendingState implements OrderState
{
    public function confirm(Order $order): void
    {
        $order->transitionTo(new ConfirmedState());
    }

    public function ship(Order $order): void
    {
        throw new InvalidTransition('Cannot ship pending order');
    }

    public function cancel(Order $order): void
    {
        $order->transitionTo(new CancelledState());
    }
}

final class ConfirmedState implements OrderState
{
    public function confirm(Order $order): void
    {
        throw new InvalidTransition('Already confirmed');
    }

    public function ship(Order $order): void
    {
        $order->transitionTo(new ShippedState());
    }

    public function cancel(Order $order): void
    {
        $order->transitionTo(new CancelledState());
    }
}
```

## Domain-Driven Design Patterns

### Repository

> Mediate between domain and data mapping layers.

```php
interface UserRepositoryInterface
{
    public function save(User $user): void;
    public function findById(UserId $id): ?User;
    public function findByEmail(Email $email): ?User;
}
```

### Specification

> Encapsulate business rules that can be combined.

```php
interface Specification
{
    public function isSatisfiedBy(object $candidate): bool;
}

final class ActiveUserSpecification implements Specification
{
    public function isSatisfiedBy(object $candidate): bool
    {
        return $candidate instanceof User && $candidate->isActive();
    }
}

final class PremiumUserSpecification implements Specification
{
    public function isSatisfiedBy(object $candidate): bool
    {
        return $candidate instanceof User && $candidate->isPremium();
    }
}

// Combine
$spec = new AndSpecification(
    new ActiveUserSpecification(),
    new PremiumUserSpecification(),
);
```

### Domain Event

> Capture something that happened in the domain.

```php
final readonly class OrderPlaced implements DomainEventInterface
{
    public function __construct(
        public OrderId $orderId,
        public CustomerId $customerId,
        public Money $total,
        public DateTimeImmutable $occurredAt,
    ) { }
}

// Entity raises events
final class Order
{
    private array $domainEvents = [];

    public static function place(CustomerId $customerId, array $items): self
    {
        $order = new self($customerId, $items);
        $order->raise(new OrderPlaced(
            $order->id,
            $customerId,
            $order->total(),
            new DateTimeImmutable(),
        ));
        return $order;
    }

    private function raise(DomainEventInterface $event): void
    {
        $this->domainEvents[] = $event;
    }

    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];
        return $events;
    }
}

## GoF Catalog Quick Reference

The patterns above are the ones you reach for most, shown in depth. The rest of the Gang of Four catalog, one line of intent plus the smell each one fixes:

| Pattern | Category | Intent | Smell it fixes |
|---------|----------|--------|----------------|
| Abstract Factory | Creational | Create families of related objects without naming concretes | `new` of related concretes scattered across the code |
| Singleton | Creational | One instance, global access (use sparingly - often an anti-pattern) | Uncontrolled duplication of a shared resource |
| Prototype | Creational | Clone objects without coupling to their concrete class | Complex re-construction of near-identical objects |
| Facade | Structural | A simple interface over a complex subsystem | Callers wiring up many collaborators themselves |
| Composite | Structural | Treat individual objects and trees uniformly | Type-checking to handle leaf vs. group |
| Proxy | Structural | A stand-in that controls access (lazy, cache, guard) | Access/caching logic mixed into the real object |
| Bridge | Structural | Split abstraction from implementation, vary independently | A class exploding along two orthogonal axes |
| Flyweight | Structural | Share common state across many objects | Memory blown by many near-identical objects |
| Template Method | Behavioral | Algorithm skeleton in a base, steps overridden | Duplicated algorithm with minor per-case differences |
| Chain of Responsibility | Behavioral | Pass a request along handlers until one handles it | A giant conditional dispatching to handlers |
| Iterator | Behavioral | Traverse a collection without exposing its shape | Callers depending on the internal structure |
| Mediator | Behavioral | Route object communication through one mediator | A web of direct object-to-object coupling |
| Memento | Behavioral | Capture and restore state without exposing internals | Undo/redo reaching into private fields |
| Visitor | Behavioral | Separate an operation from the objects it runs on | New operations forcing edits to every element class |

## Pattern Selection Guide

| Problem | Pattern |
|---------|---------|
| Create objects flexibly | Factory Method, Abstract Factory |
| Object construction is complex | Builder |
| Use an incompatible interface | Adapter |
| Add behavior dynamically | Decorator |
| Complex subsystem needs a simple API | Facade |
| Algorithm should be swappable | Strategy |
| Behavior depends on state | State |
| Decouple event producer/consumer | Observer |
| Undo/redo | Command + Memento |
| Processing pipeline | Chain of Responsibility |

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| God Object | One class does everything | Extract classes by responsibility (`GOD001`) - see [[anti-patterns/god-object]] |
| Spaghetti Code | No clear structure | Extract Method, Move Method - see [[refactoring-techniques]] |
| Golden Hammer | One pattern for everything | Choose the pattern by the problem |
| Premature Optimization | Optimizing before profiling | YAGNI; measure first |
| Cargo Cult | Patterns applied without understanding | Understand the WHY before the pattern |

## References

| Resource | Focus |
|----------|-------|
| [refactoring.guru/design-patterns](https://refactoring.guru/design-patterns) | Visual catalog with examples in multiple languages |
| [martinfowler.com/eaaCatalog](https://martinfowler.com/eaaCatalog/) | Patterns of Enterprise Application Architecture |

> "Each pattern describes a problem which occurs over and over again in our environment, and then describes the core of the solution to that problem." - Christopher Alexander
```
