/**
 * CANONICAL EXAMPLE: React Component (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - Props interface with readonly (MUST)
 * - Named export only (MUST)
 * - No business logic in component (MUST)
 * - Composition over prop drilling (SHOULD)
 * - Error boundaries consideration (SHOULD)
 */

import { type ReactNode, memo, useCallback } from 'react';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { formatMoney } from '@/domain/valueObjects/Money';
import { useUser, useUpdateUser } from '@/hooks/useUser';
import type { UserId } from '@/domain/valueObjects';

// ============================================================
// Props Interface (readonly, explicit)
// ============================================================

interface UserCardProps {
  readonly userId: UserId;
  readonly onSelect?: (userId: UserId) => void;
  readonly className?: string;
}

// ============================================================
// Component (named export, memo for performance)
// ============================================================

export const UserCard = memo(function UserCard({
  userId,
  onSelect,
  className,
}: UserCardProps): ReactNode {
  const { data: user, isLoading, error } = useUser(userId);
  const updateUser = useUpdateUser();

  const handleActivate = useCallback(() => {
    updateUser.mutate({ id: userId, status: 'active' });
  }, [userId, updateUser]);

  const handleSelect = useCallback(() => {
    onSelect?.(userId);
  }, [userId, onSelect]);

  if (isLoading) {
    return <UserCardSkeleton className={className} />;
  }

  if (error) {
    return <UserCardError error={error} className={className} />;
  }

  if (!user) {
    return null;
  }

  return (
    <Card className={className} onClick={handleSelect}>
      <CardHeader>
        <CardTitle>{user.name}</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-2">
          <div>
            <dt className="text-sm text-muted-foreground">Email</dt>
            <dd>{user.email}</dd>
          </div>
          <div>
            <dt className="text-sm text-muted-foreground">Balance</dt>
            <dd>{formatMoney(user.balance)}</dd>
          </div>
          <div>
            <dt className="text-sm text-muted-foreground">Status</dt>
            <dd>
              <StatusBadge status={user.status} />
            </dd>
          </div>
        </dl>

        {user.status === 'pending' && (
          <Button
            onClick={handleActivate}
            disabled={updateUser.isPending}
            className="mt-4 w-full"
          >
            {updateUser.isPending ? 'Activating...' : 'Activate'}
          </Button>
        )}
      </CardContent>
    </Card>
  );
});

// ============================================================
// Sub-components (colocated, focused)
// ============================================================

interface StatusBadgeProps {
  readonly status: 'active' | 'pending' | 'inactive';
}

function StatusBadge({ status }: StatusBadgeProps): ReactNode {
  const styles = {
    active: 'bg-green-100 text-green-800',
    pending: 'bg-yellow-100 text-yellow-800',
    inactive: 'bg-gray-100 text-gray-800',
  };

  return (
    <span className={`rounded-full px-2 py-1 text-xs font-medium ${styles[status]}`}>
      {status}
    </span>
  );
}

function UserCardSkeleton({ className }: { readonly className?: string }): ReactNode {
  return (
    <Card className={className}>
      <CardHeader>
        <Skeleton className="h-6 w-32" />
      </CardHeader>
      <CardContent className="space-y-2">
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-4 w-16" />
      </CardContent>
    </Card>
  );
}

interface UserCardErrorProps {
  readonly error: Error;
  readonly className?: string;
}

function UserCardError({ error, className }: UserCardErrorProps): ReactNode {
  return (
    <Card className={`border-destructive ${className}`}>
      <CardContent className="py-4">
        <p className="text-sm text-destructive">
          Failed to load user: {error.message}
        </p>
      </CardContent>
    </Card>
  );
}

// ============================================================
// Page Component Pattern
// ============================================================

interface UserListPageProps {
  readonly initialFilters?: UserFilters;
}

interface UserFilters {
  readonly status?: 'active' | 'pending' | 'inactive';
  readonly search?: string;
}

export function UserListPage({ initialFilters }: UserListPageProps): ReactNode {
  const [filters, setFilters] = useState<UserFilters>(initialFilters ?? {});
  const { data, isLoading } = useUsers(filters);

  const handleFilterChange = useCallback((newFilters: Partial<UserFilters>) => {
    setFilters((prev) => ({ ...prev, ...newFilters }));
  }, []);

  return (
    <div className="container py-8">
      <header className="mb-8">
        <h1 className="text-3xl font-bold">Users</h1>
      </header>

      <UserFiltersBar filters={filters} onChange={handleFilterChange} />

      {isLoading ? (
        <UserListSkeleton />
      ) : (
        <UserList users={data?.data ?? []} />
      )}
    </div>
  );
}
