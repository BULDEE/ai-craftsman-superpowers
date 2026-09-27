---
model: sonnet
description: "Interactive setup and onboarding. Use on first run, when changing stack/packs, or when healthcheck reports config issues."
effort: medium
disable-model-invocation: true
---

# /craftsman:setup - Configuration Wizard


> The commands below call `craftsman-path`, which prints an absolute path
> inside this installation. The plugin's `bin/` is on PATH in the Claude Code
> Bash tool; on a host where it is not, call it by its full path
> (`<plugin root>/bin/craftsman-path`). Do not use `${CLAUDE_PLUGIN_ROOT}` in a
> skill body: a skill is text handed to a model, the host expands nothing there,
> and Claude Code does not export that variable to the Bash tool.

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
   bash "$(craftsman-path bin/craftsman-helper)" conventions analyze
   ```
2. On confirmation (automatic in `--quick` and `--refresh`), generate the project conventions skill:
   ```bash
   bash "$(craftsman-path bin/craftsman-helper)" conventions generate "$PWD/.claude/skills"   # Codex reads "$PWD/.agents/skills" instead
   ```
   This writes `.claude/skills/project-conventions/SKILL.md` (`.agents/skills/...` on Codex; `user-invocable: false`, loaded as background knowledge, shareable via git, freely editable).
3. Warm the codemap cache (review skills inject it as live context):
   ```bash
   bash "$(craftsman-path bin/craftsman-helper)" codemap >/dev/null
   ```

Regeneration is always explicit (`--refresh`), never silent: the generated file records its generation date and inputs.

---

## Workshop Profile (`--global`)

Asked once per machine, then never again. It records how this developer usually works, not what the current project is. The answers are written to `~/.claude/.craft-config.yml` and every project inherits them through the 3-level config (global, then project, then directory).

Two questions, no more:

1. **Which stack(s) do you usually work in?** Propose what is already installed on the machine, and map the answer to packs.
2. **Which quality tools do you like in each stack?** Propose the community standards from the tooling detector catalog:

   ```bash
   python3 "$(craftsman-path hooks/lib/tooling_detect.py)" "$PWD" --json
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
bash "$(craftsman-path bin/craftsman-helper)" conventions signals
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
| Existing project or a new one? | `existing_project` | how the baseline is taken, AND the strictness ceiling |
| Prototype or heading to production? | `legacy_signal`, `has_tests` | strictness, within that ceiling |
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
| Already exists | photograph the current state as the baseline, and cap strictness at `moderate` |
| Starting right now | baseline starts empty, zero tolerance from the first file |
| Prototype | `strictness: moderate` |
| Going to production, on a NEW project | `strictness: strict` |
| Going to production, on an EXISTING one | `strictness: moderate` |
| Alone | no CI proposal |
| Several | propose `craftsman-ci init` (pipeline template) and `craftsman-ci export` (shareable doctrine) |
| Explain every blocked change | `guided: true` |
| Just block, stay short | `guided: false` |

**Question 1 outranks question 2, and this is the single most important line in
the mapping.** It is enforced by `config_default_strictness` in
`hooks/lib/config.sh`, not by this table: a decision that opens or closes the
front door of the gate cannot depend on a model following prose. A codebase with three years of history is in production, so the
truthful answer to question 2 is "going to production", and mapping that
straight to `strict` selects the setting that refuses most of the repository on
the first edit. Measured on a real Symfony application, 400 files sampled: 98%
have no `declare(strict_types=1)` and 88% are not `final`.

`moderate` relaxes design and style, never a boundary and never security:
`LAYER*` and `SEC*` keep their declared severity under it, which is asserted in
`tests/core/test-rules-engine.sh`. What it stops doing is refusing an edit
because of a class declaration two hundred lines above the change.

That sentence was written here before it was true. `SEC*` was missing from the
carve-out, so this change would have made a hardcoded secret advisory on every
repository with history, justified by a claim in a document a model reads to
decide. It is true now because the engine was fixed and a test holds it.

The baseline is the other half of the same answer: `craftsman-ci baseline`
records what the repository already carries, so a recorded violation reports
without blocking while a new one still refuses the write. Step D runs it.

