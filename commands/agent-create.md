---
name: agent-create
description: Interactively create a bounded context agent from template. Usage /craft agent:create
---

# /craft agent:create - Interactive Agent Creation

Create a bounded context agent through guided questions.

## Usage

```
/craft agent:create
```

## Process

### Step 1: Context Type

```
What type of context are you documenting?

1. Backend (PHP/Symfony domain)
2. Frontend (React/TypeScript)
3. Full-stack (both)

>
```

### Step 2: Context Name

```
Context name (e.g., Gamification, UserManagement, Checkout):

>
```

### Step 3: Mission

```
Describe the context's mission in one sentence:

Example: "Handle user gamification including points, levels, and leaderboards"

>
```

### Step 4: Entities (Backend)

```
List the main entities (comma-separated):

Example: GamificationProfile, Level, WeeklyCheckIn, PointTransaction

>
```

### Step 5: Aggregate Root

```
Which entity is the aggregate root? (main entry point)

1. GamificationProfile
2. Level
3. WeeklyCheckIn
4. PointTransaction

>
```

### Step 6: Value Objects

```
List value objects (comma-separated, or 'none'):

Example: CheckInData, PointAmount

>
```

### Step 7: Domain Services

```
List domain services (comma-separated, or 'none'):

Example: PointCalculator, LevelResolver

>
```

### Step 8: Key Invariants

```
List key business rules (one per line, empty line to finish):

Example:
- Points have caps per category
- CheckIn is immutable after creation
- Level is calculated from total points

>
```

### Step 9: API Endpoints (if applicable)

```
List main API endpoints (one per line, empty line to finish):

Example:
- GET /api/gamification/profile
- POST /api/gamification/check-in
- GET /api/gamification/leaderboard

>
```

### Step 10: Confirmation

```
Agent Summary:

Name: agent-backend-gamification.md
Context: Gamification
Type: Backend

Entities: 4
- GamificationProfile (Aggregate Root)
- Level
- WeeklyCheckIn
- PointTransaction

Value Objects: 1
- CheckInData

Services: 1
- PointCalculator

Invariants: 3
Endpoints: 3

Create this agent? [Y/n]
```

## Generated Template

```markdown
# Agent: Backend {Context} Context

> Created: {date}
> Type: {Backend|Frontend|Full-stack}

## Mission

{mission}

## Context Files to Read

1. `{config.paths.domain}/{Context}/` - Domain layer
2. `{config.paths.application}/{Context}/` - Use cases
3. `backend/CLAUDE.md` - Architecture rules

## Domain Layer

### Aggregate Root: {AggregateRoot}

```php
// {config.paths.domain}/{Context}/Entity/{AggregateRoot}.php
final class {AggregateRoot}
{
    // Key fields and methods to document
}
```

### Entities

{for each entity}
#### {Entity}

```php
final class {Entity}
{
    // Structure
}
```
{/for}

### Value Objects

{for each vo}
- `{VO}` - {purpose}
{/for}

### Domain Services

{for each service}
- `{Service}` - {purpose}
{/for}

## Invariants

{for each invariant}
- {invariant}
{/for}

## API Endpoints

```
{for each endpoint}
{endpoint}
{/for}
```

## Files Structure

```
{config.paths.domain}/{Context}/
├── Entity/
│   ├── {AggregateRoot}.php
{for each entity}
│   └── {Entity}.php
{/for}
├── ValueObject/
{for each vo}
│   └── {VO}.php
{/for}
├── Service/
{for each service}
│   └── {Service}.php
{/for}
├── Repository/
│   └── {AggregateRoot}RepositoryInterface.php
└── Event/
    └── (domain events)
```

## Validation

```bash
make phpstan
make test -- --filter={Context}
```

## Do NOT

- {context-specific anti-patterns}
```

## Output

Save to: `.claude/agents/agent-{type}-{context}.md`

```
✓ Agent created: .claude/agents/agent-backend-gamification.md

Use this agent as context when working on the Gamification bounded context.
```
