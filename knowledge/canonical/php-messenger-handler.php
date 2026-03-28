<?php

/**
 * CANONICAL EXAMPLE: Symfony Messenger Handler (v1.0)
 *
 * This is THE reference for Messenger handlers following CQRS + DDD.
 *
 * Key characteristics:
 * - #[AsMessageHandler] attribute (MUST in Symfony 6.2+)
 * - final class (MUST)
 * - __invoke() method (MUST for single-message handlers)
 * - Domain objects created via factory methods
 * - Repository for persistence
 * - Domain events released and dispatched after save
 */

declare(strict_types=1);

namespace App\Application\UseCase\CreateUser;

use App\Domain\Entity\User;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\UserId;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Messenger\MessageBusInterface;

#[AsMessageHandler]
final class CreateUserHandler
{
    public function __construct(
        private readonly UserRepositoryInterface $repository,
        private readonly MessageBusInterface $eventBus,
    ) {}

    public function __invoke(CreateUserCommand $command): void
    {
        $user = User::create(
            UserId::generate(),
            Email::fromString($command->email),
        );

        $this->repository->save($user);

        foreach ($user->releaseEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }
}
