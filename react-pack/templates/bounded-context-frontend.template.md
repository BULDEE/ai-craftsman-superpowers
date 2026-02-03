# Agent: Frontend {{CONTEXT}} Context

> Template for frontend bounded context agents
> Replace {{PLACEHOLDERS}} with actual values

## Mission

{{MISSION_DESCRIPTION}}

## Context Files to Read

1. `frontend/src/domain/{{context}}/` - Domain types
2. `frontend/src/application/{{context}}/` - Hooks and services
3. `frontend/src/presentation/{{context}}/` - Components
4. `frontend/CLAUDE.md` - Frontend rules

## Domain Layer

### Types

```typescript
// frontend/src/domain/{{context}}/types.ts

export type {{Entity}}Id = Brand<string, '{{Entity}}Id'>;

export interface {{Entity}} {
  readonly id: {{Entity}}Id;
  {{#each FIELDS}}
  readonly {{NAME}}: {{TYPE}};
  {{/each}}
}

{{#each ENUMS}}
export type {{NAME}} = {{VALUES}};
{{/each}}
```

### API Types

```typescript
// frontend/src/domain/{{context}}/api.ts

export interface {{Entity}}Response {
  readonly id: string;
  {{#each API_FIELDS}}
  readonly {{NAME}}: {{TYPE}};
  {{/each}}
}

export interface Create{{Entity}}Input {
  {{#each INPUT_FIELDS}}
  readonly {{NAME}}: {{TYPE}};
  {{/each}}
}
```

## Application Layer

### Query Keys

```typescript
// frontend/src/application/{{context}}/keys.ts

export const {{entity}}Keys = {
  all: ['{{entity}}'] as const,
  lists: () => [...{{entity}}Keys.all, 'list'] as const,
  list: (filters: {{Entity}}Filters) => [...{{entity}}Keys.lists(), filters] as const,
  details: () => [...{{entity}}Keys.all, 'detail'] as const,
  detail: (id: {{Entity}}Id) => [...{{entity}}Keys.details(), id] as const,
};
```

### Hooks

{{#each HOOKS}}
#### use{{NAME}}

```typescript
export function use{{NAME}}({{PARAMS}}): {{RETURN}} {
  // {{DESCRIPTION}}
}
```
{{/each}}

## Presentation Layer

### Components

```
frontend/src/presentation/{{context}}/
{{#each COMPONENTS}}
├── {{NAME}}/
│   ├── {{NAME}}.tsx
│   ├── {{NAME}}.test.tsx
│   └── index.ts
{{/each}}
```

### Pages

{{#each PAGES}}
- `{{PATH}}` - {{DESCRIPTION}}
{{/each}}

## File Structure

```
frontend/src/
├── domain/{{context}}/
│   ├── types.ts
│   └── api.ts
├── application/{{context}}/
│   ├── keys.ts
│   ├── use{{Entity}}.ts
│   └── use{{Entity}}Mutation.ts
└── presentation/{{context}}/
    ├── components/
    └── pages/
```

## Validation Commands

```bash
npm run typecheck
npm run test -- --filter={{context}}
npm run lint
```

## Do NOT

{{#each ANTI_PATTERNS}}
- {{RULE}}
{{/each}}
