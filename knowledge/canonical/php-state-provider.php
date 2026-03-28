<?php

/**
 * CANONICAL EXAMPLE: API Platform 4 State Provider & Processor (v1.0)
 *
 * Verified against official docs: https://api-platform.com/docs/core/state-providers/
 * and https://api-platform.com/docs/core/state-processors/
 *
 * Key characteristics:
 * - ProviderInterface::provide() — returns object|array|null (MUST)
 * - ProcessorInterface::process() — returns mixed (MUST)
 * - CollectionOperationInterface used to distinguish item vs collection (CONFIRMED AP4)
 * - final class (MUST)
 * - declare(strict_types=1) (MUST)
 */

declare(strict_types=1);

// ============================================================
// State Provider — Item + Collection
// Source: https://api-platform.com/docs/core/state-providers/
// ============================================================

namespace App\State;

use ApiPlatform\Metadata\CollectionOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Domain\Repository\BookRepositoryInterface;
use App\Domain\ValueObject\BookId;

final class BookProvider implements ProviderInterface
{
    public function __construct(
        private readonly BookRepositoryInterface $repository,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        if ($operation instanceof CollectionOperationInterface) {
            return $this->repository->findAll();
        }

        return $this->repository->findById(BookId::fromString($uriVariables['id']));
    }
}

// ============================================================
// State Provider — Decorator Pattern (wrap built-in provider)
// Source: https://api-platform.com/docs/core/state-providers/
// ============================================================

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Api\Resource\Book as BookResource;
use Symfony\Component\DependencyInjection\Attribute\Autowire;

final class BookRepresentationProvider implements ProviderInterface
{
    public function __construct(
        #[Autowire(service: 'api_platform.doctrine.orm.state.item_provider')]
        private readonly ProviderInterface $itemProvider,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        $book = $this->itemProvider->provide($operation, $uriVariables, $context);

        if ($book === null) {
            return null;
        }

        return new BookResource(/* map from entity */);
    }
}

// ============================================================
// State Processor — CRUD
// Source: https://api-platform.com/docs/core/state-processors/
// ============================================================

namespace App\State;

use ApiPlatform\Metadata\DeleteOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Domain\Entity\Book;
use Symfony\Component\DependencyInjection\Attribute\Autowire;

/**
 * @implements ProcessorInterface<Book, Book|void>
 */
final class BookProcessor implements ProcessorInterface
{
    public function __construct(
        #[Autowire(service: 'api_platform.doctrine.orm.state.persist_processor')]
        private readonly ProcessorInterface $persistProcessor,
        #[Autowire(service: 'api_platform.doctrine.orm.state.remove_processor')]
        private readonly ProcessorInterface $removeProcessor,
    ) {}

    /**
     * @return Book|void
     */
    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): mixed
    {
        if ($operation instanceof DeleteOperationInterface) {
            return $this->removeProcessor->process($data, $operation, $uriVariables, $context);
        }

        return $this->persistProcessor->process($data, $operation, $uriVariables, $context);
    }
}

// ============================================================
// API Resource (DTO-first approach — AP4 recommended pattern)
// Source: https://api-platform.com/docs/core/dto/
// ============================================================

namespace App\Api\Resource;

use ApiPlatform\Doctrine\Orm\State\Options;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;
use App\Api\Dto\CreateBook;
use App\Api\Dto\UpdateBook;
use App\Api\Dto\BookCollection;
use App\Entity\Book as BookEntity;
use App\State\BookProcessor;
use App\State\BookProvider;
use Symfony\Component\ObjectMapper\Attribute\Map;

#[ApiResource(
    shortName: 'Book',
    stateOptions: new Options(entityClass: BookEntity::class),
    operations: [
        new Get(provider: BookProvider::class),
        new GetCollection(
            provider: BookProvider::class,
            output: BookCollection::class,
        ),
        new Post(
            input: CreateBook::class,
            processor: BookProcessor::class,
        ),
        new Patch(
            input: UpdateBook::class,
            processor: BookProcessor::class,
        ),
    ],
)]
#[Map(source: BookEntity::class)]
final class Book
{
    public int $id;

    #[Map(source: 'title')]
    public string $name;

    public string $description;

    public string $isbn;
}

// ============================================================
// Input DTO
// Source: https://api-platform.com/docs/core/dto/
// ============================================================

namespace App\Api\Dto;

use App\Entity\Book as BookEntity;
use Symfony\Component\ObjectMapper\Attribute\Map;
use Symfony\Component\Validator\Constraints as Assert;

#[Map(target: BookEntity::class)]
final class CreateBook
{
    #[Assert\NotBlank]
    #[Assert\Length(max: 255)]
    #[Map(target: 'title')]
    public string $name;

    #[Assert\NotBlank]
    #[Assert\Length(max: 255)]
    public string $description;

    #[Assert\NotBlank]
    #[Assert\Isbn]
    public string $isbn;

    #[Assert\PositiveOrZero]
    public int $price;
}

// ============================================================
// Output DTO (collection)
// Source: https://api-platform.com/docs/core/dto/
// ============================================================

namespace App\Api\Dto;

use App\Entity\Book as BookEntity;
use Symfony\Component\ObjectMapper\Attribute\Map;

#[Map(source: BookEntity::class)]
final class BookCollection
{
    public int $id;

    #[Map(source: 'title')]
    public string $name;

    public string $isbn;
}
