<?php

declare(strict_types=1);

namespace App\Domain\Entity;

final class Order
{
    private function __construct(
        private readonly string $id,
        private readonly string $customerId,
    ) {
    }

    public static function create(string $id, string $customerId): self
    {
        return new self($id, $customerId);
    }

    public function id(): string
    {
        return $this->id;
    }

    public function customerId(): string
    {
        return $this->customerId;
    }
}
