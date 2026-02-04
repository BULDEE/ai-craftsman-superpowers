# Example: Plan Migration to Microservices

## Prompt

```
/craftsman:plan
I need to migrate our monolithic e-commerce API to microservices.
Current state:
- 45 REST endpoints
- 3 databases (users, orders, products)
- 200k active users
- Team of 4 developers
```

## Expected Behavior

### Phase 1: Scope Analysis

Claude should ask clarifying questions:

```markdown
## Scope Clarification

1. **Business drivers:** Why migrate? Scaling? Team autonomy? Deployment speed?
2. **Timeline:** Hard deadline or flexible?
3. **Risk tolerance:** Can we have downtime? Data loss acceptable?
4. **Current pain points:** Which parts of monolith are problematic?
5. **Team experience:** Familiarity with microservices, Kubernetes, etc.?
```

### Phase 2: Task Decomposition

```markdown
## Migration Plan

### Phase 0: Foundation (Week 1-2)
| # | Task | Duration | Dependencies | Risk |
|---|------|----------|--------------|------|
| 0.1 | Set up API Gateway | 2d | None | Low |
| 0.2 | Configure service mesh | 2d | 0.1 | Medium |
| 0.3 | Set up centralized logging | 1d | None | Low |
| 0.4 | Set up distributed tracing | 1d | 0.2 | Low |

### Phase 1: Extract User Service (Week 3-4)
| # | Task | Duration | Dependencies | Risk |
|---|------|----------|--------------|------|
| 1.1 | Create User service skeleton | 1d | 0.1 | Low |
| 1.2 | Migrate user DB schema | 1d | 1.1 | Medium |
| 1.3 | Implement user endpoints | 3d | 1.2 | Low |
| 1.4 | Add Strangler Fig pattern | 2d | 1.3 | Medium |
| 1.5 | Gradual traffic shift (10% -> 100%) | 3d | 1.4 | High |
| 1.6 | Remove user code from monolith | 1d | 1.5 | Low |

### Phase 2: Extract Order Service (Week 5-7)
[Similar structure]

### Phase 3: Extract Product Service (Week 8-10)
[Similar structure]

### Phase 4: Decommission Monolith (Week 11-12)
[Final cleanup tasks]
```

### Phase 3: Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                    Migration Dependency Graph                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [0.1 Gateway] ─────┬──────────────────────────────────────►│
│        │            │                                        │
│        ▼            ▼                                        │
│  [0.2 Mesh] ──► [1.1 User Svc] ──► [1.2 DB] ──► [1.3 API]  │
│        │                                              │      │
│        ▼                                              ▼      │
│  [0.3 Logs]                              [1.4 Strangler]    │
│        │                                              │      │
│        ▼                                              ▼      │
│  [0.4 Tracing]                           [1.5 Traffic]      │
│                                                   │          │
│                                                   ▼          │
│                                          [1.6 Cleanup]      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Phase 4: Risk Assessment

```markdown
## Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Data inconsistency during migration | High | Critical | Use event sourcing, CDC |
| Service communication failures | Medium | High | Circuit breakers, retries |
| Team learning curve | High | Medium | Pair programming, training |
| Increased latency | Medium | Medium | Caching, async where possible |
```

## Test This Example

1. Run `/craftsman:plan` with this prompt
2. Verify Claude asks clarifying questions first
3. Check tasks are decomposed into < 5 day units
4. Verify dependencies are clearly identified
5. Check risk assessment is included
