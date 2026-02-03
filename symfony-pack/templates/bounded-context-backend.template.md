# Agent: Backend {{CONTEXT}} Context

> Template for backend bounded context agents
> Replace {{PLACEHOLDERS}} with actual values

## Mission

{{MISSION_DESCRIPTION}}

## Context Files to Read

1. `backend/src/Domain/{{CONTEXT}}/` - Domain layer
2. `backend/src/Application/{{CONTEXT}}/` - Use cases
3. `backend/CLAUDE.md` - Architecture rules

## Domain Layer

### Aggregate Root: {{AGGREGATE_ROOT}}

```php
// backend/src/Domain/{{CONTEXT}}/Entity/{{AGGREGATE_ROOT}}.php
final class {{AGGREGATE_ROOT}}
{
    private Uuid $id;
    {{#each FIELDS}}
    private {{TYPE}} ${{NAME}};
    {{/each}}
    private DateTimeImmutable $createdAt;

    private function __construct(...) { }

    public static function create({{PARAMS}}): self { }

    {{#each BEHAVIORS}}
    public function {{NAME}}({{PARAMS}}): {{RETURN}} { }
    {{/each}}
}
```

### Entities

{{#each ENTITIES}}
#### {{NAME}}

```php
final class {{NAME}}
{
    // {{DESCRIPTION}}
}
```
{{/each}}

### Value Objects

{{#each VALUE_OBJECTS}}
- `{{NAME}}` - {{DESCRIPTION}}
{{/each}}

### Domain Services

{{#each SERVICES}}
- `{{NAME}}` - {{DESCRIPTION}}
{{/each}}

### Repositories

{{#each REPOSITORIES}}
- `{{NAME}}RepositoryInterface`
{{/each}}

### Domain Events

{{#each EVENTS}}
- `{{NAME}}Event` - {{DESCRIPTION}}
{{/each}}

## Application Layer

### Use Cases

{{#each USE_CASES}}
#### {{NAME}}

```php
final readonly class {{NAME}}Command
{
    public function __construct(
        {{#each PARAMS}}
        public {{TYPE}} ${{NAME}},
        {{/each}}
    ) { }
}

final readonly class {{NAME}}Handler
{
    public function __invoke({{NAME}}Command $command): {{RETURN}}
    {
        // {{DESCRIPTION}}
    }
}
```
{{/each}}

## Infrastructure Layer

### Files to Create

```
backend/src/Infrastructure/Persistence/{{CONTEXT}}/
{{#each REPOSITORIES}}
├── Doctrine{{NAME}}Repository.php
{{/each}}
```

## API Endpoints

```
{{#each ENDPOINTS}}
{{METHOD}} {{PATH}}  # {{DESCRIPTION}}
{{/each}}
```

## Validation Commands

```bash
make phpstan
make test -- --filter={{CONTEXT}}
```

## Invariants

{{#each INVARIANTS}}
- {{RULE}}
{{/each}}

## Do NOT

{{#each ANTI_PATTERNS}}
- {{RULE}}
{{/each}}
