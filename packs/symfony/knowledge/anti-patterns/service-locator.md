# Anti-Pattern: Service Locator

## Problem

Using `ContainerInterface::get()` to pull services at runtime instead of proper constructor injection. Hides dependencies, breaks static analysis, makes testing painful.

## Bad

```php
final class OrderHandler
{
    public function __construct(private ContainerInterface $container) {}

    public function __invoke(CreateOrder $command): void
    {
        $repo = $this->container->get(OrderRepository::class);
        $mailer = $this->container->get(MailerInterface::class);
        // ...
    }
}
```

## Good

```php
final class OrderHandler
{
    public function __construct(
        private OrderRepository $repository,
        private MailerInterface $mailer,
    ) {}

    public function __invoke(CreateOrder $command): void
    {
        // Dependencies are explicit, typed, and testable
    }
}
```

## Why It Matters

- Dependencies are hidden: impossible to know what a class needs without reading the body
- PHPStan/Psalm cannot verify types returned by `$container->get()`
- Tests require a full container or complex mocking instead of simple constructor args
- Symfony autowiring makes constructor injection trivial

## Detection

Grep for `ContainerInterface` or `->get(` in domain/application layer classes. These should only appear in infrastructure CompilerPass or factory code.
