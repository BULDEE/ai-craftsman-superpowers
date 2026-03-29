# Agent: Backend {{RESOURCE}} API

> Template for simple API Platform 4 CRUD resources WITHOUT DDD domain layer
> Replace {{PLACEHOLDERS}} with actual values

## Mission

{{MISSION_DESCRIPTION}}

## Context Files to Read

1. `backend/src/ApiResource/{{RESOURCE}}.php` - Resource DTO
2. `backend/src/Entity/{{RESOURCE}}.php` - Doctrine entity
3. `backend/src/State/` - State providers and processors
4. `backend/CLAUDE.md` - Architecture rules

## Entity Layer

### Doctrine Entity: {{RESOURCE}}

```php
<?php
declare(strict_types=1);

namespace App\Entity;

use App\Repository\{{RESOURCE}}Repository;
use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Bridge\Doctrine\Types\UuidType;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: {{RESOURCE}}Repository::class)]
#[ORM\Table(name: '{{TABLE_NAME}}')]
#[ORM\HasLifecycleCallbacks]
final class {{RESOURCE}}
{
    #[ORM\Id]
    #[ORM\Column(type: UuidType::NAME, unique: true)]
    private Uuid $id;

    {{#each FIELDS}}
    #[ORM\Column(type: '{{DOCTRINE_TYPE}}', {{ORM_OPTIONS}})]
    private {{PHP_TYPE}} ${{NAME}};

    {{/each}}
    #[ORM\Column]
    private DateTimeImmutable $createdAt;

    #[ORM\Column(nullable: true)]
    private ?DateTimeImmutable $updatedAt = null;

    private function __construct(
        {{#each FIELDS}}
        {{PHP_TYPE}} ${{NAME}},
        {{/each}}
    ) {
        $this->id = Uuid::v7();
        {{#each FIELDS}}
        $this->{{NAME}} = ${{NAME}};
        {{/each}}
        $this->createdAt = new DateTimeImmutable();
    }

    public static function create(
        {{#each FIELDS}}
        {{PHP_TYPE}} ${{NAME}},
        {{/each}}
    ): self {
        return new self(
            {{#each FIELDS}}
            ${{NAME}},
            {{/each}}
        );
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    {{#each FIELDS}}
    public function get{{CAPITALIZED_NAME}}(): {{PHP_TYPE}}
    {
        return $this->{{NAME}};
    }

    {{/each}}
    public function getCreatedAt(): DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): ?DateTimeImmutable
    {
        return $this->updatedAt;
    }

    {{#each BEHAVIORAL_METHODS}}
    public function {{NAME}}({{PARAMS}}): void
    {
        {{BODY}}
        $this->updatedAt = new DateTimeImmutable();
    }

    {{/each}}
    #[ORM\PreUpdate]
    public function onPreUpdate(): void
    {
        $this->updatedAt = new DateTimeImmutable();
    }
}
```

## API Resource Layer

### Resource DTO with Operations

