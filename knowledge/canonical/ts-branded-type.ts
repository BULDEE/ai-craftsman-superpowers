/**
 * CANONICAL EXAMPLE: Branded Types (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - Brand symbol for type safety (MUST)
 * - Factory function with validation (MUST)
 * - Type guard for runtime checks (SHOULD)
 * - Immutable by design (MUST)
 */

// ============================================================
// Brand Symbol (shared)
// ============================================================

declare const __brand: unique symbol;

type Brand<T, B extends string> = T & { readonly [__brand]: B };

// ============================================================
// UserId
// ============================================================

export type UserId = Brand<string, 'UserId'>;

export function createUserId(value: string): UserId {
  if (!isValidUuid(value)) {
    throw new Error(`Invalid UserId: ${value}`);
  }
  return value as UserId;
}

export function isUserId(value: unknown): value is UserId {
  return typeof value === 'string' && isValidUuid(value);
}

// ============================================================
// Email
// ============================================================

export type Email = Brand<string, 'Email'>;

const EMAIL_REGEX = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

export function createEmail(value: string): Email {
  const normalized = value.toLowerCase().trim();
  if (!EMAIL_REGEX.test(normalized)) {
    throw new Error(`Invalid Email: ${value}`);
  }
  return normalized as Email;
}

export function isEmail(value: unknown): value is Email {
  return typeof value === 'string' && EMAIL_REGEX.test(value);
}

// ============================================================
// Money (cents-based)
// ============================================================

export type Money = Brand<number, 'Money'>;

export function createMoney(cents: number): Money {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new Error(`Invalid Money: ${cents}`);
  }
  return cents as Money;
}

export function addMoney(a: Money, b: Money): Money {
  return (a + b) as Money;
}

export function subtractMoney(a: Money, b: Money): Money {
  const result = a - b;
  if (result < 0) {
    throw new Error('Insufficient funds');
  }
  return result as Money;
}

export function formatMoney(cents: Money, currency = 'EUR'): string {
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency,
  }).format(cents / 100);
}

// ============================================================
// Percentage (0-100)
// ============================================================

export type Percentage = Brand<number, 'Percentage'>;

export function createPercentage(value: number): Percentage {
  if (value < 0 || value > 100) {
    throw new Error(`Invalid Percentage: ${value}`);
  }
  return value as Percentage;
}

// ============================================================
// Utilities
// ============================================================

function isValidUuid(value: string): boolean {
  const UUID_REGEX =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-7][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return UUID_REGEX.test(value);
}

// ============================================================
// Usage Example
// ============================================================

interface User {
  readonly id: UserId;
  readonly email: Email;
  readonly balance: Money;
}

function createUser(rawEmail: string): User {
  return {
    id: createUserId(crypto.randomUUID()),
    email: createEmail(rawEmail),
    balance: createMoney(0),
  };
}
