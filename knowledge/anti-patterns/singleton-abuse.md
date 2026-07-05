# Anti-Pattern: Singleton Abuse

## What It Is

Reaching for the Singleton pattern (a class with one global instance and a static access point) as the default way to share objects. It looks convenient, so configuration, database connections, loggers, and caches all become globally reachable statics.

## Why It's Bad

- It is **global mutable state** in disguise: any code can read or change it, so behavior depends on hidden order.
- It **breaks the Dependency Inversion Principle**: high-level code names a concrete singleton instead of an injected abstraction (see [[principles]]).
- It **destroys testability**: you cannot substitute a fake, and one test's mutation leaks into the next (the same trap as stubbing a global, see [[testing-strategy]]).
- It **hides dependencies**: a class that calls `Logger::instance()` looks dependency-free but is not.

## Example

### BAD: Global singleton, hidden dependency

```php
final class Logger
{
    private static ?Logger $instance = null;
    public static function instance(): self
    {
        return self::$instance ??= new self();
    }
    public function log(string $m): void { /* ... */ }
}

final class PlaceOrder
{
    public function __invoke(): void
    {
        Logger::instance()->log('placing order'); // hidden global dependency, untestable
    }
}
```

### GOOD: Inject the abstraction

```php
interface Logger { public function log(string $message): void; }

final readonly class PlaceOrder
{
    public function __construct(private Logger $logger) {} // explicit, swappable

    public function __invoke(): void
    {
        $this->logger->log('placing order'); // tests inject a fake logger
    }
}
```

The composition root decides there is exactly one logger and wires it in. Uniqueness is a **wiring** concern (the DI container's job), not a property the class enforces on itself.

## When a Single Instance Is Legitimate

Wanting one instance is fine; enforcing it with the Singleton pattern is the problem. Achieve single-instance through the container's scope instead:

```php
// The container creates one Logger and injects it everywhere. Still testable,
// still an abstraction, no global static access point.
$logger = new FileLogger($path);
$placeOrder = new PlaceOrder($logger);
```

Truly stateless, side-effect-free helpers (a pure math utility) can be static without harm, because there is no shared state to leak.

## How to Detect

1. `ClassName::instance()` / `getInstance()` static access points.
2. Static mutable properties holding shared state.
3. Classes that look dependency-free but call singletons internally.
4. Tests that must reset global state between runs.

## How to Fix

1. Turn the singleton into a normal class implementing an interface.
2. Inject that interface via the constructor (Dependency Inversion).
3. Let the composition root create the single instance and share it.
4. Remove the static accessor; update callers to receive the dependency.

## Rule

> "One instance" is a job for your wiring, not for a global static. Inject abstractions; let the composition root decide multiplicity.
