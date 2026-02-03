/**
 * CANONICAL BRANDED TYPE PATTERN
 *
 * Branded types create compile-time type safety for domain primitives.
 * They prevent mixing up values that are structurally identical
 * but semantically different (e.g., UserId vs OrderId).
 */

// ============================================
// BRAND SYMBOL
// ============================================

declare const __brand: unique symbol;

type Brand<T, B> = T & { readonly [__brand]: B };

// ============================================
// DOMAIN PRIMITIVES
// ============================================

export type UserId = Brand<string, 'UserId'>;
export type OrderId = Brand<string, 'OrderId'>;
export type ProductId = Brand<string, 'ProductId'>;
export type Email = Brand<string, 'Email'>;
export type Money = Brand<number, 'Money'>;

// ============================================
// FACTORY FUNCTIONS
// ============================================

export function UserId(value: string): UserId {
  // Optional: Add validation
  if (!value || value.trim() === '') {
    throw new Error('UserId cannot be empty');
  }
  return value as UserId;
}

export function OrderId(value: string): OrderId {
  return value as OrderId;
}

export function Email(value: string): Email {
  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(value)) {
    throw new Error(`Invalid email: ${value}`);
  }
  return value.toLowerCase() as Email;
}

export function Money(cents: number): Money {
  if (cents < 0) {
    throw new Error('Money cannot be negative');
  }
  if (!Number.isInteger(cents)) {
    throw new Error('Money must be in cents (integer)');
  }
  return cents as Money;
}

// ============================================
// USAGE EXAMPLES
// ============================================

interface User {
  readonly id: UserId;
  readonly email: Email;
  readonly name: string;
}

interface Order {
  readonly id: OrderId;
  readonly userId: UserId;
  readonly total: Money;
}

// Compile-time safety:
function getUser(id: UserId): User | null {
  // ...
  return null;
}

function getOrder(id: OrderId): Order | null {
  // ...
  return null;
}

// This WORKS:
const userId = UserId('user-123');
const user = getUser(userId);

// This FAILS at compile time:
// const order = getOrder(userId);
// Error: Argument of type 'UserId' is not assignable to parameter of type 'OrderId'

// ============================================
// BRANDED TYPES WITH VALIDATION
// ============================================

export type PositiveNumber = Brand<number, 'PositiveNumber'>;
export type NonEmptyString = Brand<string, 'NonEmptyString'>;
export type Percentage = Brand<number, 'Percentage'>;

export function PositiveNumber(value: number): PositiveNumber {
  if (value <= 0) {
    throw new Error('Value must be positive');
  }
  return value as PositiveNumber;
}

export function NonEmptyString(value: string): NonEmptyString {
  const trimmed = value.trim();
  if (trimmed === '') {
    throw new Error('String cannot be empty');
  }
  return trimmed as NonEmptyString;
}

export function Percentage(value: number): Percentage {
  if (value < 0 || value > 100) {
    throw new Error('Percentage must be between 0 and 100');
  }
  return value as Percentage;
}

// ============================================
// TYPE GUARDS
// ============================================

export function isUserId(value: unknown): value is UserId {
  return typeof value === 'string' && value.startsWith('user-');
}

export function isEmail(value: unknown): value is Email {
  if (typeof value !== 'string') return false;
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(value);
}

// ============================================
// ZOID INTEGRATION
// ============================================

import { z } from 'zod';

export const userIdSchema = z.string().transform((val) => UserId(val));
export const emailSchema = z.string().email().transform((val) => Email(val));
export const moneySchema = z.number().int().min(0).transform((val) => Money(val));

// Usage with API responses:
const userSchema = z.object({
  id: userIdSchema,
  email: emailSchema,
  name: z.string(),
});

type UserFromApi = z.infer<typeof userSchema>;
// UserFromApi = { id: UserId; email: Email; name: string }
