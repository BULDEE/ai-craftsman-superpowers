---
name: component
description: Scaffold React component with TypeScript, tests, and Storybook. Use when creating React/TypeScript components.
---

# /craftsman:component - React Component Scaffolding

Scaffold a complete React component with TypeScript, tests, and optional Storybook.

## Generated Structure

```
src/
└── components/
    └── {ComponentName}/
        ├── {ComponentName}.tsx
        ├── {ComponentName}.test.tsx
        ├── {ComponentName}.stories.tsx (optional)
        └── index.ts
```

## Component Template

```tsx
import { type ReactNode } from 'react';

export interface {ComponentName}Props {
  readonly children?: ReactNode;
  readonly className?: string;
  // Add other props with explicit types
}

export function {ComponentName}({
  children,
  className,
}: {ComponentName}Props): ReactNode {
  return (
    <div className={className}>
      {children}
    </div>
  );
}
```

## Test Template

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { {ComponentName} } from './{ComponentName}';

describe('{ComponentName}', () => {
  it('renders children', () => {
    render(<{ComponentName}>Test content</{ComponentName}>);

    expect(screen.getByText('Test content')).toBeInTheDocument();
  });

  it('applies className', () => {
    render(<{ComponentName} className="custom-class">Content</{ComponentName}>);

    expect(screen.getByText('Content').parentElement).toHaveClass('custom-class');
  });

  // Add more behavioral tests
});
```

## Storybook Template

```tsx
import type { Meta, StoryObj } from '@storybook/react';
import { {ComponentName} } from './{ComponentName}';

const meta: Meta<typeof {ComponentName}> = {
  title: 'Components/{ComponentName}',
  component: {ComponentName},
  tags: ['autodocs'],
  argTypes: {
    // Define controls for props
  },
};

export default meta;
type Story = StoryObj<typeof {ComponentName}>;

export const Default: Story = {
  args: {
    children: 'Default content',
  },
};

export const WithCustomClass: Story = {
  args: {
    children: 'Styled content',
    className: 'bg-blue-500 text-white p-4',
  },
};
```

## Index Export

```tsx
export { {ComponentName} } from './{ComponentName}';
export type { {ComponentName}Props } from './{ComponentName}';
```

## Rules Enforced

| Rule | Enforcement |
|------|-------------|
| No `any` types | Explicit types or `unknown` |
| `readonly` props | All interface properties |
| Named exports | No default exports |
| Branded types | For domain primitives |
| Function components | No class components |

## TypeScript Patterns

### Branded Types for Props

```tsx
// types/branded.ts
declare const brand: unique symbol;
type Brand<T, B> = T & { readonly [brand]: B };

export type UserId = Brand<string, 'UserId'>;
export type Email = Brand<string, 'Email'>;

// Usage in component
interface UserCardProps {
  readonly userId: UserId;
  readonly email: Email;
}
```

### Discriminated Unions

```tsx
type ButtonVariant = 'primary' | 'secondary' | 'danger';

interface ButtonProps {
  readonly variant: ButtonVariant;
  readonly disabled?: boolean;
  readonly onClick: () => void;
}
```

### Children Patterns

```tsx
// Specific children type
interface CardProps {
  readonly header: ReactNode;
  readonly children: ReactNode;
  readonly footer?: ReactNode;
}

// Render props
interface DataFetcherProps<T> {
  readonly url: string;
  readonly children: (data: T) => ReactNode;
}
```

## Process

### Step 0: MANDATORY - Load Canonical Examples

**BEFORE generating any code, you MUST use the Read tool to load:**

```
Read: knowledge/canonical/ts-react-component.tsx
Read: knowledge/canonical/ts-branded-type.ts
```

This ensures generated code matches project standards exactly.

### Steps

1. **Load canonical examples** (Step 0 above - NON-NEGOTIABLE)
2. **Ask for component name and purpose**
3. **Identify required props**
4. **Generate component file**
5. **Generate test file**
6. **Generate Storybook (if requested)**
7. **Generate index export**
8. **Verify**

```bash
npm run typecheck
npm test -- --filter={ComponentName}
```

## Anti-Patterns to Avoid

| Anti-Pattern | Why Bad | Correct Approach |
|--------------|---------|------------------|
| Prop drilling | Tight coupling | Context or composition |
| `any` types | No type safety | Proper types or `unknown` |
| Default exports | Harder refactoring | Named exports only |
| Non-null assertion `!` | Hides bugs | Handle null explicitly |
| Inline styles | Inconsistent | Tailwind or CSS modules |
