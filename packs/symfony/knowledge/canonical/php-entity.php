<?php

/**
 * CANONICAL EXAMPLE: Entity Pattern (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - final class (MUST)
 * - private constructor (MUST)
 * - static factory create() (MUST)
 * - Clock injection for time (MUST)
 * - Domain events recording (SHOULD)
 * - No setters - behavioral methods only (MUST)
 * - Value Objects for typed fields (SHOULD)
 */

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Domain\Event\UserActivated;
use App\Domain\Event\UserCreated;
use App\Domain\Event\UserEmailChanged;
use App\Domain\ValueObject\Email;
use App\Domain\ValueObject\UserId;
use App\Shared\Domain\Aggregate\AggregateRoot;
use App\Shared\Domain\Clock\Clock;

final class User extends AggregateRoot
{
    private function __construct(
        private readonly UserId $id,
        private Email $email,
        private Status $status,
        private readonly \DateTimeImmutable $createdAt,
        private ?\DateTimeImmutable $activatedAt,
    ) {}

    public static function create(Email $email, Clock $clock): self
    {
        $user = new self(
            id: UserId::generate(),
            email: $email,
            status: Status::PENDING,
            createdAt: $clock->now(),
            activatedAt: null,
        );

        $user->record(new UserCreated($user->id, $user->email));

        return $user;
    }

    public function activate(Clock $clock): void
    {
        if ($this->status === Status::ACTIVE) {
            throw new UserAlreadyActivatedException($this->id);
        }

        $this->status = Status::ACTIVE;
        $this->activatedAt = $clock->now();

        $this->record(new UserActivated($this->id));
    }

    public function changeEmail(Email $newEmail): void
    {
        if ($this->email->equals($newEmail)) {
            return;
        }

        $oldEmail = $this->email;
        $this->email = $newEmail;

        $this->record(new UserEmailChanged($this->id, $oldEmail, $newEmail));
    }

    public function id(): UserId
    {
        return $this->id;
    }

    public function email(): Email
    {
        return $this->email;
    }

    public function status(): Status
    {
        return $this->status;
    }

    public function isActive(): bool
    {
        return $this->status === Status::ACTIVE;
    }
}
