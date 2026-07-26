---
model: sonnet
description: "Interactive setup and onboarding. Use on first run, when changing stack/packs, or when healthcheck reports config issues."
effort: medium
disable-model-invocation: true
---

# /craftsman:setup - Configuration Wizard

## Outcome Contract

- **Outcome**: a configuration derived from what the repository actually is, with only the undeterminable parts asked.
- **Done when**: the inferred conventions were shown before being written, .craft-config.yml is valid against the schema, and healthcheck reports no config error.
- **Evidence**: the conventions analysis output, the written config, and the healthcheck result.

## Modes

| Command | Description |
|---------|-------------|
| `/craftsman:setup` | Full interactive setup (default) |
| `/craftsman:setup --quick` | Zero-question auto-setup with smart defaults |
| `/craftsman:setup --refresh` | Regenerate observed artifacts (conventions skill, codemap) |
| `/craftsman:setup --global` | Workshop profile: asked once per machine, inherited by every project |

---

## Setup by Observation (ADR-0022)

Every mode (including `--quick`) ends with the observation step. The repository answers most setup questions itself; only ask the user what observation cannot determine (strictness preference, pack opt-ins).

1. Run the conventions analyzer and SHOW the user what was inferred before writing anything:
   ```bash
   bash ~/.claude/craftsman-conventions.sh analyze
   ```
2. On confirmation (automatic in `--quick` and `--refresh`), generate the project conventions skill:
   ```bash
   bash ~/.claude/craftsman-conventions.sh generate "$PWD/.claude/skills"
   ```
   This writes `.claude/skills/project-conventions/SKILL.md` (`user-invocable: false`, loaded as background knowledge, shareable via git, freely editable).
3. Warm the codemap cache (review skills inject it as live context):
   ```bash
   bash ~/.claude/craftsman-codemap.sh >/dev/null
   ```

Regeneration is always explicit (`--refresh`), never silent: the generated file records its generation date and inputs.

---

## Workshop Profile (`--global`)

Asked once per machine, then never again. It records how this developer usually works, not what the current project is. The answers are written to `~/.claude/.craft-config.yml` and every project inherits them through the 3-level config (global, then project, then directory).

Two questions, no more:

1. **Which stack(s) do you usually work in?** Propose what is already installed on the machine, and map the answer to packs.
2. **Which quality tools do you like in each stack?** Propose the community standards from the tooling detector catalog:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/hooks/lib/tooling_detect.py" "$PWD" --json
   ```

   The detector reports both what is declared here and what it suggests per stack (linters, architecture checkers, test runners, and the security section: secret scanners, dependency audit). For the workshop profile only the suggestion catalog matters, not this repository.

Record the answers under a `preferred_tools:` key:

```yaml
preferred_tools:
  php: ["PHPStan", "Deptrac", "PHPUnit"]
  javascript: ["ESLint", "Vitest"]
  security: ["Gitleaks"]
```

**Nothing is ever installed (ADR-0019).** A preference is a proposal that project init will offer later. Say this out loud when you write the profile so nobody expects a `composer require` or an `npm install` to have run.

---

## Situational Init (default project flow)

The default flow when `/craftsman:setup` runs inside a project. Observe first, then ask at most four short questions. Never ask what the repository has already answered.

### Step A: Observe

```bash
bash ~/.claude/craftsman-conventions.sh signals
```

It prints one JSON line:

```json
{"existing_project": true, "commit_count": 412, "has_tests": true, "has_ci": false, "legacy_signal": true}
```

Read it as: `existing_project` becomes true past 20 commits, `legacy_signal` is true when an existing project has no tests or no CI. These are prefills, not decisions. The user still confirms.

### Step B: Confirm (4 questions maximum)

One `AskUserQuestion` call, every answer prefilled from the signals. Wording matters: these questions are read by people who have never heard of a ratchet, a baseline, or a doctrine. No jargon, no rule codes, no acronyms. Ask exactly these four and nothing else:

| Question | Prefilled from | What it decides |
|---|---|---|
| Existing project or a new one? | `existing_project` | how the baseline is taken |
| Prototype or heading to production? | `legacy_signal`, `has_tests` | strictness: `moderate` or `strict` |
| Solo or team? | `has_ci` | whether a CI template and a doctrine export are proposed |
| Maximum help or maximum autonomy? | nothing, ask plainly | `guided: true` or `guided: false` |

Offer plain answers, never internal vocabulary:

- Question 1: "It already exists" / "I am starting it right now"
- Question 2: "It is a prototype, I am exploring" / "It is going to production"
- Question 3: "I work alone on it" / "We are several on it"
- Question 4: "Explain every blocked change to me" / "Just block, stay short"

Mapping, applied silently:

| Answer | Effect |
|---|---|
| Already exists | photograph the current state as the baseline |
| Starting right now | baseline starts empty, zero tolerance from the first file |
| Prototype | `strictness: moderate` |
| Going to production | `strictness: strict` |
| Alone | no CI proposal |
| Several | propose `craftsman-ci init` (pipeline template) and `craftsman-ci export` (shareable doctrine) |
| Explain every blocked change | `guided: true` |
| Just block, stay short | `guided: false` |

With `guided: true`, every quality gate block gains a plain-language paragraph explaining why the rule exists and where to read more. Turn it off later by flipping the key.

### Step C: Show the derived config before writing it

Same contract as the rest of this skill: display what was inferred, wait for confirmation, then write. The displayed block must include the two keys the four questions produced:

```yaml
strictness: "strict"
guided: true
```

### Step D: Bootstrap the structural baseline

The baseline is the photograph of the code as it is today. It is what lets the plugin demand better without punishing anyone for debt they inherited.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/lib/ratchet.py" init src --baseline .craftsman-baseline.json
```

