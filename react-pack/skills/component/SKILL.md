---
name: craft-component
description: Scaffold a React component with TypeScript types, tests, and proper patterns.
---

# /craft component - React Component Scaffolding

Generate a React component following best practices.

## Usage

```
/craft component <ComponentName>
/craft component Button
/craft component UserProfile --with-hook
```

## Generated Structure

```
src/presentation/components/{Name}/
├── {Name}.tsx
├── {Name}.test.tsx
├── index.ts
└── {Name}.types.ts (if complex)
```

## Generated Code

### Component

```tsx
import { forwardRef, type ComponentPropsWithoutRef } from 'react';
import { cn } from '@/lib/cn';

export interface {Name}Props extends ComponentPropsWithoutRef<'div'> {
  /** Description of prop */
  variant?: 'default' | 'primary' | 'secondary';
  /** Another prop */
  size?: 'sm' | 'md' | 'lg';
}

export const {Name} = forwardRef<HTMLDivElement, {Name}Props>(
  ({ className, variant = 'default', size = 'md', children, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn(
          'base-styles',
          {
            'variant-default': variant === 'default',
            'variant-primary': variant === 'primary',
            'size-sm': size === 'sm',
            'size-md': size === 'md',
            'size-lg': size === 'lg',
          },
          className
        )}
        {...props}
      >
        {children}
      </div>
    );
  }
);

{Name}.displayName = '{Name}';
```

### Test

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { {Name} } from './{Name}';

describe('{Name}', () => {
  it('renders children', () => {
    render(<{Name}>Content</{Name}>);
    expect(screen.getByText('Content')).toBeInTheDocument();
  });

  it('applies variant class', () => {
    render(<{Name} variant="primary">Content</{Name}>);
    expect(screen.getByText('Content')).toHaveClass('variant-primary');
  });

  it('forwards ref', () => {
    const ref = { current: null };
    render(<{Name} ref={ref}>Content</{Name}>);
    expect(ref.current).toBeInstanceOf(HTMLDivElement);
  });

  it('spreads additional props', () => {
    render(<{Name} data-testid="custom">Content</{Name}>);
    expect(screen.getByTestId('custom')).toBeInTheDocument();
  });
});
```

### Index Export

```tsx
export { {Name} } from './{Name}';
export type { {Name}Props } from './{Name}';
```

## Rules Applied

From `.craft-config.yml`:

- `no_any: true` → Proper TypeScript types
- `readonly_default: true` → Props are readonly
- `named_exports: true` → No default exports