```php
<?php
declare(strict_types=1);

namespace App\ApiResource;

use ApiPlatform\Metadata\ApiFilter;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;
use ApiPlatform\Metadata\Put;
use ApiPlatform\Filter\BooleanFilter;
use ApiPlatform\Filter\DateFilter;
use ApiPlatform\Filter\OrderFilter;
use ApiPlatform\Filter\SearchFilter;
use App\State\{{RESOURCE}}StateProvider;
use App\State\Create{{RESOURCE}}Processor;
use App\State\Update{{RESOURCE}}Processor;
use App\State\Delete{{RESOURCE}}Processor;
use DateTimeImmutable;
use OpenApi\Attributes as OA;
use Symfony\Component\Serializer\Attribute\Groups;
use Symfony\Component\Validator\Constraints as Assert;

#[ApiResource(
    shortName: '{{RESOURCE}}',
    operations: [
        new GetCollection(
            uriTemplate: '/{{URI_PREFIX}}',
            normalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:list']],
            provider: {{RESOURCE}}StateProvider::class,
        ),
        new Get(
            uriTemplate: '/{{URI_PREFIX}}/{id}',
            normalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:read']],
            provider: {{RESOURCE}}StateProvider::class,
        ),
        new Post(
            uriTemplate: '/{{URI_PREFIX}}',
            normalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:read']],
            denormalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:write']],
            validationContext: ['groups' => ['{{RESOURCE_LOWER}}:write']],
            processor: Create{{RESOURCE}}Processor::class,
        ),
        new Put(
            uriTemplate: '/{{URI_PREFIX}}/{id}',
            normalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:read']],
            denormalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:write']],
            validationContext: ['groups' => ['{{RESOURCE_LOWER}}:write']],
            provider: {{RESOURCE}}StateProvider::class,
            processor: Update{{RESOURCE}}Processor::class,
        ),
        new Patch(
            uriTemplate: '/{{URI_PREFIX}}/{id}',
            normalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:read']],
            denormalizationContext: ['groups' => ['{{RESOURCE_LOWER}}:patch']],
            validationContext: ['groups' => ['{{RESOURCE_LOWER}}:patch']],
            provider: {{RESOURCE}}StateProvider::class,
            processor: Update{{RESOURCE}}Processor::class,
        ),
        new Delete(
            uriTemplate: '/{{URI_PREFIX}}/{id}',
            provider: {{RESOURCE}}StateProvider::class,
            processor: Delete{{RESOURCE}}Processor::class,
        ),
    ],
    paginationEnabled: true,
    paginationItemsPerPage: {{PAGINATION_ITEMS_PER_PAGE}},
    paginationMaximumItemsPerPage: 100,
    paginationClientItemsPerPage: true,
)]
#[ApiFilter(SearchFilter::class, properties: [{{#each SEARCH_FILTERS}}'{{FIELD}}' => '{{STRATEGY}}'{{#unless @last}}, {{/unless}}{{/each}}])]
#[ApiFilter(OrderFilter::class, properties: [{{#each ORDER_FILTERS}}'{{FIELD}}'{{#unless @last}}, {{/unless}}{{/each}}])]
#[ApiFilter(DateFilter::class, properties: [{{#each DATE_FILTERS}}'{{FIELD}}'{{#unless @last}}, {{/unless}}{{/each}}])]
#[ApiFilter(BooleanFilter::class, properties: [{{#each BOOLEAN_FILTERS}}'{{FIELD}}'{{#unless @last}}, {{/unless}}{{/each}}])]
#[OA\Tag(name: '{{OA_TAG}}')]
final class {{RESOURCE}}
{
    #[Groups(['{{RESOURCE_LOWER}}:list', '{{RESOURCE_LOWER}}:read'])]
    public ?string $id = null;

    {{#each FIELDS}}
    #[Assert\NotBlank(groups: ['{{../RESOURCE_LOWER}}:write'])]
    #[Groups(['{{../RESOURCE_LOWER}}:list', '{{../RESOURCE_LOWER}}:read', '{{../RESOURCE_LOWER}}:write', '{{../RESOURCE_LOWER}}:patch'])]
    public {{NULLABLE}}{{PHP_TYPE}} ${{NAME}} = {{DEFAULT}};

    {{/each}}
    #[Groups(['{{RESOURCE_LOWER}}:read'])]
    public ?DateTimeImmutable $createdAt = null;

    #[Groups(['{{RESOURCE_LOWER}}:read'])]
    public ?DateTimeImmutable $updatedAt = null;
}
```

## State Layer

### State Provider

```php
<?php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\CollectionOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\Pagination\Pagination;
use ApiPlatform\State\ProviderInterface;
use App\ApiResource\{{RESOURCE}} as {{RESOURCE}}ApiResource;
use App\Repository\{{RESOURCE}}Repository;
use App\State\Mapper\{{RESOURCE}}Mapper;
use Symfony\Component\Uid\Uuid;

final class {{RESOURCE}}StateProvider implements ProviderInterface
{
    public function __construct(
        private readonly {{RESOURCE}}Repository $repository,
        private readonly {{RESOURCE}}Mapper $mapper,
        private readonly Pagination $pagination,
    ) {}

    public function provide(Operation $operation, array $uriVariables = [], array $context = []): object|array|null
    {
        if ($operation instanceof CollectionOperationInterface) {
            [$page, $offset, $limit] = $this->pagination->getPagination($operation, $context);

            $entities = $this->repository->findPaginated($page, $limit, $context['filters'] ?? []);

            return array_map($this->mapper->toResource(...), $entities);
        }

        $entity = $this->repository->find(Uuid::fromString($uriVariables['id']));

        if ($entity === null) {
            return null;
        }

        return $this->mapper->toResource($entity);
    }
}
```