Pass the source paths the project actually uses (`src`, `app`, `lib`, `packages/*/src`). The command prints how many files it recorded.

- **New project**: the baseline is empty, so the very first file is already held to the full standard. Zero tolerance costs nothing when there is nothing to fix.
- **Existing project**: the current state is photographed as is. Nothing that already exists is reported as a violation. Only a file that gets structurally worse than its photograph is blocked, and improving one updates its entry. Legacy is never punished for debt it already had.

Then tell the user, explicitly:

```
.craftsman-baseline.json must be committed. It is the shared reference:
without it in git, CI and your teammates measure against a different photograph.
```

### Step E: `--quick` skips the questions

`--quick` bypasses the four questions entirely. It keeps the observed defaults (existing project detection, strict strictness, `guided: false`) and still runs Step D, so a quick setup ends with a valid `.craftsman-baseline.json` like any other.

---

## Quick Mode (`--quick`)

When `$ARGUMENTS` contains `--quick`, skip ALL interactive questions and auto-generate configuration:

### Process

1. **Detect stack** using Glob tool:
   - `Glob("composer.json")` → PHP detected
   - `Glob("package.json")` → Node detected
   - Both → fullstack

2. **Extract user name** from git:
   - Run `git config user.name` via Bash tool
   - Fallback: `"Developer"` if not configured

3. **Auto-select packs:**
   - PHP detected → `symfony: true`
   - Node detected → `react: true`
   - Always → `core: true`
   - If both detected → both enabled

4. **Generate config** with smart defaults:

Use the `Write` tool to create `~/.claude/.craft-config.yml`:

```yaml
# AI Craftsman Superpowers Configuration
# Generated by /craftsman:setup --quick
# Re-run /craftsman:setup for full customization

version: "1.0"

profile:
  name: "{git_user_name}"
  disc_type: ""
  biases:
    - acceleration
    - scope_creep
    - over_optimization
    - dispersion

packs:
  core: true
  symfony: {auto_detected}
  react: {auto_detected}
  ai-ml: false

stack:
  php_version: "8.4"
  symfony_version: "7.4"
  node_version: "22"
  react_version: "19"

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

5. **Display summary** (no questions asked):

```
Quick Setup Complete!

  Name: {name} (from git config)
  Stack: {detected_stack}
  Strictness: strict (default)
  Biases: all enabled
  Packs: {auto_selected_packs}

Config saved to ~/.claude/.craft-config.yml
Run /craftsman:setup for full customization (DISC profile, pack versions, etc.)
```

### Guard: Existing Config

If `~/.claude/.craft-config.yml` OR `$PWD/.craft-config.yml` already exists:

```
Config already exists at {path}. Quick setup skipped.
Use /craftsman:setup --quick --force to overwrite, or /craftsman:setup for interactive reconfiguration.
```

Exit without changes unless `--force` is also present in `$ARGUMENTS`.

---

You are the **AI Craftsman setup assistant**. Your role is to guide the user through initial configuration and onboarding.

## Welcome (First-time users)

If no `.craft-config.yml` exists in `$PWD` or `~/.claude/`:

```
Welcome to AI Craftsman Superpowers!

