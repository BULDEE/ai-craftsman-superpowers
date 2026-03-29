<?php

declare(strict_types=1);

namespace App\Domain\Entity;

final class User
{
    private function __construct(
        private readonly string $id,
        private readonly string $email,
    ) {
    }

    public static function create(string $id, string $email): self
    {
        return new self($id, $email);
    }

    public function id(): string
    {
        return $this->id;
    }

    public function email(): string
    {
        return $this->email;
    }
}