### Create Processor

```php
<?php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\ApiResource\{{RESOURCE}} as {{RESOURCE}}ApiResource;
use App\Entity\{{RESOURCE}};
use App\Repository\{{RESOURCE}}Repository;
use App\State\Mapper\{{RESOURCE}}Mapper;

final class Create{{RESOURCE}}Processor implements ProcessorInterface
{
    public function __construct(
        private readonly {{RESOURCE}}Repository $repository,
        private readonly {{RESOURCE}}Mapper $mapper,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): {{RESOURCE}}ApiResource
    {
        $entity = {{RESOURCE}}::create(
            {{#each FIELDS}}
            $data->{{NAME}},
            {{/each}}
        );

        $this->repository->save($entity, flush: true);

        return $this->mapper->toResource($entity);
    }
}
```

### Update Processor

```php
<?php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\ApiResource\{{RESOURCE}} as {{RESOURCE}}ApiResource;
use App\Repository\{{RESOURCE}}Repository;
use App\State\Mapper\{{RESOURCE}}Mapper;

final class Update{{RESOURCE}}Processor implements ProcessorInterface
{
    public function __construct(
        private readonly {{RESOURCE}}Repository $repository,
        private readonly {{RESOURCE}}Mapper $mapper,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): {{RESOURCE}}ApiResource
    {
        $entity = $data->_entity;

        {{#each BEHAVIORAL_METHODS}}
        if ($data->{{TRIGGER_FIELD}} !== null) {
            $entity->{{METHOD_NAME}}($data->{{TRIGGER_FIELD}});
        }
        {{/each}}

        $this->repository->save($entity, flush: true);

        return $this->mapper->toResource($entity);
    }
}
```

### Delete Processor

```php
<?php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Repository\{{RESOURCE}}Repository;

final class Delete{{RESOURCE}}Processor implements ProcessorInterface
{
    public function __construct(
        private readonly {{RESOURCE}}Repository $repository,
    ) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        $this->repository->remove($data->_entity, flush: true);
    }
}
```

### Entity-to-Resource Mapper

```php
<?php
declare(strict_types=1);

namespace App\State\Mapper;

use App\ApiResource\{{RESOURCE}} as {{RESOURCE}}ApiResource;
use App\Entity\{{RESOURCE}};

final class {{RESOURCE}}Mapper
{
    public function toResource({{RESOURCE}} $entity): {{RESOURCE}}ApiResource
    {
        $resource = new {{RESOURCE}}ApiResource();
        $resource->id = (string) $entity->getId();
        {{#each FIELDS}}
        $resource->{{NAME}} = $entity->get{{CAPITALIZED_NAME}}();
        {{/each}}
        $resource->createdAt = $entity->getCreatedAt();
        $resource->updatedAt = $entity->getUpdatedAt();

        return $resource;
    }
}
```

## Repository Layer

```php
<?php
declare(strict_types=1);

namespace App\Repository;

use App\Entity\{{RESOURCE}};
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

final class {{RESOURCE}}Repository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, {{RESOURCE}}::class);
    }

    public function save({{RESOURCE}} $entity, bool $flush = false): void
    {
        $this->getEntityManager()->persist($entity);

        if ($flush) {
            $this->getEntityManager()->flush();
        }
    }

    public function remove({{RESOURCE}} $entity, bool $flush = false): void
    {
        $this->getEntityManager()->remove($entity);

        if ($flush) {
            $this->getEntityManager()->flush();
        }
    }

    public function find(Uuid $id): ?{{RESOURCE}}
    {
        return $this->createQueryBuilder('e')
            ->andWhere('e.id = :id')
            ->setParameter('id', $id, 'uuid')
            ->getQuery()
            ->getOneOrNullResult();
    }

    /**
     * @param array<string, mixed> $filters
     * @return {{RESOURCE}}[]
     */
    public function findPaginated(int $page, int $limit, array $filters = []): array
    {
        $qb = $this->createQueryBuilder('e');

        {{#each FILTERABLE_FIELDS}}
        if (isset($filters['{{NAME}}'])) {
            $qb->andWhere('e.{{NAME}} {{OPERATOR}} :{{NAME}}')
               ->setParameter('{{NAME}}', {{FILTER_VALUE}});
        }
        {{/each}}

        return $qb
            ->orderBy('e.createdAt', 'DESC')
            ->setFirstResult(($page - 1) * $limit)
            ->setMaxResults($limit)
            ->getQuery()
            ->getResult();
    }
}
```

