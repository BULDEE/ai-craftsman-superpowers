<?php

declare(strict_types=1);

namespace App\Domain\Entity;

final class Account
{
    private function __construct(
        private string $email,
    ) {
    }

    public static function create(string $email): self
    {
        return new self($email);
    }

    public function setEmail(string $email): void
    {
        $this->email = $email;
    }
}
