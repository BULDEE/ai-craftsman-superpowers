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

## React 19 Patterns

### Server Components

Server Components run on the server by default. Opt into client-side rendering only when necessary.

```
Rules:
- Default to Server Components for data fetching and static markup
- Use "use client" only for: onClick, useState, useEffect, browser APIs
- Keep client bundles small — move data fetching up to Server Components
- Wrap independently-fetched child components in <Suspense> for streaming
```

### useOptimistic — Instant UI feedback

```tsx
'use client';

import { useOptimistic } from 'react';

interface {{Entity}}ListProps {
  readonly items: readonly {{Entity}}[];
}

function {{Entity}}List({ items }: {{Entity}}ListProps) {
  const [optimisticItems, addOptimistic] = useOptimistic(
    items,
    (state: readonly {{Entity}}[], newItem: {{Entity}}) => [...state, newItem],
  );

  async function handleCreate(formData: FormData) {
    const newItem = parse{{Entity}}(formData);
    addOptimistic(newItem);         // Update UI immediately
    await create{{Entity}}(newItem); // Persist in background
  }

  return (
    <form action={handleCreate}>
      {optimisticItems.map(item => (
        <{{Entity}}Row key={item.id} item={item} />
      ))}
    </form>
  );
}
```

### useTransition — Non-blocking state updates

```tsx
'use client';

import { useTransition, useState } from 'react';

function {{Entity}}Search() {
  const [isPending, startTransition] = useTransition();
  const [results, setResults] = useState<readonly {{Entity}}[]>([]);

  function handleSearch(query: string) {
    startTransition(() => {
      // Marked as non-urgent — React can interrupt this
      setResults(filterResults(query));
    });
  }

  return (
    <div>
      <input onChange={e => handleSearch(e.target.value)} />
      {isPending && <span aria-live="polite">Filtering…</span>}
      <{{Entity}}List items={results} />
    </div>
  );
}
```

## Composition Patterns

### Compound Components

Compound components share implicit state through context. Use when sub-components are always used together and need coordinated state.

```tsx
'use client';

import { createContext, use, useState, type ReactNode } from 'react';

interface TabsContextType {
  readonly activeTab: string;
  readonly setActiveTab: (tab: string) => void;
}

interface TabsProps {
  readonly children: ReactNode;
  readonly defaultTab: string;
}

interface TabPanelProps {
  readonly id: string;
  readonly children: ReactNode;
}

const TabsContext = createContext<TabsContextType | null>(null);

function useTabsContext(): TabsContextType {
  const context = use(TabsContext);
  if (context === null) {
    throw new Error('TabPanel must be used within Tabs');
  }
  return context;
}

export function Tabs({ children, defaultTab }: TabsProps) {
  const [activeTab, setActiveTab] = useState(defaultTab);

  return (
    <TabsContext value={{ activeTab, setActiveTab }}>
      {children}
    </TabsContext>
  );
}

export function TabPanel({ id, children }: TabPanelProps) {
  const { activeTab } = useTabsContext();
  if (activeTab !== id) return null;
  return <div role="tabpanel">{children}</div>;
}

// Usage:
// <Tabs defaultTab="profile">
//   <TabPanel id="profile">...</TabPanel>
//   <TabPanel id="settings">...</TabPanel>
// </Tabs>
```

### Render Props (Modern — with useSuspenseQuery)

> **Important:** `useSuspenseQuery` throws on error. Always wrap usage in an `<ErrorBoundary>` alongside `<Suspense>`:
> ```tsx
> <ErrorBoundary fallback={<ErrorMessage />}>
>   <Suspense fallback={<Skeleton />}>
>     <DataLoader queryKey={[...]} queryFn={...}>
>       {data => <Component data={data} />}
>     </DataLoader>
>   </Suspense>
> </ErrorBoundary>
> ```

```tsx
import { useSuspenseQuery } from '@tanstack/react-query';
import type { ReactNode } from 'react';

interface DataLoaderProps<T> {
  readonly queryKey: readonly string[];
  readonly queryFn: () => Promise<T>;
  readonly children: (data: T) => ReactNode;
}

function DataLoader<T>({ queryKey, queryFn, children }: DataLoaderProps<T>) {
  const { data } = useSuspenseQuery({ queryKey, queryFn });
  return <>{children(data)}</>;
}

// Usage:
// <DataLoader queryKey={['user', id]} queryFn={() => fetchUser(id)}>
//   {user => <UserCard user={user} />}
// </DataLoader>
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