The mark lives in `.craftsman-baseline.json` at the repository root, and the
question "which mark answers for this file" is settled by the file's own
directory, never by where the shell happens to be: a pipeline running from a
package directory, and a hook fired with whatever working directory the editor
has, read the same mark. A repository nested inside another (a submodule, a
package that took its own mark) answers for its own files.

Taking the mark is also what buys `strict` back. An existing repository whose
debt has never been measured defaults to `moderate`, where only a boundary or a
secret blocks; once the mark is taken, the default is `strict` again, because
the debt `strict` would refuse is now recorded and reported without blocking.

Naming a rule in this repository's `.craft-rules.yml` outranks the mark:
`PHP001: block` blocks a recorded violation too, which is how a project takes
one rule back out of the debt once it has been cleaned up. The same line in the
global `~/.claude/.craft-config.yml` does not, because a preference held across
every repository on the machine is not a statement about this one.

The mark is taken once. A second `craftsman-ci baseline` is refused, and a
deliberate re-mark needs `--re-baseline --reason "..."` and says out loud which
files written since the first mark it absorbed.

Raising an existing project to `strict` is a deliberate later step, taken once
the debt is under a baseline, and it is one line in `.craft-config.yml`.

With `guided: true`, every quality gate block gains a plain-language paragraph explaining why the rule exists and where to read more. Turn it off later by flipping the key.

### Step C: Show the derived config before writing it

