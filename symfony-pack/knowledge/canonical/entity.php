<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\DomainEventInterface;
use App\Domain\Event\UserCreatedEvent;
use App\Domain\Event\UserVerifiedEvent;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\HashedPassword;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

/**
 * CANONICAL ENTITY PATTERN
 *
 * Key characteristics:
 * - NOT final (Doctrine needs proxies for lazy loading)
 * - private constructor + static factory
 * - no setters, only behavior methods
 * - domain events for state changes
 * - value objects for typed fields
 * - Attributes for mapping (pragmatic DX over purity)
 *
 * WHY NO FINAL: Doctrine creates proxy classes that extend entities
 * for lazy loading. `final` breaks this. Pragmatism > dogmatism.
 */
#[ORM\Entity]
#[ORM\Table(name: 'users')]
class User
{
    /** @var array<DomainEventInterface> */
    private array $domainEvents = [];

    private function __construct(
        private readonly Uuid $id,
        private Email $email,
        private HashedPassword $password,
        private bool $isVerified,
        private readonly DateTimeImmutable $createdAt,
        private ?DateTimeImmutable $updatedAt = null,
        private ?DateTimeImmutable $verifiedAt = null,
    ) {
    }

    /**
     * Static factory - the ONLY way to create an instance
     */
    public static function create(Email $email, HashedPassword $password): self
    {
        $user = new self(
            id: Uuid::v7(),
            email: $email,
            password: $password,
            isVerified: false,
            createdAt: new DateTimeImmutable(),
        );

        $user->raise(new UserCreatedEvent(
            userId: $user->id,
            email: $user->email,
            occurredAt: $user->createdAt,
        ));

        return $user;
    }

    // ========================================
    // GETTERS (readonly access)
    // ========================================

    public function id(): Uuid
    {
        return $this->id;
    }

    public function email(): Email
    {
        return $this->email;
    }

    public function isVerified(): bool
    {
        return $this->isVerified;
    }

    public function createdAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    // ========================================
    // BEHAVIOR METHODS (not setters!)
    // ========================================

    /**
     * Behavior method with:
     * - Guard clause (validation)
     * - State change
     * - Domain event
     */
    public function verify(): void
    {
        if ($this->isVerified) {
            throw new UserAlreadyVerifiedException($this->id);
        }

        $this->isVerified = true;
        $this->verifiedAt = new DateTimeImmutable();
        $this->touch();

        $this->raise(new UserVerifiedEvent(
            userId: $this->id,
            occurredAt: $this->verifiedAt,
        ));
    }

    /**
     * Another behavior method
     */
    public function changeEmail(Email $newEmail): void
    {
        if ($this->email->equals($newEmail)) {
            return; // No change needed
        }

        $oldEmail = $this->email;
        $this->email = $newEmail;
        $this->isVerified = false; // Must re-verify
        $this->touch();

        $this->raise(new UserEmailChangedEvent(
            userId: $this->id,
            oldEmail: $oldEmail,
            newEmail: $newEmail,
            occurredAt: new DateTimeImmutable(),
        ));
    }

    /**
     * Password change - note we don't expose the password
     */
    public function changePassword(HashedPassword $newPassword): void
    {
        $this->password = $newPassword;
        $this->touch();
    }

    /**
     * Check password without exposing it
     */
    public function passwordMatches(HashedPassword $candidate): bool
    {
        return $this->password->equals($candidate);
    }

    // ========================================
    // DOMAIN EVENTS
    // ========================================

    private function raise(DomainEventInterface $event): void
    {
        $this->domainEvents[] = $event;
    }

    /**
     * @return array<DomainEventInterface>
     */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];
        return $events;
    }

    // ========================================
    // PRIVATE HELPERS
    // ========================================

    private function touch(): void
    {
        $this->updatedAt = new DateTimeImmutable();
    }
}
