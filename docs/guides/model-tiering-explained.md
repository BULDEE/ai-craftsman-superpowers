# Model Tiering Explained

This guide explains why AI Craftsman Superpowers uses different Claude models for different commands and how this affects cost and quality.

## The Strategy (Simplified)

We match each command to the right model:

**Simple tasks → Fast, cheap model (Haiku)**
**Complex tasks → Capable, smart model (Sonnet or Opus)**

Result: Better quality where it matters, lower cost where it doesn't.

---

## The Model Tiers

### Tier 1: Haiku (Fast & Cheap)

Haiku is a lightweight model optimized for speed and cost.

**Costs:** 3x cheaper than Sonnet at list price ($1/$5 per Mtok against $3/$15)
**Speed:** noticeably faster, which is what keeps a write-time hook out of
your way. The exact factor depends on prompt size, so no number is quoted here

**Best for:**
- Validation tasks (checking syntax, rules)
- Simple transformations (format changes)
- Procedural operations (git commits)
- Read-only analysis (quick checks)

**Limitation:** Less capable at reasoning and creativity

**Used in:**
- `/craftsman:verify` - Validate code quality
- `/craftsman:git` - Generate commit messages
- Hooks/real-time validation - Rapid feedback

**Example:**
```bash
$ /craftsman:verify

# Haiku analyzes all files (~2 seconds):
# - Checks for strict_types declaration
# - Validates final classes
# - Scans for setter methods
# - Confirms no `any` in TypeScript
# Output: Quality report
```

**Cost:** $0.001-0.002 per verification

---

### Tier 2: Sonnet (Balanced, Default)

Sonnet is the default model. Fast enough and capable enough for most development work.

**Costs:** 1x baseline
**Speed:** Fast (2-5 seconds per response)
**Intelligence:** High (good reasoning, creativity)

**Best for:**
- Code generation (scaffolding)
- Test writing (creative test cases)
- Specifications (clear requirements)
- Refactoring (understanding intent)
- Most development tasks

**Strengths:**
- Good at code generation
- Strong architectural thinking
- Can catch subtle bugs
- Fast feedback loop
- Cost-effective for frequent use

**Used in:**
- `/craftsman:design` - Domain modeling
- `/craftsman:spec` - Test specifications
- `/craftsman:scaffold` - Code generation
- `/craftsman:test` - Test implementation
- `/craftsman:refactor` - Refactoring
- `/craftsman:debug` - Debugging

**Example:**
```bash
$ /craftsman:spec

# Sonnet writes test specifications:
# - Understands domain requirements
# - Generates edge case test names
# - Creates BDD Given/When/Then structure
# - Identifies error scenarios
# Output: Comprehensive test specs
```

**Cost:** $0.003-0.010 per command

---

### Tier 3: Opus (Complex & Critical)

Opus is the most capable model. Use for decision-making and high-stakes judgment.

**Costs:** ~2x more expensive than Sonnet
**Speed:** Slower (5-10 seconds)
**Intelligence:** Highest (excellent reasoning, judgment)

**Best for:**
- Architectural decisions (long-term impact)
- Strategic planning (multiple options, trade-offs)
- Code review (subtle issues)
- Orchestration (managing multiple agents)
- Critical reasoning tasks

**Strengths:**
- Excellent at architecture review
- Can hold complex context
- Good at planning multi-step work
- Better at identifying subtle bugs
- Strong judgment for design decisions

**Used in:**
- `/craftsman:challenge` - Architecture review (recommended)
- `/craftsman:plan` - Strategic planning (recommended)
- `/craftsman:parallel` - Agent orchestration (recommended)
- Pack-specific: `rag`, `mlops`, `agent-design` (recommended)

> **Note:** Since commands no longer carry a `model:` frontmatter field (see [ADR-0007](../adr/0007-commands-over-skills.md)), model tiering is a recommendation, not an enforcement. The user's active model applies. Agent files (e.g., `team-lead`) do enforce their model via frontmatter.

