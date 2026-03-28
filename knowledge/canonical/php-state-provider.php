<?php

/**
 * CANONICAL EXAMPLE: API Platform State Provider Pattern (v1.0)
 *
 * This is THE reference for custom API Platform state providers and processors.
 * Source: https://symfony.com/doc/current/the-fast-track/en/26-api.html
 *
 * Key characteristics:
 * - Implement ProviderInterface for reads (MUST)
 * - Implement ProcessorInterface for writes (MUST)
 * - final class (MUST)
 * - Use Query Extension pattern for filtering (SHOULD)
 * - Delegate business logic to use cases or domain (MUST)
 */

declare(strict_types=1);

namespace App\Infrastructure\ApiPlatform;

use ApiPlatform\Doctrine\Orm\Extension\QueryCollectionExtensionInterface;
use ApiPlatform\Doctrine\Orm\Extension\QueryItemExtensionInterface;
use ApiPlatform\Doctrine\Orm\Util\QueryNameGeneratorInterface;
use ApiPlatform\Metadata\Operation;
use App\Domain\Entity\Post;
use Doctrine\ORM\QueryBuilder;

// ============================================================
// CANONICAL EXAMPLE: Query Extension (v1.0)
// Restricts which items are exposed via the API.
// ============================================================

final class FilterPublishedPostQueryExtension implements
    QueryCollectionExtensionInterface,
    QueryItemExtensionInterface
{
    public function applyToCollection(
        QueryBuilder $queryBuilder,
        QueryNameGeneratorInterface $queryNameGenerator,
        string $resourceClass,
        ?Operation $operation = null,
        array $context = [],
    ): void {
        $this->applyFilter($queryBuilder, $resourceClass);
    }

    public function applyToItem(
        QueryBuilder $queryBuilder,
        QueryNameGeneratorInterface $queryNameGenerator,
        string $resourceClass,
        array $identifiers,
        ?Operation $operation = null,
        array $context = [],
    ): void {
        $this->applyFilter($queryBuilder, $resourceClass);
    }

    private function applyFilter(QueryBuilder $queryBuilder, string $resourceClass): void
    {
        if (Post::class !== $resourceClass) {
            return;
        }

        $rootAlias = $queryBuilder->getRootAliases()[0];
        $queryBuilder->andWhere(sprintf("%s.status = 'published'", $rootAlias));
    }
}

// ============================================================
// CANONICAL EXAMPLE: Entity with API Resource (v1.0)
// ============================================================
// use ApiPlatform\Metadata\ApiResource;
// use ApiPlatform\Metadata\Get;
// use ApiPlatform\Metadata\GetCollection;
// use Symfony\Component\Serializer\Attribute\Groups;
//
// #[ORM\Entity]
// #[ApiResource(
//     operations: [
//         new Get(normalizationContext: ['groups' => 'post:item']),
//         new GetCollection(normalizationContext: ['groups' => 'post:list']),
//     ],
//     order: ['createdAt' => 'DESC'],
//     paginationEnabled: true,
// )]
// final class Post
// {
//     #[Groups(['post:list', 'post:item'])]
//     private ?int $id = null;
//
//     #[Groups(['post:list', 'post:item'])]
//     private string $title;
// }
