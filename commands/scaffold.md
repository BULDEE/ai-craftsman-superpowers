---
description: Unified scaffolder for all pack types (entity, usecase, component, hook, api-resource, pack). Types loaded from active packs.
effort: medium
---

# /craftsman:scaffold - Unified Scaffolder

## Project Context

Use the **Read** tool to read `.craft-config.yml`. If the file does not exist, say "No config found. Run /craftsman:setup first."

## Available Types

Detect available scaffold types from loaded packs:

Use the **Glob** tool: `Glob("packs/*/pack.yml")`. For each found file, use the **Read** tool to read it and extract the `scaffold_types:` list. Display each pack's types as `**<pack-name>:** <type1>, <type2>, ...`. If no scaffold types found, say "No scaffold types available. Check pack configuration."

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
/craftsman:scaffold pack my-go-pack
```

## Iron Law

Before generating ANY code, you MUST load and read the canonical example for the requested type.

| Type | Canonical Example |
|------|------------------|
| entity | `packs/symfony/knowledge/canonical/php-entity.php` |
| usecase | `packs/symfony/knowledge/canonical/php-usecase.php` |
| component | `packs/react/knowledge/canonical/ts-react-component.tsx` |
| hook | `packs/react/knowledge/canonical/ts-tanstack-hook.ts` |
| api-resource | `packs/symfony/knowledge/canonical/php-state-provider.php` |
| pack | *(generates new pack from convention — no canonical needed)* |

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

**Meta type (pack):**
- Generate the full pack directory structure under `packs/<name>/`
- Create `pack.yml` with the name, version 1.0.0, description placeholder, and stack `["*"]`
- Create a starter validator in `hooks/<name>-validator.sh` with a `pack_validate_<name>()` function
- Create empty directories: `agents/`, `knowledge/canonical/`, `commands/scaffold-types/`, `static-analysis/`, `templates/`
- Create a test file at `tests/packs/test-<name>.sh` with basic structure checks
- Run `scripts/validate-pack.sh packs/<name>/` to verify the generated pack
- Print next steps: "Pack created at `packs/<name>/`. Edit pack.yml to configure stack compatibility and add your rules."

### Phase 3: Verify

After generation:
- Run `/craftsman:verify` to ensure code passes all hook validators
- Confirm naming conventions match project standards