**Example:**
```bash
$ /craftsman:challenge

# Opus reviews architecture for:
# - Layer violations
# - Aggregate boundary issues
# - Naming clarity
# - SOLID principle compliance
# - Long-term maintainability
# Output: Deep architectural critique
```

**Cost:** $0.010-0.030 per challenge/plan

---

## Decision: Why This Tier?

### Haiku for Verify

**Why?**
- `/craftsman:verify` is validation, not creation
- Checks are rule-based (PHPStan, ESLint output)
- Speed matters (developer feedback loop)
- Lower cost acceptable (runs frequently)

**What it does:**
- Parses validation tool output
- Summarizes violations
- Rates severity
- Suggests fixes

**Why NOT Sonnet?**
- Overkill for rule-based checks
- Slower response (not necessary)
- Higher cost (1000+ verifications per team per month)

---

### Sonnet for Design/Spec/Scaffold

**Why?**
- Most of development work is here
- Need good code generation quality
- Speed critical (developer flow)
- Cost-effective (Sonnet is balanced)

**What Sonnet excels at:**
- Writing clean code
- Understanding requirements
- Generating test cases
- Refactoring with context

**Why NOT Haiku?**
- Haiku can't write good code from scratch
- Lacks reasoning for architectural choices
- Would require constant corrections

**Why NOT Opus?**
- Overkill for straightforward scaffolding
- Too slow (response time matters in flow)
- Too expensive (would 2x command costs)

---

### Opus for Challenge/Plan/Parallel

**Why?**
- These are judgment calls, not execution
- Wrong decision has long-term impact
- Reasoning complexity is high
- Cost premium justified by quality

**What Opus excels at:**
- Finding subtle architectural issues
- Coordinating multiple agents
- Identifying second-order consequences
- Strategic planning

**Examples where Opus shines:**

1. **Architecture Review**
   - Haiku: "Missing error handling"
   - Sonnet: "Error handling incomplete in 2 places"
   - **Opus: "Error handling incomplete AND you're not propagating context from outer layer to inner layer, which will make debugging hard"**
   - Impact: Opus finds the fundamental issue

2. **Planning**
   - Haiku: Can't plan (no reasoning)
   - Sonnet: "Break into 5 tasks, estimated 2 hours"
   - **Opus: "Break into 5 tasks, estimated 2 hours, BUT task 3 blocks task 4 so do task 4 first, and here's a risk: task 2 touches shared state..."**
   - Impact: Opus catches dependencies and risks Sonnet misses

3. **Multi-Agent Orchestration**
   - Haiku: Can't orchestrate
   - Sonnet: "Run tasks A and B in parallel"
   - **Opus: "Run A-B-C in parallel phase 1, then D (depends on A), E (depends on B), F (depends on C) in phase 2, then G (depends on D-E-F) in phase 3. Risk: phase 2 takes longer than expected, adjust estimate to 45 min"**
   - Impact: Opus optimizes the critical path

**Cost justified:**
- `/craftsman:plan` once per feature (~$0.02 cost)
- Saves hours of rework (cost difference: $0.02 vs 2 hours of developer time)
- ROI is clear

---

## Cost Impact

The numbers that follow are list prices per million tokens, published by
Anthropic. What a given step costs depends on how much context it carries,
which nobody can state for your codebase, so this section gives ratios rather
than invented totals.

| Tier | Input | Output | Relative to Sonnet |
|------|-------|--------|--------------------|
| Haiku 4.5 | $1.00 | $5.00 | 3x cheaper |
| Sonnet 5 | $3.00 | $15.00 | baseline |
| Opus 5 | $5.00 | $25.00 | 1.7x more |

Read the tiering decision off that table. A verification pass that re-reads the
files it just checked is the step whose token count grows fastest, and it is
the step whose judgement matters least: that is why every hook runs on Haiku.
An architecture critique carries a fraction of those tokens and is the step
where a worse answer costs the most rework: that is why `/craftsman:challenge`
runs on Opus.