## Infrastructure Files to Create

```
backend/src/
├── ApiResource/
│   └── {{RESOURCE}}.php
├── Entity/
│   └── {{RESOURCE}}.php
├── Repository/
│   └── {{RESOURCE}}Repository.php
├── State/
│   ├── {{RESOURCE}}StateProvider.php
│   ├── Create{{RESOURCE}}Processor.php
│   ├── Update{{RESOURCE}}Processor.php
│   ├── Delete{{RESOURCE}}Processor.php
│   └── Mapper/
│       └── {{RESOURCE}}Mapper.php
└── migrations/
    └── Version{{MIGRATION_TIMESTAMP}}.php
```

## API Platform Configuration

```yaml
# config/packages/api_platform.yaml
api_platform:
    title: '{{API_TITLE}}'
    version: '{{API_VERSION}}'
    formats:
        json: ['application/json']
        jsonld: ['application/ld+json']
        jsonhal: ['application/hal+json']
    docs_formats:
        json: ['application/json']
        jsonld: ['application/ld+json']
        html: ['text/html']
    defaults:
        pagination_enabled: true
        pagination_items_per_page: {{PAGINATION_ITEMS_PER_PAGE}}
        pagination_maximum_items_per_page: 100
        pagination_client_items_per_page: true
    exception_to_status:
        Symfony\Component\HttpKernel\Exception\NotFoundHttpException: 404
        Symfony\Component\Validator\Exception\ValidationFailedException: 422
```

## Functional Tests