You now have a Senior Craftsman methodology baked into your Claude Code.

Here's what's included:
- 15 core skills (DDD, TDD, debugging, planning, scaffolding...)
- 5 core agents + pack-specific specialists
- Real-time code quality hooks with pack-based validators
- Quality metrics dashboard
- Team collaboration system
```

## Pre-check

### Auto-Detection

Before anything else, detect the project stack and available tooling:

Use the **Glob** tool to detect the project stack and available tooling:
- `Glob("composer.json")` → if exists, PHP_DETECTED=true
- `Glob("package.json")` → if exists, NODE_DETECTED=true
- `Glob("vendor/bin/phpstan")` → if exists, PHPSTAN=available, else missing
- `Glob("vendor/bin/deptrac")` → if exists, DEPTRAC=available, else missing

Use the **Bash** tool with simple commands to check CLI tools:
- `command -v npx` → if found, NPX=available, else missing

### Analysis Tools Check

Based on detection results, suggest any missing quality tools before setup continues:

- PHPStan missing → "Consider installing: `composer require --dev phpstan/phpstan`"
- ESLint not configured → "Consider installing: `npm install --save-dev eslint`"
- Deptrac missing (PHP project) → "Consider installing: `composer require --dev qossmic/deptrac`"

Display detected tools so the user knows what's available.

### Pack Auto-Selection

Pre-select packs based on detection (user can override in Step 4):

- PHP detected → pre-select Symfony Pack
- Node detected → pre-select React Pack
- Both detected → pre-select both, display confirmation prompt
- Neither → Core only, no auto-selection

### Existing Config Check

Check if configuration already exists:

Use the **Read** tool to read `~/.claude/.craft-config.yml`. If the file does not exist, treat as CONFIG_NOT_FOUND.

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

Detect available packs and their descriptions:

Use the **Glob** tool: `Glob("packs/*/pack.yml")`. For each found file, use the **Read** tool to read it and extract the `description:` field. Display each pack as `- **<pack-name>**: <description>`. If no packs found, say "No packs found."

Pre-select packs based on auto-detection from Pre-check (user can adjust):
- PHP detected → **Symfony Pack** auto-selected
- Node detected → **React Pack** auto-selected
- **AI-ML Pack** → Always available (supports all stacks)

Use `AskUserQuestion` with `multiSelect: true` to confirm pack selection.

**Question 4 - Technology packs:**
- **Symfony Pack** - PHP/Symfony/DDD patterns - _auto-selected if PHP detected_
- **React Pack** - React/TypeScript patterns - _auto-selected if Node detected_
- **AI-ML Pack** - AI/ML patterns (RAG, MLOps, agent design)

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
  ai-ml: {true/false}

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
  AI-ML: {Enabled/Disabled}

Available Commands:

Core (20 skills, always available):
  /craftsman:challenge - Architecture review
  /craftsman:ci        - CI/CD integration
  /craftsman:debug     - Systematic debugging
  /craftsman:design    - DDD design with challenge phases
  /craftsman:git       - Safe git workflow
  /craftsman:metrics   - Quality metrics dashboard
  /craftsman:parallel  - Parallel execution
  /craftsman:plan      - Structured planning
  /craftsman:refactor  - Systematic refactoring
  /craftsman:scaffold  - Unified scaffolding
  /craftsman:setup     - Configuration wizard (re-run anytime)
  /craftsman:spec      - Specification-first (TDD)
  /craftsman:team      - Assemble agent teams
  /craftsman:test      - Pragmatic testing
  /craftsman:verify    - Evidence-based verification

{if symfony enabled}
Symfony Pack:
  /craftsman:scaffold [entity|usecase]  - Scaffold DDD patterns
{/if}

{if react enabled}
React Pack:
  /craftsman:scaffold [component|hook]  - Scaffold React patterns
{/if}

{if ai-ml enabled}
AI-ML Pack:
  /craftsman:rag          - Design RAG pipeline
  /craftsman:mlops        - MLOps audit
  /craftsman:agent-design - Agent 3P pattern
{/if}

Happy crafting!
```

## Important Notes

- Always use `AskUserQuestion` for interactive collection
- Use `Write` tool to create the config file
- Validate YAML syntax before writing
- If reconfiguring, preserve any custom `paths` or `rules` the user may have added manually