Putting the whole pipeline on Opus multiplies the cheap high-volume steps by
five while changing nothing about the expensive low-volume ones. Putting it all
on Haiku saves little (the high-volume steps are already there) and gives up
the judgement on the steps that needed it.

For what a session actually cost, use Claude Code's `/usage`. This plugin
records no token or cost data.

## The Sweet Spot

Model tiering puts **expensive capability where it matters** (architecture/planning) and **cheap/fast everywhere else** (validation/execution).

---

## The Assignment

Every skill declares its tier in its own frontmatter. `model` picks the model,
`effort` picks how hard that model thinks. The two are set together: a cheap
model at high effort is usually worse value than the next model up.

| Tier | Effort | Skills | Why this tier |
|---|---|---|---|
| `haiku` | `low` | `verify`, `git`, `metrics`, `healthcheck` | Mechanical. Run a command, read the exit code, format the result. No design judgment involved, so a larger model buys nothing. |
| `sonnet` | `medium` | `spec`, `test`, `scaffold`, `ci`, `setup`, `workflow` | Applying a known pattern within a bounded scope, or walking the user through a guided flow. |
| `opus` | `high` | `design`, `challenge`, `debug`, `refactor` | Judgment calls with consequences: aggregate boundaries, root causes, behaviour-preserving refactors. Reasoning that spans files. |
| `opus` | `xhigh` | `plan`, `legacy`, `team`, `parallel`, `agent-design`, `rag`, `mlops` | Same reasoning, sustained over long horizons: campaigns, orchestration, pipeline architecture. |

Reading a declaration:

```yaml
# skills/design/SKILL.md
model: opus
effort: high
```

`high` is Claude Code's *default* effort, so declaring it is an explicit
statement rather than a change. `xhigh` is genuinely above the default;
`medium` and `low` sit below it and are the token-saving settings.

### Why aliases and not model ids

Every tier is an alias (`haiku`, `sonnet`, `opus`), never a pinned id like
`claude-opus-5`. Aliases resolve to the newest model in their family, so the
plugin follows model releases without a version bump. It also makes the tiering
remappable - see Overriding below.

Aliases resolve per provider: on the Anthropic API `opus` is Opus 5 and
`sonnet` is Sonnet 5, but on Microsoft Foundry `opus` is Opus 4.6. The tier is
a statement about *capability class*, not about a specific model.

### Where Fable 5 fits

Fable 5 is the most capable tier and the natural fit for `legacy`, `team`, and
`parallel` - work that runs longer than a single sitting. It is deliberately
**not** the default on them, for three reasons:

- It costs $10/$50 per MTok against Opus 5's $5/$25. Defaulting the longest-running
  skills to the most expensive tier is the opposite of what tiering is for.
- It is unavailable under zero data retention, so a `fable` pin would hard-fail
  for those organisations.
- Opus 5 is genuinely strong on this work - it is the documented workhorse for
  agentic and multi-file tasks.

If you want it on those three, `best` is the value to use rather than `fable`:
it selects Fable 5 where your organisation has access and falls back to the
latest Opus everywhere else.

---

## Overriding the tiering

The tiering is enforced, not advisory: a skill's `model` wins over whatever
`/model` is set to, for the turn it runs in. That is the point - it is what
stops a review running on the most expensive tier you happen to have selected.
The session model returns on your next prompt.

You stay in control through four mechanisms, from broadest to narrowest.

### 1. Remap a whole tier (recommended)

Because every tier is an alias, you decide what each alias resolves to:

```bash
# Every `model: opus` skill now runs Fable 5
export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-fable-5

# Or the other way: cap the opus tier at Sonnet for a cost-sensitive project
export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-sonnet-5
```

