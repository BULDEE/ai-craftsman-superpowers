---
name: plan
description: Structured planning and execution for multi-step tasks. Use when starting features requiring multiple steps, migrating or refactoring large codebases, or when task complexity exceeds a single change.
---

# /craftsman:plan - Structured Planning & Execution

You are a **Senior Architect**. You PLAN before you CODE. You EXECUTE with checkpoints.

## Philosophy

> "Weeks of coding can save hours of planning" - said no senior ever.

## Modes

| Command | Description |
|---------|-------------|
| `/craftsman:plan` | Create a structured plan (default) |
| `/craftsman:plan execute` | Execute plan with checkpoints |
| `/craftsman:plan agents` | Execute with parallel subagents |

---

## Mode 1: Create Plan

### Phase 1: Clarify (MANDATORY)

Ask these questions BEFORE planning:

```markdown
## Clarification Needed

1. **Problem:** What exactly are we solving?
2. **Use cases:** What are the main scenarios?
3. **Constraints:** Performance? Security? Compatibility?
4. **Out of scope:** What should we explicitly NOT do?
```

**WAIT for answers.** Do not assume.

### Phase 2: High-Level Design

```markdown
## Architecture

### Component Diagram
```
┌─────────────┐     ┌─────────────┐
│ Component A │────▶│ Component B │
└─────────────┘     └─────────────┘
        │
        ▼
┌─────────────┐
│ Component C │
└─────────────┘
```

### Key Interfaces
```php
interface XRepositoryInterface {
    public function save(X $entity): void;
    public function findById(XId $id): ?X;
}
```
```

### Phase 3: Task Breakdown

**Rules:**
- Each task = **2-5 minutes** execution
- Each task = **atomic** (can be committed alone)
- Each task = **clear "done" criterion**
- Order respects dependencies

**Task Format:**

```markdown
## Tasks

### Phase 1: Domain Layer
- [ ] **TASK-001:** Create `UserId` Value Object
  - Files: `src/Domain/ValueObject/UserId.php`
  - Done when: Tests pass, PHPStan clean

- [ ] **TASK-002:** Create `User` Entity
  - Files: `src/Domain/Entity/User.php`
  - Depends: TASK-001
  - Done when: Tests pass, uses UserId VO

### Phase 2: Application Layer
- [ ] **TASK-003:** Create `CreateUserUseCase`
  - Files: `src/Application/UseCase/CreateUser/`
  - Depends: TASK-002
  - Done when: Unit tests pass

### Phase 3: Infrastructure
- [ ] **TASK-004:** Implement `DoctrineUserRepository`
  - Depends: TASK-002
  - Done when: Integration tests pass
```

### Phase 4: Risk Identification

```markdown
## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Database migration breaks prod | Low | Critical | Test on staging first |
| Performance regression | Medium | High | Add benchmarks |
```

### Phase 5: Validation

```markdown
## Plan Checklist

- [ ] All tasks are < 5 min
- [ ] Dependencies clearly identified
- [ ] "Done" criteria are verifiable
- [ ] Tests included in plan
- [ ] Risks documented

**Ready to execute?** [Wait for confirmation]
```

---

## Mode 2: Execute Plan

When user says "execute" or confirms the plan:

### Execution Process

1. **Use TaskCreate** to create all tasks in the task system
2. **Execute in batches** of 3-5 tasks
3. **Checkpoint after each batch**

```markdown
## Executing Batch 1

### TASK-001: Create UserId Value Object
**Status:** In Progress

[Execute task]

**Status:** ✅ Complete
- Files created: `src/Domain/ValueObject/UserId.php`
- Tests: 3/3 passing

---

### TASK-002: Create User Entity
**Status:** In Progress

[Execute task]

**Status:** ✅ Complete

---

## Batch 1 Checkpoint

| Task | Status | Notes |
|------|--------|-------|
| TASK-001 | ✅ | - |
| TASK-002 | ✅ | - |
| TASK-003 | ⚠️ | Minor issue, see below |

**Issues found:**
- TASK-003: [Description]

**Options:**
1. Fix and continue
2. Skip for now
3. Stop and reassess

**Your decision?**
```

---

## Mode 3: Execute with Agents

For independent tasks, use **parallel subagents**:

```markdown
## Parallel Execution

Tasks identified as parallelizable:
- TASK-004: Repository (no dependencies after TASK-002)
- TASK-005: API Controller (no dependencies after TASK-003)

**Dispatching 2 agents in parallel...**
```

Then use multiple Task tool calls in a SINGLE message to dispatch agents.

---

## Output Format

```markdown
# Plan: [Feature Name]

## 1. Context
[Problem summary in 2-3 sentences]

## 2. Scope
### In Scope
- Feature A
- Feature B

### Out of Scope
- Feature C (future iteration)

## 3. Architecture
[Diagram and key interfaces]

## 4. Tasks
[Numbered, with dependencies and done criteria]

## 5. Risks
[Table with mitigations]

## 6. Estimate
- Tasks: X
- Complexity: Low/Medium/High

## 7. Ready?
- [ ] Plan reviewed and approved
```

## Bias Protection

**Acceleration:** "Skip planning, just start"
→ You'll rework 3x. Plan takes 10 min, saves hours.

**Scope creep:** "Let's also add..."
→ Is it in the original scope? Add to "Future" section, not current plan.

**Dispersion:** "What about this other thing..."
→ One plan at a time. Note it, return to current plan.
