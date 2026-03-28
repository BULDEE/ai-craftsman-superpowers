<?php

/**
 * CANONICAL EXAMPLE: API Platform 4 State Provider (v1.0)
 *
 * This is THE reference for State Providers in API Platform 4.
 * Replaces the DataProvider pattern from API Platform v2/v3.
 *
 * Key characteristics:
 * - Implements ProviderInterface (MUST)
 * - final class (MUST)
 * - Handles both collection and item operations
 * - Delegates to domain repository (Clean Architecture)
 * - Uses domain Value Objects for ID conversion
 */

declare(strict_types=1);

namespace App\Infrastructure\ApiPlatform\State;

use ApiPlatform\Metadata\CollectionOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\Pagination\Pagination;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Repository\UserRepositoryInterface;
use App\Domain\ValueObject\UserId;

final class UserStateProvider implements ProviderInterface
{
    public function __construct(
        private readonly UserRepositoryInterface $repository,
        private readonly Pagination $pagination,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        if ($operation instanceof CollectionOperationInterface) {
            [$page, $offset, $limit] = $this->pagination->getPagination($operation, $context);

            // Repository MUST return a PaginatorInterface implementation for hydra:totalItems
            return $this->repository->findPaginated($page, $limit);
        }

        return $this->repository->findById(
            UserId::fromString($uriVariables['id'])
        );
    }
}