`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, and
`ANTHROPIC_DEFAULT_FABLE_MODEL` work the same way. This is the cleanest lever:
it moves an entire tier at once and needs no changes to the plugin.

### 2. Replace an agent outright

Project and user `.claude/agents/<name>.md` definitions **override same-named
plugin agents**. Copy the agent you want to change, edit its `model`, and yours
wins:

```bash
mkdir -p .claude/agents
cp "$CLAUDE_PLUGIN_ROOT/agents/architect.md" .claude/agents/architect.md
# edit the model: line - your definition now takes precedence
```

### 3. Shadow a skill

Plugin skills are namespaced, so a local copy does not replace them; it sits
alongside. Copy the skill to `.claude/skills/<name>/SKILL.md` and you get an
unnamespaced `/design` with your tier, next to the plugin's
`/craftsman:design`. Use whichever fits the task.

### 4. Pick a different skill

Often the right answer is not overriding a tier but choosing the skill whose
tier already matches the job. Adding a getter does not need `/craftsman:design`
at the `opus` tier - `/craftsman:scaffold` at `sonnet` is the tool for it.

### What hooks do

Real-time validation on file save, commit, and session start always runs on
Haiku regardless of session model, which is what keeps editor latency low.
Model-based verification can be turned off entirely with the `agent_hooks`
plugin setting.

---

## Monitoring Costs

This plugin does not track spend. Its metrics database records violations,
corrections and sessions; it holds no model, token or cost column, and
`/craftsman:metrics` reports on code quality, not on your bill.

Claude Code's own `/usage` is where model spend lives. Its Session block gives
token counts and a locally computed dollar figure per model, and on a Pro,
Max, Team or Enterprise plan it also attributes recent usage to skills,
subagents and individual plugins, so you can see this plugin's own share.
Press `d` or `w` to switch between the last 24 hours and the last 7 days.

The figures are computed from local session history at list prices, so they
exclude other machines and any contracted discount. For authoritative billing,
use the usage page in the Claude Console.

---

## FAQ

### "Why isn't Sonnet used for everything?"

Because different tasks have different needs:
- **Verification** is rule-based → Haiku is sufficient, faster, cheaper
- **Architecture review** requires judgment → Sonnet or Opus
- **Planning** requires strategic thinking → Opus

Using wrong tool = worse results at same cost.

### "Can I use Haiku for code generation?"

No, Haiku can't write production-quality code from descriptions. It would need constant corrections, making it slower overall.

### "Opus is too expensive. Can we use Sonnet for everything?"

You'd sacrifice architecture quality (most important decisions). Better to:
- Use Sonnet for daily development (already good)
- Use Opus for critical decisions (rare but important)
- Use Haiku for validation (frequent, no judgment needed)

This balanced approach minimizes cost while protecting quality where it matters.

### "My team is price-sensitive. What do we disable?"

Priority for disabling (least impact):

1. **Disable Opus in /craftsman:challenge** → Use Sonnet instead
   - Saves: $0.01/challenge
   - Loss: Miss some subtle issues
   - When: Internal code only, not customer-facing

2. **Disable hooks validation** → Manual verification only
   - Saves: $0.10-0.30/session
   - Loss: No real-time feedback
   - When: Very tight budget

3. **Use Haiku for /craftsman:debug** → Less reasoning
   - Saves: $0.005/debug
   - Loss: Slower debugging
   - When: Simple bugs only

Full pricing breakdown in [ADR-0010: Model Tiering Strategy](../adr/0010-model-tiering.md)

---

## Philosophy

> "The right tool for the right job, at the right cost."

We invest in capability where decisions matter:
- **Architecture** (long-term impact) → Opus
- **Code generation** (daily work) → Sonnet  
- **Validation** (repetitive checks) → Haiku

This creates a system that is simultaneously:
- **Fast** (Haiku for quick feedback)
- **Intelligent** (Sonnet/Opus where needed)
- **Affordable** (tiered by necessity)
