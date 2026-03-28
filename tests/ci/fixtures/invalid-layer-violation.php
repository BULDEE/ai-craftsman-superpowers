<?php

declare(strict_types=1);

namespace App\Domain\Entity;

use App\Infrastructure\Persistence\UserRepository;

final class UserWithLayerViolation
{
    private function __construct(
        private readonly string $id,
    ) {
    }

    public static function create(string $id): self
    {
        return new self($id);
    }
}
