/**
 * CANONICAL EXAMPLE: React Server Component (v1.0)
 *
 * Source: https://react.dev/reference/rsc/server-components
 *         https://react.dev/reference/rsc/use-server
 *         https://react.dev/reference/react/use
 *
 * Key characteristics:
 * - async function is valid and recommended for Server Components
 * - No 'use server' directive on the component itself (that's for Server Actions only)
 * - Cannot use useState, useEffect, event handlers, or browser APIs
 * - use() hook preferred on client for reading promises (no useContext needed)
 * - Server Actions marked with 'use server' inside async functions
 * - <form action={fn}> with Server Actions is real React 19, not Next.js-specific
 * - Wrap with <Suspense> for streaming; wrap with <ErrorBoundary> for errors
 */

import { Suspense } from 'react';
import { use } from 'react';

import type { ReactNode } from 'react';
import type { User, UserId } from '@/domain/entities/User';
import { userRepository } from '@/infrastructure/repositories/userRepository';

// ============================================================
// Server Component — async function, direct data access
// Source: https://react.dev/reference/rsc/server-components
// ============================================================

// NO directive on Server Components. 'use server' is ONLY for Server Actions.
// CAN: async/await, filesystem, DB access, pass data/JSX to Client Components
// CANNOT: useState, useReducer, useEffect, onClick, onChange, browser APIs

export async function UserProfilePage({
  userId,
}: {
  readonly userId: UserId;
}): Promise<ReactNode> {
  // Direct backend access — no API layer needed
  const user = await userRepository.findById(userId);

  if (!user) {
    return <UserNotFound />;
  }

  // Pass serializable data to Client Components
  // CANNOT pass functions or class instances across the boundary
  return (
    <main className="container py-8">
      <h1 className="text-3xl font-bold">{user.name}</h1>
      <Suspense fallback={<ActivityFeedSkeleton />}>
        {/* Async child component — streams independently */}
        <UserActivityFeed userId={user.id} />
      </Suspense>
      {/* Server Action form — real React 19, not Next.js-specific */}
      <UpdateNameForm userId={user.id} currentName={user.name} />
    </main>
  );
}

// ============================================================
// Async Server Component for streaming with Suspense
// Source: https://react.dev/reference/react/Suspense
// ============================================================

async function UserActivityFeed({
  userId,
}: {
  readonly userId: UserId;
}): Promise<ReactNode> {
  // This component streams independently — parent shows faster
  const activities = await userRepository.findRecentActivity(userId);

  return (
    <ul className="space-y-2">
      {activities.map((activity) => (
        <li key={activity.id}>{activity.description}</li>
      ))}
    </ul>
  );
}

// ============================================================
// Server Action — 'use server' directive inside async function
// Source: https://react.dev/reference/rsc/use-server
// ============================================================

// <form action={fn}> is real React 19 — works without JavaScript (progressive enhancement)
// Automatic FormData as first argument
// MUST call 'use server' at the very top of the async function body

function UpdateNameForm({
  userId,
  currentName,
}: {
  readonly userId: UserId;
  readonly currentName: string;
}): ReactNode {
  async function updateName(formData: FormData): Promise<void> {
    'use server';
    // Treat all arguments as untrusted — validate and authorize
    const name = formData.get('name');
    if (typeof name !== 'string' || name.trim().length === 0) return;
    await userRepository.updateName(userId, name.trim());
  }

  return (
    <form action={updateName} className="mt-4 space-y-2">
      <input
        type="text"
        name="name"
        defaultValue={currentName}
        className="border rounded px-2 py-1"
      />
      <button type="submit">Update name</button>
    </form>
  );
}

// ============================================================
// Client Component — uses use() to read a Promise passed from Server
// Source: https://react.dev/reference/react/use
// ============================================================

// 'use client' marks the boundary. Everything imported here runs on the client.
// use() can be called in conditionals and loops unlike useContext().
// Promise MUST be created in a Server Component for stability across re-renders.

// In a real file this would be in its own file with 'use client' at the top.
// Shown here for reference only.
//
// 'use client';
// import { use } from 'react';
//
// interface UserNameDisplayProps {
//   readonly userPromise: Promise<User>;
// }
//
// export function UserNameDisplay({ userPromise }: UserNameDisplayProps): ReactNode {
//   // use() suspends until the promise resolves — wrap parent in <Suspense>
//   // use() throws on rejection — wrap in <ErrorBoundary>
//   // use() CAN be called inside conditionals (unlike useContext)
//   const user = use(userPromise);
//   return <span>{user.name}</span>;
// }

// ============================================================
// Constraints Summary
// ============================================================

/*
  SERVER COMPONENTS
  ✅ async function
  ✅ await in render
  ✅ Direct DB / filesystem access
  ✅ Pass serializable data and JSX to Client Components
  ✅ <form action={serverAction}>
  ❌ useState, useReducer
  ❌ useEffect, useLayoutEffect
  ❌ onClick, onChange (event handlers)
  ❌ window, document, localStorage
  ❌ No 'use server' directive on the component itself

  SERVER ACTIONS (functions marked with 'use server')
  ✅ async functions only
  ✅ <form action={fn}> — progressive enhancement
  ✅ Callable from Client Components via startTransition
  ✅ Automatic FormData argument for forms
  ❌ React elements / JSX as return values
  ❌ Regular functions or class instances as arguments/returns
  ❌ Called outside a Transition from Client Components

  use() HOOK ON CLIENT
  ✅ Reads Promises and Context values
  ✅ Can be called inside conditionals and loops
  ✅ Replaces useContext() — more flexible
  ❌ Cannot be called in try-catch blocks
  ❌ Cannot be called in event handlers
*/

function UserNotFound(): ReactNode {
  return <p className="text-muted-foreground">User not found.</p>;
}

function ActivityFeedSkeleton(): ReactNode {
  return <div className="animate-pulse h-24 bg-muted rounded" />;
}
