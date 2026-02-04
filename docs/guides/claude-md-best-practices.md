# CLAUDE.md Best Practices with AI Craftsman Superpowers

This guide explains how to structure your CLAUDE.md files to work harmoniously with the AI Craftsman Superpowers plugin.

## The Priority Hierarchy

Claude Code reads instructions from multiple sources in a specific priority order:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     INSTRUCTION PRIORITY                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   1. EXPLICIT USER INSTRUCTION          ← Highest priority           │
│      (what you type in the prompt)                                   │
│                       ↓                                              │
│   2. PROJECT CLAUDE.md                                               │
│      ./CLAUDE.md (root of current project)                           │
│      ./.claude/CLAUDE.md                                             │
│      ./.claude/*.md (additional files)                               │
│                       ↓                                              │
│   3. PLUGIN INSTRUCTIONS                                             │
│      Skills (SKILL.md), Hooks, Agents                                │
│      Knowledge base (patterns, principles)                           │
│                       ↓                                              │
│   4. GLOBAL CLAUDE.md                   ← Lowest priority            │
│      ~/.claude/CLAUDE.md                                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Rule**: Higher priority always overrides lower priority.

## What Goes Where?

### Global CLAUDE.md (`~/.claude/CLAUDE.md`)

**Purpose**: Personal preferences that apply to ALL your projects.

**DO include**:
- Your identity/persona preferences
- Communication style (DISC profile)
- Personal biases to protect against
- Stack versions you commonly use
- Global conflict resolution rules

**DON'T include** (handled by plugin):
- Code rules (final class, strict_types, no any) → Plugin hooks enforce these
- Design patterns → Plugin knowledge base
- Skill routing → Plugin auto-triggers
- SOLID/DDD principles → Plugin knowledge base

### Example Global CLAUDE.md (Compatible with Plugin)

```markdown
# Claude Code Instructions

<version>v4.0 | Compatible with ai-craftsman-superpowers</version>

<!-- ============================================
     PERSONAL SECTION - Unique to you
     ============================================ -->

<partner id="your-name">
  <disc-profile>
    <!-- Your DISC personality type -->
    DI (Dominant-Influent)
    D-HIGH: Quick decisions, intolerance for inaction
    I-HIGH: Vision, energy, rallies others
  </disc-profile>

  <bias-protection>
    <!-- Only biases NOT covered by plugin's bias-detector.sh -->
    <!-- Plugin already handles: acceleration, scope-creep, over-optimize -->
    <bias id="dispersion" trigger="Topic change mid-task"
          action="STOP → Finish X first. Note Y for later." />
    <bias id="assumption" trigger="It doesn't exist|Impossible"
          action="STOP → Verify official sources first." />
  </bias-protection>

  <communication>
    DO: Direct, clear trade-offs, challenge with arguments
    DONT: Beat around the bush, agree without conviction
  </communication>
</partner>

<persona>
  <response-calibration>
    <certainty high=">90%">Direct statements</certainty>
    <certainty medium="70-90%">"I recommend X because Y"</certainty>
    <certainty low="<70%">"~X% confidence. Options: A, B, C."</certainty>
  </response-calibration>

  <pushback>
    <challenge-when>YAGNI violation, premature optimization, missing tests</challenge-when>
    <yield-when>User insists after one pushback with reasoning</yield-when>
  </pushback>
</persona>

<!-- ============================================
     STACK SECTION - Your default versions
     ============================================ -->

<stack>
  Backend: Symfony 7.4, PHP 8.4, PostgreSQL, Redis
  Frontend: React 19, TypeScript 5.x, Tailwind, shadcn/ui
  AI/ML: LangChain, Python 3.12, pgvector
  DevOps: Docker, GitHub Actions
</stack>

<!-- ============================================
     RULES SECTION - Guide before writing
     Plugin hooks verify AFTER writing
     ============================================ -->

<rules>
  <!-- These guide Claude BEFORE generating code -->
  <!-- Plugin's post-write-check.sh validates AFTER -->

  <category name="PHP">
    <must>ALL classes MUST be final</must>
    <must>private __construct() + public static create() factory</must>
    <must>declare(strict_types=1) in every file</must>
    <must>NO setters - use behavioral methods</must>
  </category>

  <category name="TypeScript">
    <must>NO any - use proper types or unknown</must>
    <must>readonly by default</must>
    <must>Named exports only</must>
  </category>

  <category name="Git">
    <must>Conventional Commits: type(scope): description</must>
    <must>NEVER Co-Authored-By or AI attribution</must>
  </category>
</rules>

<!-- ============================================
     CONFLICT RESOLUTION - Priority rules
     ============================================ -->

<conflict-resolution>
  <priority order="1">Security over Performance over Readability</priority>
  <priority order="2">Project CLAUDE.md over Global CLAUDE.md</priority>
  <priority order="3">Explicit user instruction over Any CLAUDE.md</priority>
</conflict-resolution>

<!-- ============================================
     REMOVED - Now handled by plugin
     ============================================ -->
<!--
DON'T ADD THESE (plugin handles them):
- <skill-routing> → Skills auto-activate via SKILL.md frontmatter
- <self-check> → Plugin's post-write-check.sh hook
- <references> to knowledge paths → Plugin's knowledge/ directory
- <session-behavior> → Plugin's session-init skill
- acceleration/scope-creep/over-optimize biases → Plugin's bias-detector.sh
- SOLID/DDD/patterns explanations → Plugin's knowledge base
-->
```

---

## Project CLAUDE.md (`./CLAUDE.md`)

**Purpose**: Project-specific instructions that override global settings.

### Structure

```
my-project/
├── CLAUDE.md              ← Main project instructions
├── .claude/
│   ├── CLAUDE.md          ← Alternative location (same priority)
│   ├── api-guidelines.md  ← Additional context files
│   ├── database-schema.md
│   └── team-conventions.md
└── src/
    └── Domain/
        └── .claude/
            └── CLAUDE.md  ← Subdirectory-specific (for monorepos)
```

### Example Project CLAUDE.md

```markdown
# Project: E-Commerce Platform

## Overview

This is a Symfony 7.4 e-commerce platform with React frontend.

## Project-Specific Rules

<!-- Override or extend global rules -->

<rules>
  <!-- This project uses UUIDs, not auto-increment -->
  <must>All entity IDs use Symfony UUIDs (Uuid::v7)</must>

  <!-- Project-specific naming -->
  <must>Commands end with "Command" (CreateOrderCommand)</must>
  <must>Handlers end with "Handler" (CreateOrderHandler)</must>
  <must>Events end with "Event" (OrderCreatedEvent)</must>
</rules>

## Architecture

```
src/
├── Domain/           # Entities, Value Objects, Events
├── Application/      # Use Cases (Command/Handler)
├── Infrastructure/   # Repositories, External Services
└── Presentation/     # Controllers, API Resources
```

## Key Entities

- `Order` - Aggregate root for orders
- `Customer` - User who places orders
- `Product` - Items in catalog
- `Cart` - Shopping cart (not persisted)

## External Services

- Stripe for payments (sandbox mode in dev)
- SendGrid for emails
- AWS S3 for file storage

## Database

PostgreSQL 16 with:
- pgvector extension for product search
- Read replicas for heavy queries

## Testing

```bash
make test          # All tests
make test-unit     # Unit only
make test-e2e      # E2E with Cypress
```

## Environment

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection |
| `STRIPE_KEY` | Stripe API key |
| `MAILER_DSN` | SendGrid DSN |

## Don't Touch

- `src/Legacy/` - Old code, scheduled for removal Q2
- `migrations/Version202401*` - Historical, don't modify
```

---

## How It All Works Together

### The Complete Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CLAUDE CODE CONTEXT LOADING                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. SESSION START                                                    │
│     └── Plugin hook: session-init skill loads                        │
│         └── Shows available /craftsman:* skills                      │
│                                                                      │
│  2. USER PROMPT RECEIVED                                             │
│     └── Plugin hook: bias-detector.sh runs                           │
│         └── Warns if acceleration/scope-creep detected               │
│                                                                      │
│  3. CONTEXT ASSEMBLY                                                 │
│     ├── ~/.claude/CLAUDE.md (global)                                 │
│     ├── ./CLAUDE.md (project)                                        │
│     ├── ./.claude/*.md (additional)                                  │
│     └── Plugin knowledge base (if skill invoked)                     │
│                                                                      │
│  4. SKILL EXECUTION (e.g., /craftsman:entity)                        │
│     ├── Load SKILL.md instructions                                   │
│     ├── MANDATORY: Read canonical examples                           │
│     │   └── knowledge/canonical/php-entity.php                       │
│     │   └── knowledge/canonical/php-value-object.php                 │
│     └── Generate code following patterns                             │
│                                                                      │
│  5. CODE WRITTEN                                                     │
│     └── Plugin hook: post-write-check.sh runs                        │
│         └── Validates: strict_types, final class, no setters         │
│         └── Warns if violations detected                             │
│                                                                      │
│  6. VERIFICATION (optional: /craftsman:verify)                       │
│     └── Runs actual tests and quality gates                          │
│     └── Shows evidence, not assumptions                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Knowledge Base Integration

The plugin's knowledge base provides patterns and examples:

```
plugins/craftsman/knowledge/
├── canonical/                    # Golden standard examples
│   ├── php-entity.php           # DDD Entity template
│   ├── php-value-object.php     # Value Object template
│   ├── php-usecase.php          # Use Case template
│   ├── php-repository.php       # Repository template
│   ├── ts-react-component.tsx   # React component template
│   ├── ts-branded-type.ts       # Branded types template
│   └── ts-tanstack-hook.ts      # TanStack Query hook template
│
├── anti-patterns/               # What NOT to do
│   ├── php-anemic-domain.md
│   ├── php-god-service.md
│   ├── ts-any-abuse.md
│   └── ts-prop-drilling.md
│
├── patterns.md                  # Design patterns catalog
├── principles.md                # SOLID, KISS, DRY, YAGNI
├── event-driven.md             # Event sourcing patterns
├── microservices-patterns.md   # Microservices architecture
└── stack-specifics.md          # PHP/TS specific rules
```

**How skills use knowledge**:

```
/craftsman:entity invoked
        ↓
Step 0: MANDATORY - Read canonicals
        ↓
┌─────────────────────────────────┐
│  Read: canonical/php-entity.php │
│  Read: canonical/php-value-object.php │
│  Read: anti-patterns/php-anemic-domain.md │
└─────────────────────────────────┘
        ↓
Generate code matching canonical patterns
```

---

## Common Mistakes to Avoid

### ❌ Mistake 1: Duplicating Plugin Rules in Global CLAUDE.md

```markdown
<!-- DON'T DO THIS - Plugin already handles it -->
<references>
  <canonical path="~/.claude/knowledge/canonical/">...</canonical>
  <patterns path="~/.claude/knowledge/patterns.md">...</patterns>
</references>

<skill-routing>
  <auto pattern="bug|error" skill="/debug" />
</skill-routing>
```

**Why**: Plugin has its own knowledge base and auto-triggers.

### ❌ Mistake 2: Contradicting Plugin Patterns

```markdown
<!-- DON'T DO THIS - Contradicts plugin's DDD approach -->
<rules>
  <must>Use public setters for all properties</must>
  <must>No need for Value Objects, use primitives</must>
</rules>
```

**Why**: Plugin enforces behavioral methods and Value Objects.

### ❌ Mistake 3: Over-specifying in Global

```markdown
<!-- DON'T DO THIS - Too project-specific for global -->
<rules>
  <must>All entities use auto-increment IDs</must>
  <must>Controllers return JSON only</must>
</rules>
```

**Why**: These are project-specific; put them in project CLAUDE.md.

### ✅ Correct Approach

```markdown
<!-- Global: Personal preferences only -->
<partner>
  <communication>DO: Be direct, challenge assumptions</communication>
</partner>

<!-- Project: Project-specific rules -->
<rules>
  <must>This project uses UUID v7 for all IDs</must>
</rules>
```

---

## Quick Reference Card

| What | Where | Example |
|------|-------|---------|
| Your personality/DISC | Global | `<disc-profile>DI</disc-profile>` |
| Communication style | Global | `<communication>DO: Be direct</communication>` |
| Personal biases | Global | `<bias id="dispersion">...` |
| Default stack versions | Global | `<stack>Symfony 7.4, PHP 8.4</stack>` |
| Code rules (guide) | Global | `<must>final class</must>` |
| Code rules (enforce) | Plugin | `post-write-check.sh` |
| Design patterns | Plugin | `knowledge/patterns.md` |
| Canonical examples | Plugin | `knowledge/canonical/` |
| Skill definitions | Plugin | `skills/*/SKILL.md` |
| Project architecture | Project | `./CLAUDE.md` |
| Project-specific rules | Project | `./CLAUDE.md` |
| Domain context | Project | `./.claude/domain.md` |
| API documentation | Project | `./.claude/api.md` |

---

## Checklist: Is Your Setup Correct?

### Global CLAUDE.md (`~/.claude/CLAUDE.md`)

- [ ] Contains personal preferences (DISC, communication style)
- [ ] Contains personal biases (only those NOT in plugin)
- [ ] Contains default stack versions
- [ ] Contains code rules as guidance (not enforcement)
- [ ] Does NOT contain skill routing (plugin handles it)
- [ ] Does NOT contain knowledge paths (plugin has its own)
- [ ] Does NOT duplicate plugin patterns/principles

### Project CLAUDE.md (`./CLAUDE.md`)

- [ ] Contains project overview and purpose
- [ ] Contains project-specific architecture
- [ ] Contains key entities and their relationships
- [ ] Contains external services and integrations
- [ ] Contains environment variables reference
- [ ] Contains testing commands
- [ ] Contains "don't touch" warnings for legacy code

### Plugin Integration

- [ ] Plugin is installed: `/plugin` shows `craftsman@...`
- [ ] Hooks are enabled (bias-detector, post-write-check)
- [ ] Skills are accessible: `/craftsman:design`, etc.
- [ ] No conflicts between global rules and plugin

---

## Migration Guide

If you have an existing CLAUDE.md that conflicts with the plugin:

### Step 1: Identify Duplicates

```bash
# Check for knowledge paths (should not exist)
grep -n "~/.claude/knowledge" ~/.claude/CLAUDE.md

# Check for skill routing (should not exist)
grep -n "skill-routing" ~/.claude/CLAUDE.md

# Check for self-check (should not exist)
grep -n "self-check" ~/.claude/CLAUDE.md
```

### Step 2: Remove Duplicates

Remove these sections from global CLAUDE.md:
- `<references>` with knowledge paths
- `<skill-routing>`
- `<self-check>`
- `<session-behavior>` (unless custom)
- Biases already in plugin: acceleration, scope-creep, over-optimize

### Step 3: Verify

```bash
# Plugin should load without conflicts
claude
/craftsman:verify
```

---

## Summary

| Layer | Responsibility | Examples |
|-------|---------------|----------|
| **Global** | Personal preferences | DISC, communication, biases |
| **Plugin** | Methodology & enforcement | Skills, hooks, knowledge |
| **Project** | Project context | Architecture, entities, APIs |
| **Subdirectory** | Module-specific | Monorepo domain context |

**Golden Rule**: Let each layer do what it does best. Don't duplicate.
