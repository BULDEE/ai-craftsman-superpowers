# Anti-Pattern: Synchronous Work in Async Handlers

## Problem

Performing synchronous I/O (HTTP calls, file operations) directly inside Messenger handlers kills worker throughput and prevents independent retry per channel.

## Bad

```php
#[AsMessageHandler]
final class SendNotificationHandler
{
    public function __invoke(SendNotification $command): void
    {
        // BAD: synchronous HTTP call blocks the worker
        $this->httpClient->request('POST', 'https://api.slack.com/...', [...]);
        $this->httpClient->request('POST', 'https://api.sendgrid.com/...', [...]);
    }
}
```

## Good

```php
#[AsMessageHandler]
final class SendNotificationHandler
{
    public function __construct(
        private readonly MessageBusInterface $bus,
    ) {}

    public function __invoke(SendNotification $command): void
    {
        // GOOD: dispatch sub-messages for each channel
        $this->bus->dispatch(new SendSlackNotification($command->message));
        $this->bus->dispatch(new SendEmailNotification($command->message));
    }
}

#[AsMessageHandler]
final class SendSlackNotificationHandler
{
    public function __invoke(SendSlackNotification $command): void
    {
        // Each channel handled independently — can retry without affecting others
        $this->httpClient->request('POST', 'https://api.slack.com/...', [...]);
    }
}
```

## Why It Matters

- Messenger workers process one message at a time per worker process
- Synchronous I/O blocks the entire worker for its full duration
- A Slack API timeout (30s) blocks email delivery too
- Sub-messages allow independent retry policies and dead-letter queues per channel
- Worker scaling is much more effective when handlers are lightweight

## Rule

> Each handler should do one thing. Use sub-messages to fan out work across channels.