```php
<?php
declare(strict_types=1);

namespace App\Tests\Functional\Api;

use ApiPlatform\Symfony\Bundle\Test\ApiTestCase;
use ApiPlatform\Symfony\Bundle\Test\Client;
use App\Entity\{{RESOURCE}};
use App\Tests\Factory\{{RESOURCE}}Factory;
use Zenstruck\Foundry\Test\Factories;
use Zenstruck\Foundry\Test\ResetDatabase;

final class {{RESOURCE}}ApiTest extends ApiTestCase
{
    use Factories;
    use ResetDatabase;

    private Client $client;

    protected function setUp(): void
    {
        $this->client = static::createClient();
    }

    public function test_get_collection_returns_paginated_list(): void
    {
        {{RESOURCE}}Factory::createMany(15);

        $response = $this->client->request('GET', '/api/{{URI_PREFIX}}');

        self::assertResponseIsSuccessful();
        self::assertResponseHeaderSame('content-type', 'application/ld+json; charset=utf-8');

        $data = $response->toArray();
        self::assertArrayHasKey('hydra:totalItems', $data);
        self::assertSame(15, $data['hydra:totalItems']);
        self::assertCount({{PAGINATION_ITEMS_PER_PAGE}}, $data['hydra:member']);
    }

    public function test_get_collection_supports_search_filter(): void
    {
        {{RESOURCE}}Factory::createOne(['{{SEARCH_FIELD}}' => '{{SEARCH_VALUE}}']);
        {{RESOURCE}}Factory::createMany(5);

        $response = $this->client->request('GET', '/api/{{URI_PREFIX}}?{{SEARCH_FIELD}}={{SEARCH_VALUE}}');

        self::assertResponseIsSuccessful();
        $data = $response->toArray();
        self::assertSame(1, $data['hydra:totalItems']);
    }

    public function test_get_item_returns_single_resource(): void
    {
        $entity = {{RESOURCE}}Factory::createOne();

        $this->client->request('GET', '/api/{{URI_PREFIX}}/' . $entity->getId());

        self::assertResponseIsSuccessful();
        self::assertJsonContains([
            {{#each ASSERT_FIELDS}}
            '{{NAME}}' => {{VALUE}},
            {{/each}}
        ]);
    }

    public function test_get_item_returns_404_when_not_found(): void
    {
        $this->client->request('GET', '/api/{{URI_PREFIX}}/00000000-0000-7000-8000-000000000000');

        self::assertResponseStatusCodeSame(404);
    }

    public function test_post_creates_resource(): void
    {
        $this->client->request('POST', '/api/{{URI_PREFIX}}', [
            'json' => [
                {{#each POST_PAYLOAD}}
                '{{NAME}}' => {{VALUE}},
                {{/each}}
            ],
        ]);

        self::assertResponseStatusCodeSame(201);
        self::assertResponseHeaderSame('content-type', 'application/ld+json; charset=utf-8');
        self::assertJsonContains([
            {{#each POST_ASSERT}}
            '{{NAME}}' => {{VALUE}},
            {{/each}}
        ]);
    }

    public function test_post_returns_422_on_validation_failure(): void
    {
        $this->client->request('POST', '/api/{{URI_PREFIX}}', [
            'json' => [{{INVALID_PAYLOAD}}],
        ]);

        self::assertResponseStatusCodeSame(422);
    }

    public function test_patch_updates_resource(): void
    {
        $entity = {{RESOURCE}}Factory::createOne();

        $this->client->request('PATCH', '/api/{{URI_PREFIX}}/' . $entity->getId(), [
            'headers' => ['Content-Type' => 'application/merge-patch+json'],
            'json' => [
                {{#each PATCH_PAYLOAD}}
                '{{NAME}}' => {{VALUE}},
                {{/each}}
            ],
        ]);

        self::assertResponseIsSuccessful();
        self::assertJsonContains([
            {{#each PATCH_ASSERT}}
            '{{NAME}}' => {{VALUE}},
            {{/each}}
        ]);
    }

    public function test_put_replaces_resource(): void
    {
        $entity = {{RESOURCE}}Factory::createOne();

        $this->client->request('PUT', '/api/{{URI_PREFIX}}/' . $entity->getId(), [
            'json' => [
                {{#each PUT_PAYLOAD}}
                '{{NAME}}' => {{VALUE}},
                {{/each}}
            ],
        ]);

        self::assertResponseIsSuccessful();
    }

    public function test_delete_removes_resource(): void
    {
        $entity = {{RESOURCE}}Factory::createOne();

        $this->client->request('DELETE', '/api/{{URI_PREFIX}}/' . $entity->getId());

        self::assertResponseStatusCodeSame(204);
        self::assertNull(
            static::getContainer()->get({{RESOURCE}}Repository::class)->find($entity->getId())
        );
    }
}
```

## Foundry Factory

```php
<?php
declare(strict_types=1);

namespace App\Tests\Factory;

use App\Entity\{{RESOURCE}};
use Zenstruck\Foundry\Persistence\PersistentProxyObjectFactory;

final class {{RESOURCE}}Factory extends PersistentProxyObjectFactory
{
    protected function defaults(): array
    {
        return [
            {{#each FIELDS}}
            '{{NAME}}' => {{FAKER_VALUE}},
            {{/each}}
        ];
    }

    protected function initialize(): static
    {
        return $this;
    }

    public static function class(): string
    {
        return {{RESOURCE}}::class;
    }
}
```

## API Endpoints

```
{{#each ENDPOINTS}}
{{METHOD}} /api/{{URI_PREFIX}}{{PATH}}  # {{DESCRIPTION}}
{{/each}}
```

## Validation Commands

```bash
make phpstan
make test -- --filter={{RESOURCE}}
php bin/console doctrine:schema:validate
php bin/console debug:router | grep {{URI_PREFIX}}
```

## Invariants

{{#each INVARIANTS}}
- {{RULE}}
{{/each}}

## Do NOT

- Add a Domain layer — entities are Doctrine entities directly
- Use Value Objects — use PHP native types on the entity
- Create Command/Handler pairs — processors call the repository directly
- Use DataProvider or DataPersister — those are API Platform v2/v3 patterns
- Put business logic in processors — move it to behavioral methods on the entity
- Use setters — use behavioral methods or the `create()` factory
- Use `new DateTimeImmutable()` inside a class that can be unit tested — inject a Clock
- Leave catch blocks empty

{{#each ANTI_PATTERNS}}
- {{RULE}}
{{/each}}
