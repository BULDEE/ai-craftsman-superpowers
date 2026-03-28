# Anti-Pattern: Barrel Imports (index.ts re-exports)

## Problem

Barrel files (`index.ts`) that re-export from many modules prevent tree-shaking and increase bundle size. Every import from a barrel may pull all exports into the bundle, even unused ones.

## Bad

```typescript
// src/components/index.ts — barrel file
export { Button } from './Button/Button';
export { Card } from './Card/Card';
export { Modal } from './Modal/Modal';
export { Table } from './Table/Table';
// ... 50 more components

// Usage — may import ALL components even if only Button is needed
import { Button } from '@/components';
```

## Good

```typescript
// Direct imports — bundler only includes what is referenced
import { Button } from '@/components/Button/Button';
import { Card } from '@/components/Card/Card';
```

## Why It Matters

- Barrel files defeat tree-shaking in many bundlers (especially CommonJS output)
- Every `import { X } from '@/barrel'` may force evaluation of all exports
- Circular dependency risk increases as barrel files grow
- Build times increase proportionally with barrel size
- Initial page load grows silently as teams add to the barrel

## Exceptions

Barrel files are acceptable for:
- Public package APIs (when you control what consumers import)
- Small, stable groups (3-5 exports max)
- When your bundler (e.g. Vite with ESM) guarantees tree-shaking

## Rule

> Prefer direct imports. Only use barrels for deliberate public API surfaces, never as a convenience layer.
