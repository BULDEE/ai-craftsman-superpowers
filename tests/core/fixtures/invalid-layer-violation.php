<?php

declare(strict_types=1);

namespace App\Domain\Service;

use App\Infrastructure\Persistence\DoctrineUserRepository;

final class UserService
{
    public function __construct(
        private readonly DoctrineUserRepository $repository,
    ) {
    }
}