Same contract as the rest of this skill: display what was inferred, wait for confirmation, then write. What is displayed and written is the project file of [The configuration file (v4)](#the-configuration-file-v4), with the stack detected as that section says and the `strictness` and `guided` the four questions produced. Then validate it and read it back as that section says.

### Step D: Take the baseline

The baseline is the photograph of the code as it is today. It is what lets the plugin demand better without punishing anyone for debt they inherited.

```bash
bash "$(craftsman-path bin/craftsman-ci)" baseline src
```

Pass the source directories the project actually uses (`src`, `app`, `lib`, `packages/*/src`), from the repository root. This is the canonical mark, the one the hooks and CI read: it scans with the same validators and severities, records the rule violations each file already carries, and takes the structural photograph in the same `.craftsman-baseline.json`. `ratchet.py init` alone is not a substitute: it records the structure and no rule, so every inherited violation still blocks the first edit.

- **New project**: the baseline is empty, so the very first file is already held to the full standard. Zero tolerance costs nothing when there is nothing to fix.
- **Existing project**: every violation already there is recorded. From then on it is reported as a warning and no longer blocks; a new one, or one more of the same rule in the same file, still blocks. A file that gets structurally worse than its photograph is reported, and improving one updates its entry. Legacy is never punished for debt it already had.
- **Already taken**: the mark is taken once. When `.craftsman-baseline.json` exists the command refuses and exits 1; leave it as it is and tell the user. Re-taking it is their decision (`--re-baseline --reason "..."`), never a setup default.

Then tell the user, explicitly:

```
.craftsman-baseline.json must be committed. It is the shared reference:
without it in git, CI and your teammates measure against a different photograph.
```

### Step E: `--quick` skips the questions

`--quick` bypasses the four questions entirely. It keeps the observed defaults
and still runs Step D, so a quick setup ends with a valid
`.craftsman-baseline.json` like any other.

Its strictness follows the same rule as the questions, and it does not need to
be re-derived: `config_default_strictness` in `hooks/lib/config.sh` is the one
implementation, and `config_strictness` already falls back to it. The table
above documents what that function returns; it does not compute it.

---

## The configuration file (v4)

Every mode writes this one format, the one `schemas/craft-config.schema.json`
describes and `hooks/lib/config.sh` reads. The project file is
`$PWD/.craft-config.yml`: stack, strictness and guidance describe this
repository, not the machine.

```yaml
# .craft-config.yml, format v4 (schemas/craft-config.schema.json)
v: 4
stack: {stack}
strictness: {strictness}
guided: {guided}
```

- `{stack}`: `symfony` when only `composer.json` exists, `react` when only
  `package.json` exists, `fullstack` when both do, `other` when neither does.
  One word on the same line: the resolver reads a scalar.
- `{strictness}`: `strict`, `moderate` or `relaxed`, from the Step B mapping.
  `--quick` omits the line, and the plugin then derives it
  (`config_default_strictness`).
- `{guided}`: `true` or `false` (question 4). `--quick` writes `false`.

Never write `version:`, a `stack:` mapping of versions, a `packs:` mapping or
a `rules:` block of booleans: that is the format before v4. No consumer reads
the first three (every shipped pack loads on every stack and judges its own
file types), a `stack:` mapping leaves the resolver with no stack at all, and
`rules:` is read as rule-id overrides (`PHP001: warn`), never as switches.

The machine-wide keys live in `~/.claude/.craft-config.yml` and only the
machine owner sets them: `preferred_tools` (`--global`), `trust_project_tools`,
`hooks`, `packs: external`. A project file cannot grant them.

**Validate, then read it back.** A file that parses is not a file the plugin
reads as intended. Before saying setup is done, run the validator (schema,
resolver's own reader) and show the user the values the plugin will use:

```bash
bash -c 'source "$(craftsman-path hooks/lib/config.sh)"; config_validate .craft-config.yml && echo "stack=$(config_stack) strictness=$(config_strictness)"'
```

Any line it prints is a problem to fix before finishing; the healthcheck
reports the same problems as a config error.

**Migrating a pre-v4 file.** A `.craft-config.yml` without `v: 4` was written
for an older format. Keep what the resolver reads (`strictness`, rule-id
overrides under `rules:`, `sentry_org`, `sentry_project`, `context_budget`,
`guided`, and in the global file the machine-owner keys above, `packs:
external` included), replace a `stack:` mapping with the detected word, drop
`version:`, the version numbers and the `packs:` switches, add `v: 4`, show
the result, write it after confirmation, and validate it as above.

---

## Quick Mode (`--quick`)

When `$ARGUMENTS` contains `--quick`, skip ALL interactive questions and auto-generate configuration:

### Process

1. **Detect stack** using Glob tool:
   - `Glob("composer.json")` → PHP detected
   - `Glob("package.json")` → Node detected
   - Map it to `{stack}` as [The configuration file (v4)](#the-configuration-file-v4) says: PHP only → `symfony`, Node only → `react`, both → `fullstack`, neither → `other`

2. **Extract user name** from git, for the summary:
   - Run `git config user.name` via Bash tool
   - Fallback: `"Developer"` if not configured

3. **Write the project file** with the `Write` tool: `$PWD/.craft-config.yml`, the v4 block of [The configuration file (v4)](#the-configuration-file-v4), with the detected stack, `guided: false`, and no `strictness` line (the plugin derives it with `config_default_strictness`).

4. **Take the baseline** exactly as [Step D](#step-d-take-the-baseline) says.

5. **Validate and read back** with the command of [The configuration file (v4)](#the-configuration-file-v4). Report its values, not the ones you meant to write.

6. **Display summary** (no questions asked):

```
Quick Setup Complete!

  Name: {name} (from git config)
  Stack: {stack read back by config_stack}
  Strictness: {strictness read back by config_strictness}
  Biases: all enabled
  Baseline: {what Step D recorded, or "already taken"}

Config saved to .craft-config.yml (this project)
Run /craftsman:setup for full customization (situational questions, DISC profile)
```

### Guard: Existing Config

If `$PWD/.craft-config.yml` already exists (the workshop profile in `~/.claude/` is not a project config and does not stop a project setup):

```
Config already exists at {path}. Quick setup skipped.
Use /craftsman:setup --quick --force to overwrite, or /craftsman:setup for interactive reconfiguration.
```

Exit without changes unless `--force` is also present in `$ARGUMENTS`. A file without `v: 4` is a pre-v4 config: say so and offer the migration of [The configuration file (v4)](#the-configuration-file-v4) instead of skipping silently.

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

### Stack Pre-Selection

Pre-select the stack based on detection (user can override in Step 4), with the mapping of [The configuration file (v4)](#the-configuration-file-v4):

- PHP detected → `symfony`
- Node detected → `react`
- Both detected → `fullstack`, display confirmation prompt
- Neither → `other`

### Existing Config Check

Check if configuration already exists:

Use the **Read** tool to read `$PWD/.craft-config.yml` (this project) and `~/.claude/.craft-config.yml` (this machine). A missing file is CONFIG_NOT_FOUND for that scope.

- If the project file exists: Show it and ask "Do you want to reconfigure? [y/N]". Without `v: 4` it is a pre-v4 file: propose the migration of [The configuration file (v4)](#the-configuration-file-v4).
- If it doesn't exist: Proceed with full setup

## Setup Process

### Step 1: Welcome

Display:

```
Welcome to AI Craftsman Superpowers!

Let's configure your craftsman profile.
The project settings go to .craft-config.yml (this project),
your personal profile to ~/.claude/.craft-config.yml (this machine).
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

Default recommendation: All enabled. Record the answers by id: `acceleration`, `scope_creep`, `over_optimization`, `dispersion`.

### Step 4: Stack

Detect available packs and their descriptions:

Use the **Glob** tool: `Glob("packs/*/pack.yml")`. For each found file, use the **Read** tool to read it and extract the `description:` field. Display each pack as `- **<pack-name>**: <description>`. If no packs found, say "No packs found." Every shipped pack declares `stack: ["*"]` and judges its own file types, so there is nothing to switch on or off: the question is which stack this project is.

Use `AskUserQuestion` to confirm the stack pre-selected in Pre-check:

**Question 4 - Stack:**
- **symfony** - PHP/Symfony - _pre-selected if only PHP detected_
- **react** - React/TypeScript - _pre-selected if only Node detected_
- **fullstack** - both - _pre-selected if both detected_
- **other** - anything else

### Step 5: Generate Configuration

Two files, each with its own scope:

1. **This project**: write `$PWD/.craft-config.yml` with the v4 block of [The configuration file (v4)](#the-configuration-file-v4). Without the situational questions of Step B, omit `strictness` (the plugin derives it) and write `guided: false`.
2. **This machine**: merge the personal profile into `~/.claude/.craft-config.yml`. Add `v: 4` if it is absent, add or replace the `profile:` block, and keep every other key: that file also holds the machine owner's switches (`trust_project_tools`, `hooks`, `packs: external`).

```yaml
# ~/.claude/.craft-config.yml, merged: every other key is kept
v: 4
profile:
  name: "{collected_name}"
  disc_type: "{collected_disc}"
  biases:
    - {bias1}
    - {bias2}
```

Use the `Write` tool (or `Edit` for the merge), then validate and read back both files with the command of [The configuration file (v4)](#the-configuration-file-v4) (`config_validate ~/.claude/.craft-config.yml` for the second). Take the baseline as [Step D](#step-d-take-the-baseline) says.

### Step 6: Display Summary

After saving, display the values read back, not the ones you meant to write:

```
Configuration saved:
  .craft-config.yml (this project)
  ~/.claude/.craft-config.yml (your profile)

Your Profile:
  Name: {name}
  DISC Type: {disc_type}
  Bias Protection: {biases}

This Project:
  Stack: {stack read back by config_stack}
  Strictness: {strictness read back by config_strictness}
  Baseline: {what Step D recorded, or "already taken"}

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

{if stack is symfony or fullstack}
Symfony Pack:
  /craftsman:scaffold [entity|usecase]  - Scaffold DDD patterns
{/if}

{if stack is react or fullstack}
React Pack:
  /craftsman:scaffold [component|hook]  - Scaffold React patterns
{/if}

AI-ML Pack (every stack):
  /craftsman:rag          - Design RAG pipeline
  /craftsman:mlops        - MLOps audit
  /craftsman:agent-design - Agent 3P pattern

Happy crafting!
```

## Important Notes

- Always use `AskUserQuestion` for interactive collection
- Use `Write` tool to create the config file
- Validate the written file with `config_validate`, not only its YAML syntax: a pre-v4 file parses and is still read wrongly
- If reconfiguring, preserve rule-id overrides under `rules:` and every key of the global file the user added manually
