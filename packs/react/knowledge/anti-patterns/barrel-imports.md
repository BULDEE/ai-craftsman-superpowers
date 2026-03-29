# Anti-Pattern: Barrel File Imports

Source: https://github.com/vercel-labs/agent-skills/blob/main/skills/react-best-practices/AGENTS.md (Rule 2.1)

## Problem

Barrel files (`index.ts` that re-export everything from a module) force the bundler to load **all** modules in the barrel, even when only one is used. This costs 200–800ms on initial load and significantly inflates bundle size.

```typescript
// ❌ BAD — forces loading of ALL exports from the barrel
import { Button, Card, Input, Table, Modal } from '@/components/ui';
import { formatDate, formatMoney, formatUser } from '@/domain/utils';
```

Even if only `Button` is used, the bundler must evaluate every file re-exported through `@/components/ui/index.ts`.

## Root Cause

Tree-shaking is unreliable with barrel files because:
- Side effects in any barrel module disable tree-shaking for the entire barrel
- Dynamic re-exports cannot be statically analyzed
- The bundler must speculatively load all modules to resolve the barrel

## Solution

Import directly from the source file.

```typescript
// ✅ GOOD — only the Button module is loaded
import { Button } from '@/components/ui/button';
import { formatDate } from '@/domain/utils/formatDate';
```

## When Barrels Are Acceptable

Barrels are acceptable only for **public package APIs** — the top-level `index.ts` of a published npm package that consumers import. They are NOT acceptable inside an application codebase.

## Detection

```bash
# Find barrel files
find src -name "index.ts" -exec grep -l "^export \* from" {} \;

# Find imports using barrels
grep -r "from '@/components/ui'" src --include="*.tsx"
```

## Impact

| Metric | Before | After |
|--------|--------|-------|
| Initial bundle parse | +200–800ms | baseline |
| Unused modules loaded | many | 0 |
| Tree-shaking effectiveness | poor | full |
