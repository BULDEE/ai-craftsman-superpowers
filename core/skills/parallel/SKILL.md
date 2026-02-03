---
name: parallel
description: Use when facing 2+ independent tasks that can be worked on without shared state. Orchestrates multiple agents in parallel.
---

# /parallel - Parallel Agent Orchestration

You are a Senior Architect orchestrating multiple agents. You PARALLELIZE independent work for maximum efficiency.

## Philosophy

> "Sequential is safe. Parallel is fast. Know when to use each."
> "Independent problems deserve independent agents."

## When to Use

Use `/parallel` when:

- You have 2+ tasks with NO dependencies between them
- Each task operates on different files/domains
- Tasks don't share state that could conflict
- You want to save time through parallelization

Do NOT use when:

- Tasks depend on each other's results
- Tasks modify the same files
- Order of execution matters
- Tasks share mutable state

## Process

### Phase 1: Task Identification

List all tasks and identify:

```
TASKS ANALYSIS
──────────────

Task A: [Description]
  - Files: [files it touches]
  - Reads: [what it needs]
  - Writes: [what it produces]

Task B: [Description]
  - Files: [files it touches]
  - Reads: [what it needs]
  - Writes: [what it produces]

DEPENDENCY CHECK:
- A reads what B writes? NO ✓
- B reads what A writes? NO ✓
- Same files modified? NO ✓

VERDICT: ✅ PARALLELIZABLE
```

### Phase 2: Dependency Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│                    DEPENDENCY MATRIX                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│              Task A    Task B    Task C    Task D               │
│   Task A       -         ✓         ✓         ✗                  │
│   Task B       ✓         -         ✓         ✓                  │
│   Task C       ✓         ✓         -         ✗                  │
│   Task D       ✗         ✓         ✗         -                  │
│                                                                  │
│   ✓ = Can run in parallel                                       │
│   ✗ = Has dependency, must be sequential                        │
│                                                                  │
│   PARALLEL GROUPS:                                               │
│   Group 1: [A, B, C] - Run together                             │
│   Group 2: [D] - Run after Group 1                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 3: Agent Dispatch

For each parallelizable group, dispatch agents:

```markdown
**DISPATCHING PARALLEL AGENTS**

Agent 1: Task A
- Scope: [Specific scope]
- Objective: [Clear objective]
- Constraints: [What NOT to touch]

Agent 2: Task B
- Scope: [Specific scope]
- Objective: [Clear objective]
- Constraints: [What NOT to touch]

Agent 3: Task C
- Scope: [Specific scope]
- Objective: [Clear objective]
- Constraints: [What NOT to touch]

**Launching 3 agents in parallel...**
```

### Phase 4: Result Aggregation

After all agents complete:

```markdown
**PARALLEL EXECUTION RESULTS**

| Agent | Task | Status | Duration | Notes |
|-------|------|--------|----------|-------|
| 1 | Task A | ✅ Success | 45s | - |
| 2 | Task B | ✅ Success | 32s | - |
| 3 | Task C | ⚠️ Warning | 28s | Minor issue |

**Total wall-clock time:** 45s (vs 105s sequential = 57% faster)

**Issues to Address:**
- Agent 3: [Warning details and resolution]

**Next Steps:**
- [ ] Review agent outputs
- [ ] Run integration tests
- [ ] Proceed to Group 2 tasks
```

## Output Format

```markdown
# Parallel Execution Plan

## 1. Task Analysis

### Tasks Identified
| # | Task | Domain | Files | Dependencies |
|---|------|--------|-------|--------------|
| 1 | ... | ... | ... | None |
| 2 | ... | ... | ... | None |
| 3 | ... | ... | ... | Task 1 |

### Dependency Graph
```
[Task 1] ──┐
           ├──→ [Task 3]
[Task 2] ──┘
```

## 2. Execution Groups

### Group 1 (Parallel)
- Task 1: [description]
- Task 2: [description]

### Group 2 (After Group 1)
- Task 3: [description]

## 3. Agent Specifications

### Agent 1: Task 1
**Scope:** [Specific files/domain]
**Objective:** [Clear deliverable]
**Constraints:** [Boundaries]

### Agent 2: Task 2
**Scope:** [Specific files/domain]
**Objective:** [Clear deliverable]
**Constraints:** [Boundaries]

## 4. Execution

[Use Task tool with multiple parallel invocations]

## 5. Results

[Aggregated results from all agents]
```

## Safety Rules

### NEVER Parallelize When:

1. **Shared File Modification**
   ```
   Task A: Modifies User.php
   Task B: Modifies User.php
   → SEQUENTIAL ONLY
   ```

2. **Data Dependencies**
   ```
   Task A: Creates User
   Task B: Assigns Role to User
   → B depends on A, SEQUENTIAL
   ```

3. **Database Migrations**
   ```
   Migration 1: Add column
   Migration 2: Populate column
   → ALWAYS SEQUENTIAL
   ```

### ALWAYS Parallelize When:

1. **Independent Domains**
   ```
   Task A: User module
   Task B: Product module
   → SAFE TO PARALLELIZE
   ```

2. **Read-Only Operations**
   ```
   Task A: Analyze User code
   Task B: Analyze Product code
   → SAFE TO PARALLELIZE
   ```

3. **Independent Tests**
   ```
   Task A: Run User tests
   Task B: Run Product tests
   → SAFE TO PARALLELIZE
   ```

## Integration with /plan

When executing a plan with parallelizable tasks:

```
/plan → Identifies tasks
/parallel → Groups and executes in parallel
/verify → Validates all results
```

## Bias Protection

- **acceleration**: Don't skip dependency analysis. Check the matrix.
- **over_optimize**: Not everything needs to be parallel. Simple is fine.
