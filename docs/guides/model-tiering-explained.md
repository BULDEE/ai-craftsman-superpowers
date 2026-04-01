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

**Costs:** ~5x cheaper than Sonnet
**Speed:** ~3x faster than Sonnet
**Latency:** <1 second typically

**Best for:**
- Validation tasks (checking syntax, rules)
- Simple transformations (format changes)
- Procedural operations (git commits)
- Read-only analysis (quick checks)

**Limitation:** Less capable at reasoning and creativity

**Used in:**
- `/craftsman:verify` — Validate code quality
- `/craftsman:git` — Generate commit messages
- Hooks/real-time validation — Rapid feedback

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
- `/craftsman:design` — Domain modeling
- `/craftsman:spec` — Test specifications
- `/craftsman:scaffold` — Code generation
- `/craftsman:test` — Test implementation
- `/craftsman:refactor` — Refactoring
- `/craftsman:debug` — Debugging

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
- `/craftsman:challenge` — Architecture review (recommended)
- `/craftsman:plan` — Strategic planning (recommended)
- `/craftsman:parallel` — Agent orchestration (recommended)
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

### Feature: "Add User Registration" (Sequential Workflow)

```
Step 1: /craftsman:design (Sonnet)
  - Input: Feature description
  - Output: Domain model
  - Cost: ~$0.008
  - Time: 3 min

Step 2: /craftsman:spec (Sonnet)
  - Input: Design
  - Output: Test specifications
  - Cost: ~$0.006
  - Time: 2 min

Step 3: /craftsman:scaffold (Sonnet)
  - Input: Design + spec
  - Output: Code skeletons
  - Cost: ~$0.008
  - Time: 4 min

Step 4: /craftsman:test (Sonnet)
  - Input: Scaffolded code
  - Output: Test implementations
  - Cost: ~$0.008
  - Time: 3 min

Step 5: /craftsman:challenge (Opus)
  - Input: All code
  - Output: Architecture critique
  - Cost: ~$0.020 (2x more expensive, but worth it)
  - Time: 5 min

Step 6: /craftsman:verify (Haiku)
  - Input: All code
  - Output: Quality report
  - Cost: ~$0.001 (ultra-cheap)
  - Time: 1 min

Step 7: /craftsman:git (Haiku)
  - Input: Modified files
  - Output: Git commit
  - Cost: ~$0.001
  - Time: <1 min

TOTAL COST: ~$0.052
TOTAL TIME: ~20 min
```

### Comparison: If All Commands Used Sonnet

```
Same workflow, all Sonnet:
Step 1-4: Sonnet (same cost, same quality) ✅
Step 5: Challenge as Sonnet
  - Cost: ~$0.010 (cheaper)
  - Quality: Lower (less judgment)
  - Issues: Might miss subtle architecture problems ❌
Step 6-7: Sonnet (overkill)
  - Cost: ~$0.008 total (much more expensive)
  - Quality: Wasted capability (doesn't need reasoning)
  - Issues: Slow feedback on simple validation ❌

TOTAL COST: ~$0.052 (SAME!)
TOTAL TIME: ~25 min (SLOWER!)
QUALITY: Mixed (worse on critical path)
```

### Comparison: If All Commands Used Opus

```
Same workflow, all Opus:
Every step: Opus
  - Cost: ~$0.140 (2.7x more expensive!)
  - Quality: Overkill on scaffolding
  - Issues: Slow feedback loop, expensive verification ❌

TOTAL COST: ~$0.140 (268% more!)
TOTAL TIME: ~35 min (75% slower!)
```

## The Sweet Spot

Model tiering puts **expensive capability where it matters** (architecture/planning) and **cheap/fast everywhere else** (validation/execution).

---

## How to Interpret Tiering in Commands

When you see command documentation:

```markdown
# /craftsman:design

model: sonnet
effort: medium
```

This means:
- Uses Sonnet model
- Takes 2-5 minutes typically
- Cost: $0.008 per use
- Good for code generation and reasoning

---

## When to Override Tiering

### Use Haiku When Sonnet is Overkill

**Don't do:**
```bash
/craftsman:design
> Just add a simple getter method to User class
```

**Do:**
```bash
/craftsman:scaffold
> Add getter method to User class. Minimal context needed.
# Sonnet is still more efficient for this
```

### Force Opus When Judgment is Critical

Default commands use Sonnet, but you can optionally request Opus:

```bash
/craftsman:challenge --model=opus
> Architecture review for our payment system
```

Use when:
- Payment processing (critical security)
- Multi-year strategic decision
- Security-sensitive components
- Million-dollar business logic

### Downgrade to Haiku When Speed Matters

Real-time validation in hooks uses Haiku automatically:
- On file save
- On git commit
- On session start

This keeps IDE latency low.

---

## Configuration

Model tiering is configured in `CLAUDE.md` and `plugin.json`:

```yaml
# Plugin config
commands:
  design:
    model: sonnet
  scaffold:
    model: sonnet
  challenge:
    model: opus
  verify:
    model: haiku
  git:
    model: haiku
```

Override in project `.craft-config.yml`:
```yaml
# Downgrade challenge to sonnet for cost savings
overrides:
  challenge:
    model: sonnet
```

---

## Monitoring Costs

Check your API usage:

```bash
/craftsman:metrics
```

Output shows:
```
Model usage this week:
- Haiku:  156 calls × $0.0008 = $0.125
- Sonnet: 42 calls × $0.003  = $0.126
- Opus:   8 calls × $0.015   = $0.120

Total: $0.371

Breakdown:
- Verification (Haiku): $0.125 (34%)
- Development (Sonnet): $0.126 (34%)
- Architecture (Opus):  $0.120 (32%)

Most expensive: /craftsman:challenge (35 calls, $0.105)
```

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

Full pricing breakdown in [ADR-001: Model Tiering Strategy](../adr/001-model-tiering.md)

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
