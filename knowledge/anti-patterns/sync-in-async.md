# Anti-Pattern: Sync Expectations in Async Handlers

Source: https://symfony.com/doc/current/messenger.html

## What it is

Treating `$bus->dispatch()` as a synchronous call that returns the handler's result.

## Why it's wrong

`MessageBusInterface::dispatch()` always returns an `Envelope`, not the handler's return value. When a transport is configured, the handler runs in a worker process — `dispatch()` returns immediately with no result. Attempting to read the handler output from `dispatch()` silently fails or causes errors.

## The Anti-Pattern

```php
// WRONG — dispatch() does not return handler output
$response = $bus->dispatch(new CreateOrderCommand($data));
return new JsonResponse(['orderId' => $response->id]); // Fatal: Envelope has no ->id
```

## The Correct Pattern

For async use cases, the controller must accept eventual consistency:

```php
// CORRECT — fire and return 202 Accepted
$bus->dispatch(new CreateOrderCommand($data));
return new JsonResponse([], Response::HTTP_ACCEPTED);
```

For sync use cases that need a return value, use a **Query bus** (sync transport) and retrieve results via a repository, not via dispatch return:

```php
// CORRECT — query via repository after synchronous dispatch
$bus->dispatch(new CreateOrderCommand($data));
$order = $this->orderRepository->findLastByUser($userId);
return new JsonResponse(['orderId' => $order->id()->toString()]);
```

Or use a dedicated sync transport:

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        transports:
            sync: 'sync://'
        routing:
            'App\Application\Query\*': sync
            'App\Application\UseCase\*': async
```

## Signals to detect this

- `$bus->dispatch(...)->getMessage()->someProperty`
- Handler method has non-void return type AND is routed to async transport
- Controller expects handler result immediately after dispatch
