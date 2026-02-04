<?php

/**
 * CANONICAL EXAMPLE: Repository Pattern (v1.0)
 *
 * Key characteristics:
 * - Interface in Domain layer (MUST)
 * - Implementation in Infrastructure layer (MUST)
 * - Collection-like semantics (SHOULD)
 * - Works with Aggregates, not raw data (MUST)
 * - No query logic in Domain interface (MUST)
 */

declare(strict_types=1);

// ============================================================
// Domain Layer: Repository Interface
// ============================================================

namespace App\Domain\Repository;

use App\Domain\Entity\User;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\UserId;

interface UserRepositoryInterface
{
    public function save(User $user): void;

    public function findById(UserId $id): ?User;

    public function findByEmail(Email $email): ?User;

    public function existsByEmail(Email $email): bool;

    public function remove(User $user): void;
}

// ============================================================
// Infrastructure Layer: Doctrine Implementation
// ============================================================

namespace App\Infrastructure\Persistence\Doctrine;

use App\Domain\Entity\User;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\UserId;
use Doctrine\ORM\EntityManagerInterface;

final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $em,
    ) {}

    public function save(User $user): void
    {
        $this->em->persist($user);
        $this->em->flush();
    }

    public function findById(UserId $id): ?User
    {
        return $this->em->find(User::class, $id->value);
    }

    public function findByEmail(Email $email): ?User
    {
        return $this->em->createQueryBuilder()
            ->select('u')
            ->from(User::class, 'u')
            ->where('u.email.value = :email')
            ->setParameter('email', $email->value)
            ->getQuery()
            ->getOneOrNullResult();
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->em->createQueryBuilder()
            ->select('1')
            ->from(User::class, 'u')
            ->where('u.email.value = :email')
            ->setParameter('email', $email->value)
            ->getQuery()
            ->getOneOrNullResult() !== null;
    }

    public function remove(User $user): void
    {
        $this->em->remove($user);
        $this->em->flush();
    }
}

// ============================================================
// CANONICAL EXAMPLE: Tenant-Aware Repository (v1.0)
// ============================================================

namespace App\Infrastructure\Persistence\Doctrine;

use App\Domain\Entity\Lead;
use App\Domain\Repository\LeadRepositoryInterface;
use App\Domain\ValueObject\LeadId;
use App\Domain\ValueObject\TenantId;
use App\Shared\Infrastructure\Security\TenantContext;
use Doctrine\ORM\EntityManagerInterface;

final readonly class DoctrineLeadRepository implements LeadRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $em,
        private TenantContext $tenantContext,
    ) {}

    public function save(Lead $lead): void
    {
        $this->ensureTenantMatch($lead->tenantId());
        $this->em->persist($lead);
        $this->em->flush();
    }

    public function findById(LeadId $id): ?Lead
    {
        $lead = $this->em->find(Lead::class, $id->value);

        if ($lead !== null) {
            $this->ensureTenantMatch($lead->tenantId());
        }

        return $lead;
    }

    private function ensureTenantMatch(TenantId $tenantId): void
    {
        if (!$tenantId->equals($this->tenantContext->current())) {
            throw new TenantMismatchException();
        }
    }
}
