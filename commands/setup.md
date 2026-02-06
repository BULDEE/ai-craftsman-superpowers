---
description: Interactive setup wizard for AI Craftsman Superpowers. Configure your profile, select packs, and generate ~/.claude/.craft-config.yml.
---

# /craftsman:setup - Configuration Wizard

You are the **AI Craftsman setup assistant**. Your role is to guide the user through initial configuration.

## Pre-check

First, check if configuration already exists:

```bash
cat ~/.claude/.craft-config.yml 2>/dev/null
```

- If file exists: Show current config and ask "Do you want to reconfigure? [y/N]"
- If file doesn't exist: Proceed with full setup

## Setup Process

### Step 1: Welcome

Display:

```
Welcome to AI Craftsman Superpowers!

Let's configure your craftsman profile.
Your config will be saved to ~/.claude/.craft-config.yml
```

### Step 2: Profile Information

Use `AskUserQuestion` to collect:

**Question 1 - Name:**
Ask for the user's name (free text via "Other" option).

**Question 2 - DISC Profile Method:**
Present these options:
- **I know my DISC** - Direct selection
- **Mini-test (4 questions)** - Quick assessment
- **Skip this step** - Configure later

---

#### If "I know my DISC" selected:

Present direct choice:
- **DI** - Dominant-Influential: Direct + Enthusiastic
- **D** - Dominant: Direct, results-focused, decisive
- **I** - Influential: Enthusiastic, collaborative, optimistic
- **C** - Conscientious: Analytical, detail-oriented, systematic
- Other (for S, DC, IS, SC combinations)

---

#### If "Mini-test" selected:

Run the 4-question DISC assessment:

**Q1 - Problem Solving:**
```
When facing a technical problem, you prefer to:
```
- **A) Act fast** - Adjust along the way
- **B) Analyze first** - Understand before acting

**Q2 - Meetings:**
```
In meetings, you prefer to:
```
- **A) Get to the point** - Decide quickly
- **B) Build consensus** - Let everyone speak

**Q3 - Giving feedback:**
```
When a colleague makes a mistake, you:
```
- **A) Tell them directly** - What went wrong
- **B) Choose your words carefully** - Take time to formulate

**Q4 - Receiving feedback:**
```
You prefer feedback that is:
```
- **A) Direct and factual** - Even if it stings
- **B) Constructive** - Encouraging

**Scoring Algorithm:**

| Q1 | Q2 | Q3 | Q4 | Result |
|----|----|----|----|----|
| A | A | A | A | **D** (Dominant) |
| A | A | A | B | **DI** |
| A | A | B | A | **DC** |
| A | A | B | B | **DI** |
| A | B | A | A | **DI** |
| A | B | A | B | **I** (Influential) |
| A | B | B | A | **DC** |
| A | B | B | B | **I** |
| B | A | A | A | **DC** |
| B | A | A | B | **C** (Conscientious) |
| B | A | B | A | **C** |
| B | A | B | B | **SC** |
| B | B | A | A | **IS** |
| B | B | A | B | **I** |
| B | B | B | A | **SC** |
| B | B | B | B | **S** (Steady) |

After scoring, display:
```
Based on your answers, your DISC profile is: {result}

{description of the profile}

This helps me adapt my communication style to work better with you.
```

**Profile Descriptions:**
- **D (Dominant)**: You like getting straight to the point, making quick decisions, and seeing concrete results.
- **I (Influential)**: You enjoy collaboration, enthusiasm, and getting others excited about your ideas.
- **S (Steady)**: You value stability, listening, and harmonious teamwork.
- **C (Conscientious)**: You prioritize precision, thorough analysis, and high standards.
- **DI**: Direct AND enthusiastic - you want results while bringing the team along.
- **DC**: Direct AND analytical - you want results backed by solid facts.
- **IS**: Collaborative AND steady - you create a positive and reliable work environment.
- **SC**: Steady AND analytical - you combine patience with methodical rigor.

---

#### If "Skip" selected:

Set `disc_type: ""` (empty) and continue. Display:
```
No problem! You can set your DISC profile later by running /craftsman:setup again.
```

