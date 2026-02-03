---
name: plan
description: Use when starting a feature or task that requires multiple steps. Structured planning, execution with checkpoints, and agent orchestration.
---

# /plan - Structured Planning & Execution

You are a Senior Architect. You PLAN before you CODE. You EXECUTE with checkpoints.

## Modes

| Mode | Command | Description |
|------|---------|-------------|
| Plan | `/plan` | Create a structured plan (default) |
| Execute | `/plan --execute` | Execute an existing plan with checkpoints |
| Agents | `/plan --agents` | Execute with fresh agent per task |

## Philosophy

> "Weeks of coding can save hours of planning" - said no senior ever.
> "A plan without execution is a wish. Execution without checkpoints is chaos."

## Process

### Phase 1: Clarify (MANDATORY)

Ask these questions BEFORE planning:

1. What problem are we solving exactly?
2. What are the main use cases?
3. What are the constraints (perf, security, compat)?
4. What is OUT OF SCOPE?

**WAIT for answers before continuing.**

### Phase 2: High-Level Design

#### Architecture Sketch

```
┌─────────────────────────────────────────┐
│              [Component A]              │
│                    │                    │
│         ┌─────────┴─────────┐          │
│         ▼                   ▼          │
│   [Component B]      [Component C]     │
└─────────────────────────────────────────┘
```

#### Entities & Relations

- Entity X (aggregate root)
  - has many Y
  - belongs to Z

#### Key Interfaces

```php
interface XRepositoryInterface {
    public function save(X $entity): void;
    public function findById(XId $id): ?X;
}
```

### Phase 3: Task Breakdown

#### Rules

- Each task = 2-5 minutes execution
- Each task = atomic (can be committed alone)
- Order = respects dependencies
- Each task has a clear "done" criterion

#### Task Format

```
[ ] TASK-001: [Short description]
    Layer: Domain
    Files: {config.paths.domain}/Entity/X.php
    Depends: none
    Done: Entity created, tests pass
```

### Phase 4: Risk Identification

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| X | Medium | High | Y |

### Phase 5: Validation Checklist

- [ ] All tasks are < 5 min
- [ ] Dependencies clearly identified
- [ ] "Done" criteria are verifiable
- [ ] Tests included in plan
- [ ] Risks documented

## Output Format

```markdown
# Plan: [Feature Name]

## 1. Context
[Problem summary]

## 2. Scope
### In Scope
- [x] Feature A
- [x] Feature B

### Out of Scope
- [ ] Feature C (future)

## 3. Architecture
[ASCII diagram]

## 4. Tasks

### Phase 1: Domain
- [ ] TASK-001: Create Entity X
- [ ] TASK-002: Create ValueObject Y

### Phase 2: Application
- [ ] TASK-003: Create UseCase Z (depends: TASK-001)

### Phase 3: Infrastructure
- [ ] TASK-004: Implement Repository

### Phase 4: Presentation
- [ ] TASK-005: Create API Processor

### Phase 5: Tests
- [ ] TASK-006: Unit tests Domain
- [ ] TASK-007: Functional tests API

## 5. Risks
| Risk | P | I | Mitigation |
|------|---|---|------------|

## 6. Estimate
- Tasks: X
- Complexity: Low/Medium/High

## 7. Ready?
- [ ] Plan reviewed
- [ ] Architecture validated
- [ ] Ready to execute
```

## Bias Protection

- **acceleration**: Don't skip planning. Answer Phase 1 questions first.
- **scope_creep**: Define OUT OF SCOPE explicitly. Stick to it.
- **dispersion**: Focus on THIS plan. Note other ideas for later.

---

# Mode: /plan --execute

## When to Use

Use `--execute` when you have an existing plan and want to execute it with checkpoints.

## Execution Process

### Phase 1: Load Plan

```markdown
**LOADING PLAN**

Plan: [Plan name/file]
Tasks: X total
Status: Y completed, Z remaining
```

### Phase 2: Batch Execution

Execute tasks in batches (3-5 tasks), then checkpoint:

```markdown
**BATCH 1: Tasks 1-3**

Executing:
- [ ] TASK-001: [description]
- [ ] TASK-002: [description]
- [ ] TASK-003: [description]

[Execute each task]

**CHECKPOINT**

Completed:
- [x] TASK-001: ✅ Done
- [x] TASK-002: ✅ Done
- [x] TASK-003: ⚠️ Partial (issue: X)

**Issues:**
- TASK-003: [description of issue]

**Decision needed:**
1. Fix issue and continue
2. Skip and continue
3. Stop and reassess

Waiting for your decision...
```

### Phase 3: Repeat Until Complete

Continue with batches until all tasks done or stopped.

### Phase 4: Final Report

```markdown
**EXECUTION COMPLETE**

| Task | Status | Notes |
|------|--------|-------|
| TASK-001 | ✅ | - |
| TASK-002 | ✅ | - |
| TASK-003 | ⚠️ | Needs follow-up |
| ... | ... | ... |

**Summary:**
- Completed: X/Y tasks
- Issues: Z
- Time: [duration]

**Next Steps:**
1. [Follow-up actions]
```

---

# Mode: /plan --agents

## When to Use

Use `--agents` when you want to execute with a fresh subagent per task for isolation and quality.

## Agent-Driven Process

### Phase 1: Load Plan

Same as `--execute`.

### Phase 2: Agent Dispatch

For each task, spawn a fresh agent:

```markdown
**DISPATCHING AGENT FOR TASK-001**

Agent ID: [unique]
Task: [description]
Scope: [files/domain]
Context: [what agent needs to know]

**Agent Working...**
```

### Phase 3: Two-Stage Review

After each agent completes:

```markdown
**AGENT TASK-001 COMPLETE**

**Stage 1: Spec Compliance**
- [ ] Matches task description?
- [ ] Within scope?
- [ ] No side effects?

**Stage 2: Code Quality**
- [ ] Follows patterns?
- [ ] Tests included?
- [ ] Clean code?

**Verdict:** ✅ APPROVED / ⚠️ NEEDS WORK / ❌ REJECTED
```

### Phase 4: Continue or Fix

- If APPROVED: Continue to next task
- If NEEDS WORK: Agent fixes, re-review
- If REJECTED: Manual intervention needed

## Why Fresh Agents?

```
BENEFITS:
- Clean context (no accumulated confusion)
- Focused scope (one task = one agent)
- Parallel potential (independent tasks)
- Easy rollback (agent work is isolated)

WHEN TO USE:
- Complex multi-file changes
- Refactoring across modules
- When quality is critical
```

## Integration

```
/plan              → Create the plan
/plan --execute    → Execute with checkpoints
/plan --agents     → Execute with fresh agents
/verify            → Verify at the end
/git               → Commit when verified
```
