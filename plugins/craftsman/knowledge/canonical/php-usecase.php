<?php

/**
 * CANONICAL EXAMPLE: UseCase Pattern (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - final readonly class (MUST)
 * - Single public method __invoke() or execute() (MUST)
 * - Constructor injection of dependencies (MUST)
 * - Input DTO as parameter (SHOULD)
 * - Output DTO as return (SHOULD)
 * - Transaction handling at this layer (SHOULD)
 * - Domain logic delegated to entities (MUST)
 */

declare(strict_types=1);

namespace App\Application\UseCase\User;

use App\Application\DTO\User\CreateUserInput;
use App\Application\DTO\User\CreateUserOutput;
use App\Domain\Entity\User;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\Email;
use App\Shared\Domain\Clock\Clock;
use App\Shared\Domain\Transaction\TransactionManagerInterface;

final readonly class CreateUserUseCase
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
        private TransactionManagerInterface $transactionManager,
        private Clock $clock,
    ) {}

    public function __invoke(CreateUserInput $input): CreateUserOutput
    {
        $email = Email::create($input->email);

        $this->ensureEmailNotTaken($email);

        return $this->transactionManager->execute(function () use ($email): CreateUserOutput {
            $user = User::create($email, $this->clock);

            $this->userRepository->save($user);

            return new CreateUserOutput(
                id: $user->id()->value,
                email: $user->email()->value,
            );
        });
    }

    private function ensureEmailNotTaken(Email $email): void
    {
        if ($this->userRepository->existsByEmail($email)) {
            throw new EmailAlreadyTakenException($email);
        }
    }
}

// ============================================================
// CANONICAL EXAMPLE: Input DTO (v1.0)
// ============================================================

final readonly class CreateUserInput
{
    public function __construct(
        public string $email,
    ) {}
}

// ============================================================
// CANONICAL EXAMPLE: Output DTO (v1.0)
// ============================================================

final readonly class CreateUserOutput
{
    public function __construct(
        public string $id,
        public string $email,
    ) {}
}

// ============================================================
// CANONICAL EXAMPLE: Query UseCase (v1.0)
// ============================================================

final readonly class GetUserByIdUseCase
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {}

    public function __invoke(string $userId): UserOutput
    {
        $id = UserId::fromString($userId);

        $user = $this->userRepository->findById($id)
            ?? throw new UserNotFoundException($id);

        return UserOutput::fromEntity($user);
    }
}
