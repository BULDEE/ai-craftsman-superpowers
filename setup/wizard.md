---
name: setup
description: Interactive setup wizard for AI Craftsman Superpowers - runs on first launch
---

# AI Craftsman Superpowers - Setup Wizard

## Overview

This wizard configures your craftsman profile. It runs automatically on first launch.

## Process

### Step 1: Welcome

```
Welcome to AI Craftsman Superpowers!

Let's configure your craftsman profile. This takes about 2 minutes.
Your config will be saved to ~/.claude/.craft-config.yml
```

### Step 2: Profile Information

Ask the user:

**Question 1:** "What's your name?"
- Free text input
- Used for personalized interactions

**Question 2:** "What's your DISC profile? (How you work best)"

Present options:
| Type | Description |
|------|-------------|
| D | **Dominant** - Direct, results-focused, decisive |
| I | **Influential** - Enthusiastic, collaborative, optimistic |
| S | **Steady** - Patient, supportive, consistent |
| C | **Conscientious** - Analytical, detail-oriented, systematic |
| DI | **Dominant-Influential** - Direct + Enthusiastic (recommended for senior devs) |
| DC | **Dominant-Conscientious** - Direct + Analytical |
| IS | **Influential-Steady** - Collaborative + Supportive |
| SC | **Steady-Conscientious** - Patient + Analytical |

### Step 3: Bias Protection

**Question 3:** "Which cognitive biases should I help guard against?"

Present checkboxes:
- [ ] **Acceleration** - Tendency to code before understanding ("Let's just build it")
- [ ] **Dispersion** - Jumping between topics without finishing
- [ ] **Scope creep** - Adding features not in original scope ("Let's also add...")
- [ ] **Over-optimization** - Premature abstraction ("Let's make it configurable...")

Default: All checked

### Step 4: Pack Selection

**Question 4:** "Which technology packs do you want to enable?"

Present checkboxes:
- [x] **Core** - Methodology skills (always enabled, cannot disable)
- [ ] **Symfony Pack** - PHP/Symfony/DDD patterns
- [ ] **React Pack** - React/TypeScript patterns

### Step 5: Stack Versions (if packs selected)

If Symfony Pack enabled:
- "PHP version?" (default: 8.4)
- "Symfony version?" (default: 7.4)

If React Pack enabled:
- "Node version?" (default: 22)
- "React version?" (default: 19)

### Step 6: Confirmation

Show summary:

```
Configuration Summary:

Profile:
  Name: {name}
  DISC Type: {disc_type}
  Bias Protection: {biases}

Packs:
  Core: Enabled (always)
  Symfony: {enabled/disabled}
  React: {enabled/disabled}

Save this configuration? [Y/n]
```

### Step 7: Save & Complete

1. Generate `~/.claude/.craft-config.yml` from template
2. Display success message:

```
Configuration saved to ~/.claude/.craft-config.yml

Available skills:
- /craftsman:design    - DDD design with challenge
- /craftsman:debug     - Systematic investigation
- /craftsman:spec      - Specification-first (TDD)
- /craftsman:plan      - Structured planning
- /craftsman:challenge - Architecture review
- /craftsman:refactor  - Systematic refactoring
- /craftsman:test      - Pragmatic testing
- /craftsman:git       - Safe git workflow

{if symfony}
- /craftsman:entity  - Scaffold DDD entity
- /craftsman:usecase - Scaffold use case
{/if}

{if react}
- /craftsman:component - Scaffold React component
- /craftsman:hook      - Scaffold query hook
{/if}

Type /craftsman: for the full command reference.

Happy crafting!
```

## Re-running Setup

User can re-run setup anytime with:
```
/craftsman:setup
```

This will show current config and allow modifications.
