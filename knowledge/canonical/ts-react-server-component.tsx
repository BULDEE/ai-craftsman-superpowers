// CANONICAL EXAMPLE: React Server Component with data fetching (v1.0)
//
// This is THE reference for React 19 Server Components.
// No "use client" directive — runs on the server by default.
//
// Key characteristics:
// - async function (MUST for server-side data fetching)
// - No useState/useEffect (server components are stateless)
// - Suspense boundaries for streaming (SHOULD)
// - Skeleton fallback during loading (SHOULD)
// - readonly props interface (MUST per TS rules)

import { Suspense } from 'react';

interface UserPageProps {
  readonly params: { readonly userId: string };
}

interface User {
  readonly id: string;
  readonly name: string;
  readonly email: string;
}

async function fetchUser(userId: string): Promise<User> {
  // Note: Caching strategy is framework-specific.
  // Next.js: { cache: 'no-store' } or { next: { revalidate: 60 } }
  // Remix: Use loader with headers
  // Generic React: Use HTTP cache headers on the API
  const response = await fetch(`/api/users/${userId}`);
  if (!response.ok) {
    throw new Error(`Failed to fetch user: ${response.status}`);
  }
  // Production: validate with zod schema — UserSchema.parse(data)
  const data: unknown = await response.json();
  return data as User;
}

// Server Component — async, no hooks, no client state
export async function UserPage({ params }: UserPageProps) {
  const user = await fetchUser(params.userId);

  return (
    <main>
      <UserProfile user={user} />
      <Suspense fallback={<UserActivitySkeleton />}>
        {/* UserActivity fetches its own data independently — enables streaming */}
        <UserActivity userId={params.userId} />
      </Suspense>
    </main>
  );
}

// Sub-components declared separately (never inline — see inline-components anti-pattern)
function UserProfile({ user }: { readonly user: User }) {
  return (
    <section>
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </section>
  );
}

function UserActivitySkeleton() {
  return <div aria-busy="true" aria-label="Loading activity..." />;
}

interface ActivityItem {
  readonly id: string;
  readonly label: string;
}

async function UserActivity({ userId }: { readonly userId: string }) {
  // Independent fetch — will stream separately from UserProfile
  const response = await fetch(`/api/users/${userId}/activity`);
  // Production: validate with zod schema
  const activity = (await response.json()) as readonly ActivityItem[];
  return <ul>{activity.map(item => <li key={item.id}>{item.label}</li>)}</ul>;
}
