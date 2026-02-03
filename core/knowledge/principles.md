# Software Principles

## SOLID

### Single Responsibility Principle (SRP)

> A class should have only one reason to change.

```php
// BAD: Multiple responsibilities
final class UserService
{
    public function createUser(): void { }
    public function sendWelcomeEmail(): void { }  // Email is different responsibility
    public function generateReport(): void { }    // Reporting is different responsibility
}

// GOOD: Single responsibility
final class UserService
{
    public function createUser(): void { }
}

final class WelcomeEmailSender
{
    public function send(User $user): void { }
}
```

### Open/Closed Principle (OCP)

> Open for extension, closed for modification.

```php
// BAD: Modify existing code for new types
final class DiscountCalculator
{
    public function calculate(Order $order): Money
    {
        if ($order->type() === 'regular') { ... }
        if ($order->type() === 'premium') { ... }
        // Must modify this class for each new type
    }
}

// GOOD: Extend without modification
interface DiscountStrategy
{
    public function calculate(Order $order): Money;
}

final class RegularDiscount implements DiscountStrategy { }
final class PremiumDiscount implements DiscountStrategy { }
```

### Liskov Substitution Principle (LSP)

> Subtypes must be substitutable for their base types.

```php
// BAD: Subtype changes behavior
class Rectangle
{
    public function setWidth(int $w): void { $this->width = $w; }
    public function setHeight(int $h): void { $this->height = $h; }
}

class Square extends Rectangle
{
    public function setWidth(int $w): void
    {
        $this->width = $w;
        $this->height = $w;  // Violates LSP - unexpected behavior
    }
}

// GOOD: Don't use inheritance for this
interface Shape
{
    public function area(): int;
}

final class Rectangle implements Shape { }
final class Square implements Shape { }
```

### Interface Segregation Principle (ISP)

> Clients should not depend on interfaces they don't use.

```php
// BAD: Fat interface
interface Worker
{
    public function work(): void;
    public function eat(): void;
    public function sleep(): void;
}

// GOOD: Segregated interfaces
interface Workable
{
    public function work(): void;
}

interface Feedable
{
    public function eat(): void;
}
```

### Dependency Inversion Principle (DIP)

> Depend on abstractions, not concretions.

```php
// BAD: Depends on concrete implementation
final class OrderService
{
    public function __construct(
        private MySqlOrderRepository $repository  // Concrete!
    ) { }
}

// GOOD: Depends on abstraction
final class OrderService
{
    public function __construct(
        private OrderRepositoryInterface $repository  // Abstract!
    ) { }
}
```

## KISS (Keep It Simple, Stupid)

> The simplest solution is usually the best.

```php
// BAD: Over-engineered
final class StringUtils
{
    public function reverse(string $s): string
    {
        $factory = new StringProcessorFactory();
        $processor = $factory->create('reverse');
        $pipeline = new ProcessingPipeline([$processor]);
        return $pipeline->execute($s);
    }
}

// GOOD: Simple
final class StringUtils
{
    public function reverse(string $s): string
    {
        return strrev($s);
    }
}
```

## DRY (Don't Repeat Yourself)

> Every piece of knowledge must have a single, unambiguous representation.

```php
// BAD: Duplication
final class UserValidator
{
    public function validateEmail(string $email): bool
    {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }
}

final class ContactValidator
{
    public function validateEmail(string $email): bool
    {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }
}

// GOOD: Single source of truth
final class Email
{
    public static function fromString(string $value): self
    {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidEmailException($value);
        }
        return new self($value);
    }
}
```

## YAGNI (You Aren't Gonna Need It)

> Don't add functionality until it's necessary.

```php
// BAD: Speculative generality
final class UserService
{
    public function __construct(
        private UserRepositoryInterface $repository,
        private ?CacheInterface $cache = null,           // "Might need caching"
        private ?LoggerInterface $logger = null,         // "Might need logging"
        private ?MetricsInterface $metrics = null,       // "Might need metrics"
        private array $options = []                      // "Might need options"
    ) { }
}

// GOOD: Only what's needed now
final class UserService
{
    public function __construct(
        private UserRepositoryInterface $repository,
    ) { }
}
```

## Tell, Don't Ask

> Tell objects what to do, don't ask for their state.

```php
// BAD: Ask then act
if ($order->status() === OrderStatus::PENDING) {
    $order->setStatus(OrderStatus::CONFIRMED);
    $order->setConfirmedAt(new DateTimeImmutable());
}

// GOOD: Tell
$order->confirm();
```

## Law of Demeter

> Only talk to your immediate friends.

```php
// BAD: Train wreck
$street = $order->customer()->address()->street();

// GOOD: Ask the object directly
$street = $order->deliveryStreet();
```

## Fail Fast

> Detect and report errors as early as possible.

```php
// BAD: Silent failure
public function process(?User $user): void
{
    if ($user === null) {
        return;  // Silently ignores problem
    }
    // ...
}

// GOOD: Fail fast
public function process(User $user): void  // Type forces non-null
{
    // If null somehow passed, it fails immediately
}
```
