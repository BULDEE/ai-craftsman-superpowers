<?php

declare(strict_types=1);

namespace App\Application\UseCase\CreateUser;

use App\Domain\Entity\User;
use App\Domain\Exception\EmailAlreadyExistsException;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\HashedPassword;
use Symfony\Component\Uid\Uuid;

/**
 * CANONICAL USE CASE PATTERN
 *
 * Key characteristics:
 * - Single responsibility (one action)
 * - Immutable Command/Query DTO
 * - Handler with __invoke
 * - Depends on domain interfaces, not implementations
 * - Orchestrates domain logic, doesn't contain it
 */

// ============================================
// COMMAND DTO (Input)
// ============================================

final readonly class CreateUserCommand
{
    public function __construct(
        public string $email,
        public string $password,
        public string $name,
    ) {
    }
}

// ============================================
// HANDLER
// ============================================

final readonly class CreateUserHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
        private PasswordHasherInterface $passwordHasher,
    ) {
    }

    /**
     * @throws EmailAlreadyExistsException
     */
    public function __invoke(CreateUserCommand $command): Uuid
    {
        // 1. Convert primitives to Value Objects
        $email = Email::fromString($command->email);

        // 2. Business rule: email must be unique
        if ($this->userRepository->existsByEmail($email)) {
            throw new EmailAlreadyExistsException($email);
        }

        // 3. Hash password (infrastructure concern, but needed here)
        $hashedPassword = $this->passwordHasher->hash($command->password);

        // 4. Create domain entity (domain logic is IN the entity)
        $user = User::create($email, $hashedPassword);

        // 5. Persist
        $this->userRepository->save($user);

        // 6. Return identifier
        return $user->id();
    }
}

// ============================================
// QUERY EXAMPLE
// ============================================

final readonly class GetUserProfileQuery
{
    public function __construct(
        public string $userId,
    ) {
    }
}

final readonly class GetUserProfileHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(GetUserProfileQuery $query): ?UserProfileResponse
    {
        $user = $this->userRepository->findById(
            Uuid::fromString($query->userId)
        );

        if ($user === null) {
            return null;
        }

        return UserProfileResponse::fromUser($user);
    }
}

// ============================================
// RESPONSE DTO (Output)
// ============================================

final readonly class UserProfileResponse
{
    public function __construct(
        public string $id,
        public string $email,
        public string $name,
        public bool $isVerified,
        public string $createdAt,
    ) {
    }

    public static function fromUser(User $user): self
    {
        return new self(
            id: $user->id()->toString(),
            email: $user->email()->value(),
            name: $user->name()->value(),
            isVerified: $user->isVerified(),
            createdAt: $user->createdAt()->format('c'),
        );
    }
}

// ============================================
// USE CASE WITH TRANSACTION
// ============================================

final readonly class TransferMoneyHandler
{
    public function __construct(
        private AccountRepositoryInterface $accountRepository,
        private TransactionManagerInterface $transactionManager,
    ) {
    }

    public function __invoke(TransferMoneyCommand $command): void
    {
        $this->transactionManager->transactional(function () use ($command) {
            $from = $this->accountRepository->findById($command->fromAccountId);
            $to = $this->accountRepository->findById($command->toAccountId);

            if ($from === null || $to === null) {
                throw new AccountNotFoundException();
            }

            $amount = Money::create($command->amountCents, $command->currency);

            // Domain logic is in entities
            $from->withdraw($amount);
            $to->deposit($amount);

            $this->accountRepository->save($from);
            $this->accountRepository->save($to);
        });
    }
}

// ============================================
// INTERFACE FOR TRANSACTION MANAGER
// ============================================

interface TransactionManagerInterface
{
    /**
     * @template T
     * @param callable(): T $operation
     * @return T
     */
    public function transactional(callable $operation): mixed;
}
