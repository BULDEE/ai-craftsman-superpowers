<?php

declare(strict_types=1);

namespace App\Domain\Repository;

use App\Domain\Entity\User;
use App\Domain\ValueObject\Email;
use Symfony\Component\Uid\Uuid;

/**
 * CANONICAL REPOSITORY INTERFACE PATTERN
 *
 * Key characteristics:
 * - Interface in Domain layer
 * - Implementation in Infrastructure layer
 * - Uses domain types (not primitives)
 * - No query builder or ORM leakage
 * - Collection-oriented (pretend it's an in-memory collection)
 */
interface UserRepositoryInterface
{
    /**
     * Persist a user (insert or update)
     */
    public function save(User $user): void;

    /**
     * Find by identifier
     */
    public function findById(Uuid $id): ?User;

    /**
     * Find by unique field
     */
    public function findByEmail(Email $email): ?User;

    /**
     * Remove a user
     */
    public function remove(User $user): void;

    /**
     * Check existence without loading
     */
    public function existsByEmail(Email $email): bool;
}

// ============================================
// INFRASTRUCTURE IMPLEMENTATION
// ============================================

namespace App\Infrastructure\Persistence;

use App\Domain\Entity\User;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\Email;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Uid\Uuid;

/**
 * Doctrine implementation of UserRepository
 *
 * Note: This is in Infrastructure, not Domain
 */
final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $em,
    ) {
    }

    public function save(User $user): void
    {
        $this->em->persist($user);
        $this->em->flush();
    }

    public function findById(Uuid $id): ?User
    {
        return $this->em->find(User::class, $id);
    }

    public function findByEmail(Email $email): ?User
    {
        return $this->em->createQueryBuilder()
            ->select('u')
            ->from(User::class, 'u')
            ->where('u.email = :email')
            ->setParameter('email', $email->value())
            ->getQuery()
            ->getOneOrNullResult();
    }

    public function remove(User $user): void
    {
        $this->em->remove($user);
        $this->em->flush();
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->em->createQueryBuilder()
            ->select('1')
            ->from(User::class, 'u')
            ->where('u.email = :email')
            ->setParameter('email', $email->value())
            ->getQuery()
            ->getOneOrNullResult() !== null;
    }
}

// ============================================
// EXAMPLE: Repository with Specifications
// ============================================

interface OrderRepositoryInterface
{
    public function save(Order $order): void;

    public function findById(Uuid $id): ?Order;

    /**
     * Find using specification pattern
     *
     * @return Order[]
     */
    public function findMatching(OrderSpecification $spec): array;

    /**
     * Count matching specification
     */
    public function countMatching(OrderSpecification $spec): int;
}

/**
 * Specification pattern for complex queries
 */
interface OrderSpecification
{
    public function toQueryCriteria(): array;
}

final readonly class PendingOrdersForCustomer implements OrderSpecification
{
    public function __construct(
        private Uuid $customerId,
    ) {
    }

    public function toQueryCriteria(): array
    {
        return [
            'customerId' => $this->customerId,
            'status' => OrderStatus::PENDING,
        ];
    }
}

// Usage:
// $orders = $orderRepository->findMatching(
//     new PendingOrdersForCustomer($customerId)
// );
