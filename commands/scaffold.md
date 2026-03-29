---
description: Unified scaffolder for all pack types (entity, usecase, component, hook, api-resource). Types loaded from active packs.
effort: medium
---

# /craftsman:scaffold - Unified Scaffolder

## Project Context

!`cat .craft-config.yml 2>/dev/null || echo "No config found. Run /craftsman:setup first."`

## Available Types

Detect available scaffold types from loaded packs:

!`for pack_dir in packs/*/; do [ -f "$pack_dir/pack.yml" ] || continue; name=$(basename "$pack_dir"); types=$(grep -A5 "scaffold_types:" "$pack_dir/pack.yml" | grep -oE '"[^"]+"' | tr -d '"' | tr '\n' ', ' | sed 's/,$//'); [ -n "$types" ] && echo "**${name}:** ${types}"; done 2>/dev/null || echo "No scaffold types available. Check pack configuration."`

## Usage

```
/craftsman:scaffold <type> [name]
```

Examples:
```
/craftsman:scaffold entity Order
/craftsman:scaffold usecase CreateOrder
/craftsman:scaffold component UserProfile
/craftsman:scaffold hook useOrders
```

## Iron Law

Before generating ANY code, you MUST load and read the canonical example for the requested type.

| Type | Canonical Example |
|------|------------------|
| entity | `packs/symfony/knowledge/canonical/php-entity.php` |
| usecase | `packs/symfony/knowledge/canonical/php-usecase.php` |
| component | `packs/react/knowledge/canonical/ts-react-component.tsx` |
| hook | `packs/react/knowledge/canonical/ts-tanstack-hook.ts` |

## Process

### Phase 1: Context

1. Detect project stack from `.craft-config.yml`
2. Validate the requested type exists in an active pack
3. Load the canonical example for the type

### Phase 2: Generate

Based on the type argument:

**Symfony types (entity, usecase):**
- Load the canonical example file from `packs/symfony/knowledge/canonical/`
- Follow the exact patterns: `final class`, private constructor, factory methods, Value Objects
- Generate: Entity/UseCase + tests + migration if needed

**React types (component, hook):**
- Load the canonical example file from `packs/react/knowledge/canonical/`
- Follow the exact patterns: named exports, branded types, TanStack Query integration
- Generate: Component/Hook + tests + Storybook if component

### Phase 3: Verify

After generation:
- Run `/craftsman:verify` to ensure code passes all hook validators
- Confirm naming conventions match project standards
