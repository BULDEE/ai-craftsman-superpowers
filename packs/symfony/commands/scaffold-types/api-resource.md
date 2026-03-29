---
description: Scaffold API Platform resource with State Provider, State Processor, DTOs, and tests
effort: medium
---

# API Resource Scaffolding

## Project Context

!`cat .craft-config.yml 2>/dev/null || echo "No config found. Run /craftsman:setup first."`

## Iron Law

Before generating ANY code, load the canonical examples:

!`cat packs/symfony/knowledge/canonical/php-state-provider.php 2>/dev/null || echo "Canonical not found"`
!`cat packs/symfony/knowledge/canonical/php-entity.php 2>/dev/null || echo "Canonical not found"`

## Process

### Phase 1: Define the API Contract

Ask the user:
1. Resource name (e.g., `Order`)
2. Operations needed (GET collection, GET item, POST, PUT, PATCH, DELETE)
3. Relationships (e.g., Order hasMany OrderItems)
4. Filtering/sorting requirements
5. Pagination strategy (cursor-based or offset)

### Phase 2: Generate Files

For a resource named `{Name}`:

1. **Entity** — `src/Domain/Entity/{Name}.php`
   - `final class` with private constructor + factory
   - Domain events for state changes
   - Value Objects for domain primitives

2. **API Resource DTO** — `src/Presentation/Api/Resource/{Name}Resource.php`
   - `#[ApiResource]` with operations
   - `#[ApiFilter]` for configured filters
   - Serialization groups for read/write separation

3. **State Provider** — `src/Infrastructure/Api/State/{Name}Provider.php`
   - Implements `ProviderInterface`
   - Uses repository for data access
   - Handles collection pagination and item lookup

4. **State Processor** — `src/Infrastructure/Api/State/{Name}Processor.php`
   - Implements `ProcessorInterface`
   - Delegates to use cases / command bus
   - Returns proper HTTP status codes

5. **Input DTOs** — `src/Presentation/Api/Dto/Create{Name}Input.php`, `Update{Name}Input.php`
   - Validation constraints
   - No logic, pure data carriers

6. **Tests** — `tests/Functional/Api/{Name}Test.php`
   - Test each operation
   - Test validation errors
   - Test pagination
   - Test filtering

### Phase 3: Verify

- Run `/craftsman:verify` to ensure all files pass validators
- Check API Platform configuration is correct
