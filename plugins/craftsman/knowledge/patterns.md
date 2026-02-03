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

## References

| Resource | Focus |
|----------|-------|
| [refactoring.guru/design-patterns](https://refactoring.guru/design-patterns) | Visual catalog with examples in multiple languages |
| [martinfowler.com/eaaCatalog](https://martinfowler.com/eaaCatalog/) | Patterns of Enterprise Application Architecture |

> "Each pattern describes a problem which occurs over and over again in our environment, and then describes the core of the solution to that problem." — Christopher Alexander
```
