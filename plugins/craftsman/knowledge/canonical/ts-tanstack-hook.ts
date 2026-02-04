/**
 * CANONICAL EXAMPLE: TanStack Query Hooks (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - Typed query keys (MUST)
 * - Proper error handling (MUST)
 * - Optimistic updates for mutations (SHOULD)
 * - Cache invalidation strategy (MUST)
 * - No any types (MUST)
 */

import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseMutationResult,
  type UseQueryResult,
} from '@tanstack/react-query';

import type { User } from '@/domain/entities/User';
import type { UserId, Email } from '@/domain/valueObjects';
import { userApi } from '@/infrastructure/api/userApi';

// ============================================================
// Query Keys (typed and centralized)
// ============================================================

export const userKeys = {
  all: ['users'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: UserId) => [...userKeys.details(), id] as const,
};

// ============================================================
// Types
// ============================================================

interface UserFilters {
  readonly status?: 'active' | 'pending' | 'inactive';
  readonly search?: string;
  readonly page?: number;
  readonly limit?: number;
}

interface CreateUserInput {
  readonly email: string;
  readonly name: string;
}

interface UpdateUserInput {
  readonly id: UserId;
  readonly email?: string;
  readonly name?: string;
}

interface PaginatedResponse<T> {
  readonly data: readonly T[];
  readonly total: number;
  readonly page: number;
  readonly limit: number;
}

// ============================================================
// Query: Get User by ID
// ============================================================

export function useUser(id: UserId): UseQueryResult<User, Error> {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: () => userApi.getById(id),
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}

// ============================================================
// Query: List Users with Filters
// ============================================================

export function useUsers(
  filters: UserFilters = {}
): UseQueryResult<PaginatedResponse<User>, Error> {
  return useQuery({
    queryKey: userKeys.list(filters),
    queryFn: () => userApi.list(filters),
    staleTime: 30 * 1000, // 30 seconds for lists
  });
}

// ============================================================
// Mutation: Create User
// ============================================================

export function useCreateUser(): UseMutationResult<
  User,
  Error,
  CreateUserInput
> {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: CreateUserInput) => userApi.create(input),
    onSuccess: (newUser) => {
      // Add to cache
      queryClient.setQueryData(userKeys.detail(newUser.id), newUser);
      // Invalidate lists to refetch
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
  });
}

// ============================================================
// Mutation: Update User (with optimistic update)
// ============================================================

export function useUpdateUser(): UseMutationResult<
  User,
  Error,
  UpdateUserInput
> {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: UpdateUserInput) => userApi.update(input),

    onMutate: async (input) => {
      // Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: userKeys.detail(input.id) });

      // Snapshot previous value
      const previousUser = queryClient.getQueryData<User>(
        userKeys.detail(input.id)
      );

      // Optimistically update
      if (previousUser) {
        queryClient.setQueryData(userKeys.detail(input.id), {
          ...previousUser,
          ...input,
        });
      }

      return { previousUser };
    },

    onError: (_error, input, context) => {
      // Rollback on error
      if (context?.previousUser) {
        queryClient.setQueryData(
          userKeys.detail(input.id),
          context.previousUser
        );
      }
    },

    onSettled: (_data, _error, input) => {
      // Refetch to ensure consistency
      queryClient.invalidateQueries({ queryKey: userKeys.detail(input.id) });
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
  });
}

// ============================================================
// Mutation: Delete User
// ============================================================

export function useDeleteUser(): UseMutationResult<void, Error, UserId> {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: UserId) => userApi.delete(id),
    onSuccess: (_data, id) => {
      // Remove from cache
      queryClient.removeQueries({ queryKey: userKeys.detail(id) });
      // Invalidate lists
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
  });
}

// ============================================================
// Usage Example in Component
// ============================================================

/*
function UserProfile({ userId }: { userId: UserId }) {
  const { data: user, isLoading, error } = useUser(userId);
  const updateUser = useUpdateUser();

  if (isLoading) return <Skeleton />;
  if (error) return <ErrorMessage error={error} />;
  if (!user) return <NotFound />;

  const handleUpdate = (email: string) => {
    updateUser.mutate({ id: userId, email });
  };

  return (
    <UserCard
      user={user}
      onUpdate={handleUpdate}
      isUpdating={updateUser.isPending}
    />
  );
}
*/