### Step 3: Bias Protection

Use `AskUserQuestion` with `multiSelect: true`:

**Question 3 - Biases to monitor:**
- **Acceleration** - Warns when rushing to code before understanding
- **Scope Creep** - Warns when adding features beyond original scope
- **Over-optimization** - Warns when abstracting prematurely
- **Dispersion** - Warns when jumping between topics

Default recommendation: All enabled.

### Step 4: Pack Selection

Use `AskUserQuestion` with `multiSelect: true`:

**Question 4 - Technology packs:**
- **Symfony Pack** - PHP/Symfony/DDD patterns (/craftsman:entity, /craftsman:usecase)
- **React Pack** - React/TypeScript patterns (/craftsman:component, /craftsman:hook)
- **AI Pack** - AI/ML patterns (/craftsman:rag, /craftsman:mlops, /craftsman:agent-design)

Note: Core pack is always enabled.

### Step 5: Stack Versions (conditional)

If Symfony Pack selected, ask:
- PHP version (default: 8.4)
- Symfony version (default: 7.4)

If React Pack selected, ask:
- Node version (default: 22)
- React version (default: 19)

### Step 6: Generate Configuration

Create the configuration file at `~/.claude/.craft-config.yml`:

```yaml
# AI Craftsman Superpowers Configuration
# Generated by /craftsman:setup
# Re-run /craftsman:setup to modify

version: "1.0"

profile:
  name: "{collected_name}"
  disc_type: "{collected_disc}"
  biases:
    - {bias1}
    - {bias2}

packs:
  core: true
  symfony: {true/false}
  react: {true/false}
  ai: {true/false}

stack:
  php_version: "{version}"
  symfony_version: "{version}"
  node_version: "{version}"
  react_version: "{version}"

rules:
  php:
    final_classes: true
    private_constructors: true
    no_setters: true
    strict_types: true
    no_datetime_direct: true
    no_empty_catch: true
  typescript:
    no_any: true
    readonly_default: true
    branded_types: true
    named_exports: true
    no_non_null_assertion: true
  git:
    conventional_commits: true
    no_ai_attribution: true

paths:
  domain: "src/Domain"
  application: "src/Application"
  infrastructure: "src/Infrastructure"
  presentation: "src/Presentation"
```

Use the `Write` tool to create this file.

### Step 7: Display Summary

After saving, display:

```
Configuration saved to ~/.claude/.craft-config.yml

Your Profile:
  Name: {name}
  DISC Type: {disc_type}
  Bias Protection: {biases}

Enabled Packs:
  Core: Always enabled
  Symfony: {Enabled/Disabled}
  React: {Enabled/Disabled}
  AI: {Enabled/Disabled}

Available Commands:

Core (always available):
  /craftsman:design    - DDD design with challenge phases
  /craftsman:debug     - Systematic debugging
  /craftsman:plan      - Structured planning
  /craftsman:challenge - Architecture review
  /craftsman:verify    - Evidence-based verification
  /craftsman:spec      - Specification-first (TDD)
  /craftsman:refactor  - Systematic refactoring
  /craftsman:test      - Pragmatic testing
  /craftsman:git       - Safe git workflow
  /craftsman:parallel  - Parallel execution

{if symfony enabled}
Symfony Pack:
  /craftsman:entity   - Scaffold DDD entity
  /craftsman:usecase  - Scaffold use case
{/if}

{if react enabled}
React Pack:
  /craftsman:component - Scaffold React component
  /craftsman:hook      - Scaffold TanStack Query hook
{/if}

{if ai enabled}
AI Pack:
  /craftsman:rag          - Design RAG pipeline
  /craftsman:mlops        - MLOps audit
  /craftsman:agent-design - Agent 3P pattern
  /craftsman:source-verify - Verify AI capabilities
{/if}

Happy crafting!
```

## Important Notes

- Always use `AskUserQuestion` for interactive collection
- Use `Write` tool to create the config file
- Validate YAML syntax before writing
- If reconfiguring, preserve any custom `paths` or `rules` the user may have added manually
