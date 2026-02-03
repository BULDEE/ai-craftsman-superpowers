---
name: craft-hook
description: Scaffold a TanStack Query hook with proper types and error handling.
---

# /craft hook - TanStack Query Hook Scaffolding

Generate a custom hook using TanStack Query.

## Usage

```
/craft hook <hookName>
/craft hook useUser
/craft hook useCreateOrder --mutation
```

## Generated Code

### Query Hook

```tsx
import { useQuery, type UseQueryOptions } from '@tanstack/react-query';
import { api } from '@/lib/api';

// Response type
export interface {Entity}Response {
  readonly id: string;
  readonly name: string;
  // ... fields
}

// Query key factory
export const {entity}Keys = {
  all: ['{entity}'] as const,
  lists: () => [...{entity}Keys.all, 'list'] as const,
  list: (filters: {Entity}Filters) => [...{entity}Keys.lists(), filters] as const,
  details: () => [...{entity}Keys.all, 'detail'] as const,
  detail: (id: string) => [...{entity}Keys.details(), id] as const,
};

// Fetch function
async function fetch{Entity}(id: string): Promise<{Entity}Response> {
  const response = await api.get<{Entity}Response>(`/{entities}/${id}`);
  return response.data;
}

// Hook
export function use{Entity}(
  id: string,
  options?: Omit<UseQueryOptions<{Entity}Response>, 'queryKey' | 'queryFn'>
) {
  return useQuery({
    queryKey: {entity}Keys.detail(id),
    queryFn: () => fetch{Entity}(id),
    ...options,
  });
}
```

### Mutation Hook

```tsx
import { useMutation, useQueryClient, type UseMutationOptions } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { {entity}Keys } from './use{Entity}';

// Input type
export interface Create{Entity}Input {
  readonly name: string;
  // ... fields
}

// Response type
export interface Create{Entity}Response {
  readonly id: string;
}

// Mutation function
async function create{Entity}(input: Create{Entity}Input): Promise<Create{Entity}Response> {
  const response = await api.post<Create{Entity}Response>('/{entities}', input);
  return response.data;
}

// Hook
export function useCreate{Entity}(
  options?: Omit<UseMutationOptions<Create{Entity}Response, Error, Create{Entity}Input>, 'mutationFn'>
) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: create{Entity},
    onSuccess: () => {
      // Invalidate related queries
      queryClient.invalidateQueries({ queryKey: {entity}Keys.lists() });
    },
    ...options,
  });
}
```

### Test

```tsx
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { use{Entity} } from './use{Entity}';

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
};

describe('use{Entity}', () => {
  it('fetches {entity} data', async () => {
    const { result } = renderHook(() => use{Entity}('123'), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual({
      id: '123',
      // ... expected data
    });
  });
});
```

## Query Key Conventions

```tsx
// Entity-based keys
const userKeys = {
  all: ['user'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
};
```

## Rules Applied

- `no_any: true` → Proper generic types
- `readonly_default: true` → Immutable response types
- `named_exports: true` → No default exports
