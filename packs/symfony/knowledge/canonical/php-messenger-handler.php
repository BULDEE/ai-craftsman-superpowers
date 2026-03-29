<?php

/**
 * CANONICAL EXAMPLE: Symfony Messenger Handler Pattern (v1.0)
 *
 * This is THE reference for async message handlers.
 * Source: https://symfony.com/doc/current/messenger.html
 *
 * Key characteristics:
 * - #[AsMessageHandler] attribute (MUST) — replaces manual services.yaml tag
 * - final readonly class (MUST)
 * - Single __invoke() method typed to the message (MUST)
 * - No return value for async handlers (SHOULD) — dispatch() returns Envelope, not handler result
 * - MessageBusInterface for dispatching (MUST)
 */

declare(strict_types=1);

namespace App\Application\UseCase\SendNotification;

use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\UserId;
use App\Infrastructure\Notification\NotificationSenderInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

// ============================================================
// CANONICAL EXAMPLE: Message (Command/Event) (v1.0)
// ============================================================

final readonly class SendNotificationCommand
{
    public function __construct(
        public string $userId,
        public string $message,
    ) {}
}

// ============================================================
// CANONICAL EXAMPLE: Message Handler (v1.0)
// ============================================================

#[AsMessageHandler]
final readonly class SendNotificationHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
        private NotificationSenderInterface $notificationSender,
    ) {}

    public function __invoke(SendNotificationCommand $command): void
    {
        $userId = UserId::fromString($command->userId);

        $user = $this->userRepository->findById($userId)
            ?? throw new UserNotFoundException($userId);

        $this->notificationSender->send($user->email(), $command->message);
    }
}

// ============================================================
// CANONICAL EXAMPLE: Dispatching from Controller (v1.0)
// ============================================================
// dispatch() returns Envelope — NOT the handler's return value.
// For async transports, the handler runs in a worker process.
//
// use Symfony\Component\Messenger\MessageBusInterface;
//
// public function notify(
//     string $userId,
//     MessageBusInterface $bus,
// ): Response {
//     $bus->dispatch(new SendNotificationCommand($userId, 'Welcome!'));
//     return new JsonResponse([], Response::HTTP_ACCEPTED);
// }

// ============================================================
// CANONICAL EXAMPLE: Messenger YAML config (v1.0)
// ============================================================
// config/packages/messenger.yaml
//
// framework:
//     messenger:
//         transports:
//             async:
//                 dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
//                 retry_strategy:
//                     max_retries: 3
//                     delay: 1000        # ms before first retry
//                     multiplier: 2      # 1s, 2s, 4s, ...
//                     max_delay: 0       # 0 = no cap
//                     jitter: 0.1        # randomness to prevent thundering herd
//         routing:
//             # Wildcard MUST be at the END of the namespace prefix
//             'App\Application\UseCase\*': async
