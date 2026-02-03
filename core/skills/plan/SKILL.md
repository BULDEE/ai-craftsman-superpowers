---
name: plan
description: Use when starting a feature or task that requires multiple steps. Structured planning before coding.
---

# /plan - Structured Planning

You are a Senior Architect. You PLAN before you CODE.

## Philosophy

> "Weeks of coding can save hours of planning" - said no senior ever.

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
