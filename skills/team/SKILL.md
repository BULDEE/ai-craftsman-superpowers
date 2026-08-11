---
model: opus
description: "Multi-agent orchestration with native Claude Code teams. Use when facing 2+ independent tasks needing parallel work, full-stack features requiring backend+frontend agents, code reviews needing multiple specialist perspectives, or security audits."
effort: xhigh
---

# /craftsman:team - Agent Team Manager (Native Teams)

## Outcome Contract

- **Outcome**: a multi-agent deliverable consolidated into one coherent result, not a pile of agent reports.
- **Done when**: every dispatched agent reported, conflicting recommendations are resolved explicitly, and the consolidated result is verified as a whole.
- **Evidence**: the per-agent outputs and the verification run on the merged result.

You are the **team coordinator** for AI Craftsman Superpowers. You assemble, configure, and spawn teams using Claude Code's **native Agent Teams** feature (`TaskCreate` + named teammates + `SendMessage`).

> **IMPORTANT**: Native teams require exactly one thing: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the settings.json env block or in the environment. Nothing else gates them.

## What Changed in Claude Code v2.1.178

The `TeamCreate` and `TeamDelete` tools **no longer exist**. Do not look for
them, do not call them, and never treat their absence as a broken environment:
Claude Code lists them among the tools whose absence is expected.

With the flag set, the team is created **automatically at session start**. The
session is its own team, named `session-` plus the first eight characters of
the session ID. Its config lives at `~/.claude/teams/<team-name>/config.json`
and its shared task list at `~/.claude/tasks/<team-name>/`. The main session is
already registered there as the lead. The `team_name` input on the `Agent` tool
is still accepted but ignored: a session has exactly one implicit team.

To confirm the team is live before announcing anything, read the config:

```bash
cat ~/.claude/teams/session-*/config.json
```

A `members` array containing a `team-lead` entry means native teams are working.

## Degraded Mode (flag not set)

Degrade **only** when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is unset or empty.
A missing `TeamCreate` tool is not a degradation trigger. Do NOT abort and do
not ask the user to reconfigure mid-task. Announce once:

```
Native teams unavailable (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set).
Degrading to parallel subagent dispatch - same specialists, no shared task list.
```

Then run the same composition through parallel `Agent` dispatches: one dispatch
per team member with its focus as the prompt, all in a single message when the
tasks touch disjoint files, and consolidate the reports yourself as the lead
would. The user can enable native teams later and re-run; mention
`/craftsman:healthcheck` shows whether the environment is ready.

## Subcommand Dispatch

Parse the first argument after `/craftsman:team`:

