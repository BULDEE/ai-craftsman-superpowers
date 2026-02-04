---
name: hook
description: |
  Scaffold React custom hook with TanStack Query integration.
  Use when creating data fetching or state management hooks.

  ACTIVATES AUTOMATICALLY when detecting: "hook", "useQuery", "useMutation",
  "custom hook", "TanStack Query", "data fetching"
model: sonnet
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
---

# Hook Skill - Custom Hook Scaffolding with TanStack Query

Scaffold custom React hooks for data fetching using TanStack Query.

## Generated Structure

```
src/
└── hooks/
    └── {hookName}/
        ├── {hookName}.ts
        ├── {hookName}.test.ts
        └── index.ts
```

## Query Hook Template

```tsx
import { useQuery, type UseQueryResult } from '@tanstack/react-query';
import { api } from '@/lib/api';

// Types
export interface {Entity} {
  readonly id: string;
  readonly name: string;
  // Add other fields
}

interface Use{Entity}Options {
  readonly enabled?: boolean;
}

// Query key factory
export const {entity}Keys = {
  all: ['entities'] as const,
  lists: () => [...{entity}Keys.all, 'list'] as const,
  list: (filters: Record<string, unknown>) => [...{entity}Keys.lists(), filters] as const,
  details: () => [...{entity}Keys.all, 'detail'] as const,
  detail: (id: string) => [...{entity}Keys.details(), id] as const,
};

// Fetch function
async function fetch{Entity}(id: string): Promise<{Entity}> {
  const response = await api.get<{Entity}>(`/entities/${id}`);
  return response.data;
}

// Hook
export function use{Entity}(
  id: string,
  options: Use{Entity}Options = {},
): UseQueryResult<{Entity}> {
  return useQuery({
    queryKey: {entity}Keys.detail(id),
    queryFn: () => fetch{Entity}(id),
    enabled: options.enabled ?? true,
  });
}
```

## Mutation Hook Template

```tsx
import { useMutation, useQueryClient, type UseMutationResult } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { {entity}Keys } from './use{Entity}';

// Types
export interface Create{Entity}Input {
  readonly name: string;
  // Add other fields
}

export interface Create{Entity}Response {
  readonly id: string;
}

// Mutation function
async function create{Entity}(input: Create{Entity}Input): Promise<Create{Entity}Response> {
  const response = await api.post<Create{Entity}Response>('/entities', input);
  return response.data;
}

// Hook
export function useCreate{Entity}(): UseMutationResult<
  Create{Entity}Response,
  Error,
  Create{Entity}Input
> {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: create{Entity},
    onSuccess: () => {
      // Invalidate and refetch
      queryClient.invalidateQueries({ queryKey: {entity}Keys.lists() });
    },
  });
}
```

## List Hook Template

```tsx
import { useQuery, type UseQueryResult } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { {entity}Keys, type {Entity} } from './use{Entity}';

// Types
export interface {Entity}ListFilters {
  readonly status?: 'active' | 'inactive';
  readonly search?: string;
  readonly page?: number;
  readonly limit?: number;
}

export interface {Entity}ListResponse {
  readonly items: readonly {Entity}[];
  readonly total: number;
  readonly page: number;
  readonly limit: number;
}

// Fetch function
async function fetch{Entity}List(filters: {Entity}ListFilters): Promise<{Entity}ListResponse> {
  const response = await api.get<{Entity}ListResponse>('/entities', { params: filters });
  return response.data;
}

// Hook
export function use{Entity}List(
  filters: {Entity}ListFilters = {},
): UseQueryResult<{Entity}ListResponse> {
  return useQuery({
    queryKey: {entity}Keys.list(filters),
    queryFn: () => fetch{Entity}List(filters),
  });
}
```

## Test Template

```tsx
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { use{Entity} } from './use{Entity}';
import { api } from '@/lib/api';

vi.mock('@/lib/api');

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  });

  return function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };
}

describe('use{Entity}', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('fetches entity by id', async () => {
    const mockEntity = { id: '123', name: 'Test Entity' };
    vi.mocked(api.get).mockResolvedValueOnce({ data: mockEntity });

    const { result } = renderHook(() => use{Entity}('123'), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual(mockEntity);
    expect(api.get).toHaveBeenCalledWith('/entities/123');
  });

  it('handles error', async () => {
    vi.mocked(api.get).mockRejectedValueOnce(new Error('Not found'));

    const { result } = renderHook(() => use{Entity}('invalid'), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isError).toBe(true));

    expect(result.current.error?.message).toBe('Not found');
  });

  it('respects enabled option', () => {
    const { result } = renderHook(() => use{Entity}('123', { enabled: false }), {
      wrapper: createWrapper(),
    });

    expect(result.current.fetchStatus).toBe('idle');
    expect(api.get).not.toHaveBeenCalled();
  });
});
```

## Index Export

```tsx
export { use{Entity}, {entity}Keys } from './use{Entity}';
export type { {Entity}, Use{Entity}Options } from './use{Entity}';

export { useCreate{Entity} } from './useCreate{Entity}';
export type { Create{Entity}Input, Create{Entity}Response } from './useCreate{Entity}';

export { use{Entity}List } from './use{Entity}List';
export type { {Entity}ListFilters, {Entity}ListResponse } from './use{Entity}List';
```

## Rules Enforced

| Rule | Enforcement |
|------|-------------|
| No `any` types | Explicit types everywhere |
| `readonly` types | All interface properties |
| Query key factory | Consistent cache keys |
| Error handling | Proper error types |
| Named exports | No default exports |

## Process

### Step 0: MANDATORY - Load Canonical Examples

**BEFORE generating any code, you MUST use the Read tool to load:**

```
Read: knowledge/canonical/ts-tanstack-hook.ts
Read: knowledge/canonical/ts-branded-type.ts
```

This ensures generated code matches project standards exactly.

### Steps

1. **Load canonical examples** (Step 0 above - NON-NEGOTIABLE)
2. **Ask for hook purpose and entity**
3. **Identify operations (query/mutation)**
4. **Generate hook files**
5. **Generate tests**
6. **Generate index export**
7. **Verify**

```bash
npm run typecheck
npm test -- --filter=use{Entity}
```
