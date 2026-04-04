# Symfony Messenger Patterns

## Architecture

Messages are plain data objects. Handlers contain logic via type-hinted `__invoke()`.

```php
// Message: data only, no behavior
final class SendInvoice
{
    public function __construct(
        public readonly int $orderId,
    ) {}
}

// Handler: business logic
#[AsMessageHandler]
final class SendInvoiceHandler
{
    public function __invoke(SendInvoice $message): void
    {
        // Process
    }
}
```

## Critical Rules

### 1. Pass IDs, Not Entities

```php
// GOOD: serializable, no Doctrine coupling
final class NewUserWelcomeEmail
{
    public function __construct(public readonly int $userId) {}
}

// BAD: Doctrine proxy serialization issues
final class NewUserWelcomeEmail
{
    public function __construct(public readonly User $user) {}
}
```

### 2. Idempotent Handlers

Messages can be delivered multiple times. Derive idempotency keys from business events.

```php
final class ProcessPayment
{
    public function __construct(
        public readonly int $orderId,
        public readonly string $idempotencyKey, // From business event, not random UUID
    ) {}
}
```

### 3. Message Versioning

```php
// Add optional properties with defaults for backward compatibility
final class SendInvoice
{
    public function __construct(
        public readonly int $orderId,
        public readonly ?string $locale = null, // Added in v2
    ) {}
}
```

## Async Configuration

```yaml
framework:
    messenger:
        failure_transport: failed
        transports:
            async: '%env(MESSENGER_TRANSPORT_DSN)%'
            failed: 'doctrine://default?queue_name=failed'
        routing:
            'App\Message\SendInvoice': async
```

## Retry Strategy

```yaml
retry_strategy:
    max_retries: 3
    delay: 1000
    multiplier: 2       # Exponential backoff
    max_delay: 10000
    jitter: 0.1          # Prevent thundering herd
```

Use `UnrecoverableMessageHandlingException` for permanent failures (no retry).
Use `RecoverableMessageHandlingException` to force retry.

## Production

- **Process manager** (Supervisor/systemd) to keep workers alive
- **Limits**: `--time-limit=3600 --memory-limit=128M --limit=10`
- **Graceful shutdown**: `messenger:stop-workers` on deploy
- **Stateless workers**: implement `ResetInterface` for services with state

## Transport Selection

| Transport | When |
|-----------|------|
| Doctrine | Simple setup, small volume |
| Redis Streams | Fast, distributed |
| AMQP (RabbitMQ) | Complex routing, enterprise |
| sync:// | Dev/test, synchronous processing |

## Anti-Patterns

- Passing Doctrine entities in messages
- Random UUIDs as idempotency keys
- Long-running handlers without timeouts
- Stateful services without `ResetInterface`
- No failure transport (messages silently lost)
- Single transport for mixed priorities
- Workers without `--limit` or process manager