- `create` → [Team Builder](#team-create)
- `context` → [Codebase Analysis](#team-context)
- `list` → [List Teams](#team-list)
- _(no argument)_ → Show help and available subcommands

---

## /craftsman:team create {#team-create}

### Step 1: Choose Template or Custom

Ask the user:

```
How do you want to build your team?

1. code-review     - Architecture + security + domain quality review
2. feature         - Backend + frontend + post-implementation review
3. security-audit  - Penetration testing + architecture security
4. legacy-takeover - Map, net, decouple, and document a legacy codebase
5. custom          - Interactive questionnaire
```

### Step 2a: Template Path

If a template is selected (1 through 4):

1. Load the template from `teams/templates/<name>.yml`
2. Display the template summary:
   ```
   Template: <name>
   Agents: <list agent names and roles>
   Workflow: <type>
   ```
3. Ask: "Use this template as-is, or customize it? [as-is/customize]"
4. If as-is → skip to Step 4
5. If customize → proceed through Step 2b questionnaire with template as defaults

### Step 2b: Custom Questionnaire

Collect team parameters interactively:

**Q1 - Goal:**
```
What's the main goal?
  review    - Code review / audit
  implement - Build a feature
  audit     - Security / compliance audit
  migrate   - Migration / refactoring
```

**Q2 - Team size:**
```
How many agents? (2–5)
```

**Q3 - Specialties needed** (multi-select):
```
Which specialties are required?
  architecture  - Clean Architecture, DDD, layer boundaries
  security      - OWASP, pentesting, authentication flows
  frontend      - React, TypeScript, hooks, components
  backend       - PHP/Symfony, domain modeling, use cases
  ddd           - Domain modeling, aggregates, value objects
  performance   - Profiling, caching, query optimization
```

**Q4 - Isolation:**
```
Agent isolation strategy?
  worktree - Each agent works in its own git worktree (recommended for implement/migrate)
  shared   - All agents share the current working directory
```

### Step 3: Generate Team Config

Based on collected inputs, generate a team YAML and write it to `teams/<team-name>.yml`:

```yaml
# teams/<team-name>.yml
# Generated by /craftsman:team create
name: <team-name>
purpose: <user-provided goal description>
workflow:
  type: <parallel | sequential | parallel-then-review>
  steps:
    - parallel: [<agent1>, <agent2>]    # if parallel-then-review
    - sequential: [<agent3>]            # reviewer phase
agents:
  - name: <agent-slug>
    role: <lead | member | reviewer>
    scope: "<glob pattern>"
    tools: [Read, Write, Edit, Bash, Glob, Grep]
```

Agent slug → subagent_type mapping:
- `architecture` → `craftsman:architect`
- `security` → `craftsman:security-pentester`
- `frontend` → `frontend-craftsman`
- `backend` → `backend-craftsman`
- `ddd` → `architect`
- `performance` → `craftsman:team-lead`
- `team-lead` → `craftsman:team-lead`

Show the generated config to the user and ask for confirmation before proceeding.

### Step 4: Spawn the Team (Native Agent Teams)

**This is the critical step.** Drive the shared task list, do not fire off
isolated one-shot `Agent` calls and call it a team.

#### Step 4.1: Confirm the Team Exists

There is no team to create. With the flag set, Claude Code already wrote the
team config and the shared task list at session start, and registered the main
session as the lead. The team name is session-derived, so the `<team-name>` in
the rest of this skill is that name, not a name you choose.

Read it once if you need it:

```bash
cat ~/.claude/teams/session-*/config.json
```

Never call `TeamCreate`: it was removed in Claude Code v2.1.178.

#### Step 4.2: Create Tasks

Use `TaskCreate` for each agent's work scope. Tasks should be:
- **Specific**: one clear deliverable per task
- **Independent**: no cross-dependencies for parallel workflow
- **Scoped**: include the glob pattern or file list for the agent

Example for a code-review team:
```
TaskCreate({ title: "Architecture review - layer violations and dependency direction", description: "..." })
TaskCreate({ title: "Security audit - OWASP top 10 and authentication flows", description: "..." })
TaskCreate({ title: "Domain quality - aggregate boundaries and value objects", description: "..." })
```

For **parallel-then-review** workflows, also create the review task:
```
TaskCreate({ title: "Consolidation review - merge findings and resolve conflicts", description: "Depends on: [task IDs of parallel tasks]" })
```

#### Step 4.3: Spawn Teammates

Use the `Agent` tool, giving every teammate an explicit `name`:

```
Agent({
  description: "<3-5 word summary>",
  prompt: "<full task brief including team context>",
  subagent_type: "<agent-slug>",
  name: "<agent-name>"
})
```

**CRITICAL**: `name` is what makes a teammate addressable - it becomes the
agent ID `<name>@<team-name>` used by `SendMessage` and by `TaskUpdate` owners.
Do not pass `team_name`: the session has a single implicit team and the
parameter is ignored. Teammates:
- Share the task list at `~/.claude/tasks/<team-name>/`
- Can send messages to each other via `SendMessage`
- Go idle between turns and can be re-activated
- Are visible and observable by the user in the agent panel
- Get their own split pane only when `teammateMode` selects one; the default
  `in-process` mode keeps them in the lead's terminal, and that is not a failure

The lead never picks the transport. If the user wants split panes, that is a
`teammateMode` setting, not something this skill works around.

For each teammate prompt, include:
1. The team name and purpose
2. Their specific task (reference the TaskCreate ID)
3. Instructions to claim their task via `TaskUpdate` (set owner + in_progress)
4. Instructions to mark task completed via `TaskUpdate` when done
5. Instructions to check `TaskList` for additional work after completion

#### Workflow-specific spawning:

**Parallel workflow:**
Launch ALL teammates in a single message (multiple Agent tool calls):
```
// Single message with multiple parallel Agent calls
Agent({ ..., name: "arch-reviewer" })
Agent({ ..., name: "sec-pentester" })
Agent({ ..., name: "domain-reviewer" })
```

**Sequential workflow:**
Launch teammates one at a time. Wait for idle notification + task completion before spawning the next. Pass previous output via `SendMessage` or task description.

**Parallel-then-review workflow:**
1. Launch all `parallel` teammates simultaneously
2. Wait for all parallel tasks to be marked completed
3. Launch `sequential` reviewer teammate with instructions to read all completed task outputs

### Step 5: Monitor and Consolidate

After spawning teammates:

1. **Wait for notifications** - Teammates send messages automatically when they complete tasks or go idle. Do NOT poll or sleep.
2. **Respond to blockers** - If a teammate reports an issue, help resolve it via `SendMessage`.
3. **Track progress** - Use `TaskList` to see overall completion status.
4. **Re-assign if needed** - If a teammate is struggling, send guidance via `SendMessage`.

When all tasks are completed:

1. **Collect findings** - Read each teammate's task output or messages
2. **Aggregate by severity** - BLOCKING → MUST FIX → IMPROVE
3. **Deduplicate** - Remove overlapping findings across agents
4. **Present consolidated report:**

```markdown
## Team Report: <team-name>

### Summary
- Teammates: <count>
- Total findings: <count>
- BLOCKING: <count> | MUST FIX: <count> | IMPROVE: <count>

### Findings by Teammate
<per-teammate section>

### Consolidated Action Items
1. [BLOCKING] ...
2. [MUST FIX] ...
3. [IMPROVE] ...
```

5. **Shutdown the team** - Send shutdown to all teammates:
```
SendMessage({ to: "<teammate-name>", message: { type: "shutdown_request" } })
```

---

## /craftsman:team context {#team-context}

Analyze the codebase to recommend the optimal team composition.

### Step 1: Structure Analysis

Use the **Glob** tool to list source files (exclude vendor/node_modules/.git):
- `Glob("src/**/*.php")` - list PHP source files
- `Glob("src/**/*.ts")` and `Glob("src/**/*.tsx")` - list TypeScript source files

Report up to 200 files found. If no files match, say "No source files found."

### Step 2: Detect Stack

Use the **Glob** tool to check for stack indicator files:
- `Glob("composer.json")` → if exists, set PHP_DETECTED=true
- `Glob("package.json")` → if exists, set NODE_DETECTED=true

If PHP detected, use **Grep** to check `composer.json` for:
- `"symfony/framework-bundle"` → SYMFONY=true/false
- `"langchain"`, `"openai"`, or `"pgvector"` → AI_PHP=true/false

If Node detected, use **Grep** to check `package.json` for:
- `"react"` → REACT=true/false
- `"langchain"`, `"openai"`, or `"@anthropic"` → AI_NODE=true/false

### Step 3: Bounded Context Detection

Use the **Glob** tool to detect DDD layers:
- `Glob("src/Domain/**")`, `Glob("src/Application/**")`, `Glob("src/Infrastructure/**")`, `Glob("src/Presentation/**")`

If no DDD directories found, say "No DDD structure detected."

Use the **Glob** tool to detect bounded contexts:
- `Glob("src/*/")` - list top-level directories under src/, excluding Domain/Application/Infrastructure/Presentation/vendor/node_modules

### Step 4: Count Files by Layer

Use the **Glob** tool to count files per DDD layer:
- `Glob("src/Domain/**/*")` → count results → "Domain: N files"
- `Glob("src/Application/**/*")` → count results → "Application: N files"
- `Glob("src/Infrastructure/**/*")` → count results → "Infrastructure: N files"
- `Glob("src/Presentation/**/*")` → count results → "Presentation: N files"

If no layered structure found, say so.

Use the **Glob** tool to count frontend files:
- `Glob("src/components/**/*")`, `Glob("src/hooks/**/*")`, `Glob("src/pages/**/*")`, `Glob("src/services/**/*")`
- Only display directories with count > 0

### Step 5: Output Recommendation

Present findings as:

```markdown
## Codebase Analysis

### Bounded Contexts Found
<list each context with file count>

### Stack
- Backend: <detected stack and versions>
- Frontend: <detected stack and versions>
- AI/ML: <detected if present>

### Recommended Team

For this codebase, I recommend:
<agent list with rationale>

### Suggested Workflow
<workflow type with reasoning>

### Next Step
Run `/craftsman:team create` and select the recommended template,
or let me generate a custom config based on this analysis.
```

---

## /craftsman:team list {#team-list}

### Step 1: List Built-in Templates

Use the **Glob** tool: `Glob("teams/templates/*.yml")`. Extract template names from the file paths. If no files found, say "No templates directory found."

For each template found, read and display:
- Name and description
- Agent count and roles
- Workflow type
- Trigger guidance

### Step 2: List Custom Teams

Use the **Glob** tool: `Glob("teams/*.yml")`. Exclude files under `teams/templates/`. Extract team names from the file paths. If no files found, say "No custom teams configured yet."

For each custom team found, display:
- Name and purpose
- Agent count
- Creation date (from file mtime if available)

### Step 3: List Active Teams

!`ls ~/.claude/teams/*.json 2>/dev/null | xargs -I{} basename {} .json | grep . || echo "No active teams running."`

For each active team:
- Read the config to show member count and status
- Show task completion progress via TaskList

### Step 4: Display Summary

```
Available Teams
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BUILT-IN TEMPLATES
  code-review    (3 agents) - PR reviews, quality audits
  feature        (3 agents) - Full-stack feature implementation
  security-audit (3 agents) - Pre-release security checks

CUSTOM TEAMS
  <name>         (<n> agents) - <purpose>
  (none yet)

ACTIVE TEAMS
  <name>         (<n> members) - <status>
  (none running)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Run /craftsman:team create to build a new team.
Run /craftsman:team context to get a recommendation.
```

---

## Workflow Tool Variant (explicit opt-in)

Native teams above are imperative: this skill spawns and steers each
teammate. When the user explicitly asks for scripted orchestration ("use a
workflow", "fan out agents", "ultracode"), offer the native Workflow tool
instead: a deterministic pipeline script (find then verify stages, resume
cache, budget guards) that fits fixed-shape fan-outs like multi-dimension
review or migration sweeps. The offer is user-triggered, never the default:
a workflow can spawn dozens of agents, and that scale is the user's call
(context budgets, ADR-0021). Teams stay the answer for exploratory,
conversational collaboration; the Workflow tool is for pipelines whose
stages are known before launch.

---

## Help (no subcommand)

```
/craftsman:team - Agent Team Manager (Native Teams)

SUBCOMMANDS
  /craftsman:team create   - Interactive team builder (spawns named teammates)
  /craftsman:team context  - Analyze codebase and get team recommendation
  /craftsman:team list     - List templates, custom teams, and active teams

EXAMPLES
  /craftsman:team create                → guided team assembly
  /craftsman:team create feature        → fast-track feature template
  /craftsman:team context               → analyze this repo first
  /craftsman:team list                  → see what's available

REQUIREMENTS
  - settings.json: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1   (the only gate)

OPTIONAL
  - settings.json: teammateMode: "in-process" (default) | "auto" | "tmux" | "iterm2"
    Display only. Split panes need tmux, or iTerm2 with the it2 CLI.
```
