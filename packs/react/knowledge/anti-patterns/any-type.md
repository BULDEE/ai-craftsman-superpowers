# Anti-Pattern: Using `any` Type

## What It Is

Using TypeScript's `any` type instead of proper types.

## Why It's Bad

- Defeats the purpose of TypeScript
- Hides bugs that would be caught at compile time
- Makes refactoring dangerous
- No IDE autocompletion

## Example

### BAD: Using `any`

```typescript
// BAD: No type safety
function processData(data: any): any {
  return data.items.map((item: any) => item.name);
}

// BAD: Casting to any to "fix" type errors
const result = (response as any).data.users;

// BAD: any in generics
function fetchData<T = any>(url: string): Promise<T> {
  return fetch(url).then(r => r.json());
}

// BAD: any in component props
interface Props {
  data: any;
  onSubmit: (values: any) => void;
}
```

### GOOD: Proper Types

```typescript
// GOOD: Explicit types
interface Item {
  readonly id: string;
  readonly name: string;
}

interface DataResponse {
  readonly items: readonly Item[];
}

function processData(data: DataResponse): string[] {
  return data.items.map((item) => item.name);
}

// GOOD: Use unknown for truly unknown data
function parseJson(text: string): unknown {
  return JSON.parse(text);
}

// GOOD: Type guard for unknown
function isUser(value: unknown): value is User {
  return (
    typeof value === 'object' &&
    value !== null &&
    'id' in value &&
    'email' in value
  );
}

// GOOD: Generic with constraint
function fetchData<T extends object>(url: string): Promise<T> {
  return fetch(url).then(r => r.json());
}

// GOOD: Explicit prop types
interface FormProps {
  readonly data: UserFormData;
  readonly onSubmit: (values: UserFormData) => void;
}
```

## When `unknown` is Better

```typescript
// For external data (API, localStorage, user input)
function handleApiResponse(response: unknown): User | null {
  if (!isUser(response)) {
    console.error('Invalid user data');
    return null;
  }
  return response;
}

// For catch blocks
try {
  // ...
} catch (error: unknown) {
  if (error instanceof Error) {
    console.error(error.message);
  }
}
```

## How to Fix Existing `any`

1. Enable `noImplicitAny` in tsconfig
2. Search for `: any` in codebase
3. Create interfaces for data structures
4. Use type guards for runtime checks
5. Use generics with constraints

## ESLint Rule

```json
{
  "@typescript-eslint/no-explicit-any": "error"
}
```
