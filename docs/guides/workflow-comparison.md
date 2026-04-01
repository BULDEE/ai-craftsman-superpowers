# Workflow Comparison: Sequential vs Parallel vs Team

This guide compares the three execution models available in AI Craftsman Superpowers and helps you choose the right one for your task.

## Quick Decision Matrix

| Workflow | Best For | Complexity | Cost | Speed | Effort |
|----------|----------|-----------|------|-------|--------|
| **Sequential** | Small tasks, dependencies required, single person | Low | Low | Medium | Low |
| **Parallel** | Independent tasks with same domain, multi-file review | Medium | Medium | Fast | Medium |
| **Team Agent** | Complex features, cross-domain work, coordination needed | High | High | Fastest | High |

## When to Use Each

### Sequential (Manual Chaining)

Use when:
- Tasks have strict dependencies (Task B requires Task A output)
- You need full control over each step
- Tasks modify the same file or aggregate
- Complexity is low-to-medium

Example:
```
Feature implementation:
  /craftsman:design → /craftsman:spec → /craftsman:scaffold → 
  /craftsman:test → /craftsman:verify → /craftsman:git
```

Best for: One developer, straightforward features, learning the plugin.

### Parallel Execution

Use when:
- Multiple independent tasks exist (no shared files, no data dependencies)
- Same developer or team, working on same feature
- Tasks are read-heavy or write to separate files
- Coordination overhead is minimal

Example:
```
Code review on multi-domain PR:
  Agent 1: Review backend API layer
  Agent 2: Review React components
  Agent 3: Review test coverage (parallel, all read-only)
  → Aggregate results
```

Best for: Code reviews, refactoring multiple modules, exploring design alternatives.

### Team Agent Workflow

Use when:
- Complex features spanning multiple domains (backend, frontend, infra)
- Agents need to discover and coordinate via shared task list
- Specialists bring different expertise (architect, security, frontend)
- High quality is more important than speed

Example:
```
Implement checkout with payment system:
  Team created with 3 agents (backend/domain, frontend, security)
  Shared task list: design domain → API spec → scaffold backend → 
  scaffold frontend → security review → integration test
  Agents coordinate via task list (who's unblocked, who's next)
```

Best for: Large features, production systems, security-critical work.

---

## Detailed Comparison

### Sequential Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                   Your Working Directory                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  /craftsman:design                                          │
│  ├─→ Generate design document                              │
│  │                                                          │
│  /craftsman:spec                                            │
│  ├─→ Write test specs (reads: design doc)                  │
│  │                                                          │
│  /craftsman:scaffold                                        │
│  ├─→ Generate code (reads: design, spec)                   │
│  │                                                          │
│  /craftsman:test                                            │
│  ├─→ Add test implementations (reads: code)                │
│  │                                                          │
│  /craftsman:verify                                          │
│  ├─→ Validate all (reads: code, tests)                     │
│  │                                                          │
│  /craftsman:git                                             │
│  └─→ Commit atomically                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Timeline: Design → Spec → Scaffold → Test → Verify → Git
Duration: ~T (all sequential)
```

**Characteristics:**
- Single context throughout
- Full history visible in one conversation
- Changes happen sequentially in working directory
- Easy to backtrack or adjust

**Prerequisites:**
- None (works out of the box)

**Estimating cost:**
- 1 call to Sonnet per command
- Total: ~6-7 calls per feature
- Cost: ~$0.02-0.04 per feature

### Parallel Workflow

```
┌──────────────────────────────────────────────────────────────┐
│                    Your Working Directory                    │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  /craftsman:parallel                                         │
│  │                                                            │
│  ├─→ Agent 1: /craftsman:challenge on backend API            │
│  │   └─→ Scope: src/API/... (read-only analysis)             │
│  │                                                            │
│  ├─→ Agent 2: /craftsman:challenge on React components       │
│  │   └─→ Scope: src/Components/... (read-only analysis)      │
│  │                                                            │
│  └─→ Agent 3: /craftsman:challenge on test coverage          │
│      └─→ Scope: tests/... (read-only analysis)               │
│                                                               │
│  Results aggregated after all agents complete                │
│  /craftsman:verify (validates combined output)               │
│                                                               │
└──────────────────────────────────────────────────────────────┘

Timeline: All agents run concurrently → Aggregate → Verify
Duration: max(T1, T2, T3) = much faster than sequential
```

**Characteristics:**
- Multiple independent agents run simultaneously
- Each agent sees full codebase (read access)
- Agents can write to different files safely
- Requires explicit task decomposition

**Prerequisites:**
- None (works out of the box)

**Safety constraints:**
- No two agents can write to the same file
- No data dependencies between agents
- Read-heavy operations are ideal

**Estimating cost:**
- 1 Orchestrator call (Opus) to decompose
- N agent calls to Sonnet (parallel)
- Total: 1 + N calls
- Cost: ~$0.03-0.10 per feature (depends on task count)

### Team Agent Workflow

```
┌──────────────────────────────────────────────────────────────┐
│                  Shared Task List Database                   │
├──────────────────────────────────────────────────────────────┤
│ [PENDING]  Domain modeling                                   │
│ [PENDING]  API specification                                 │
│ [PENDING]  Backend scaffold (depends: Domain, API)           │
│ [PENDING]  Frontend scaffold (depends: API)                  │
│ [PENDING]  Security review (depends: Backend, Frontend)      │
│ [PENDING]  Integration tests (depends: all above)            │
└──────────────────────────────────────────────────────────────┘
                              ↑
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
    ┌─────────────┐    ┌─────────────┐   ┌──────────────┐
    │   Agent 1   │    │   Agent 2   │   │   Agent 3    │
    │ (Architect) │    │ (Frontend)  │   │  (Security)  │
    │             │    │             │   │              │
    │ Claims Task │    │ Claims Task │   │ Claims Task  │
    │ Updates w/  │    │ Updates w/  │   │ Updates w/   │
    │ result      │    │ result      │   │ result       │
    │             │    │             │   │              │
    │ Worktree 1  │    │ Worktree 2  │   │ Worktree 3   │
    └─────────────┘    └─────────────┘   └──────────────┘

Timeline: Tasks flow through agents based on dependencies
Duration: Critical path (T_total) — much faster than sequential
```

**Characteristics:**
- Team created with 2-5 specialized agents
- Shared task list with dependencies
- Agents pick available tasks (no blockers)
- Each agent works in isolated worktree
- Natural coordination via task status

**Prerequisites:**
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in Claude Code settings.json
- `teammates.mode: "iterm"` or `"tmux"` configured
- Claude Code v1.0.33+

**Team setup:**
```bash
# Create team interactively
/craftsman:team create

# Choose template or customize:
# 1. code-review (architecture + security + domain)
# 2. feature (backend + frontend + review)
# 3. security-audit (pen testing + architecture)
# 4. custom (interactive)
```

**Estimating cost:**
- Team Lead (Sonnet) orchestrates
- 2-5 team members (Sonnet) execute tasks
- Hooks (Haiku) validate in real-time
- Total: ~$0.15-0.40 per feature
- BUT: Covers larger scope, better quality

---

## Decision Flowchart

```
START
  │
  ├─ Do tasks have strict dependencies (B depends on A)?
  │  YES → Use Sequential
  │  NO  → Continue
  │
  ├─ Are all tasks in same domain (e.g., all backend)?
  │  YES → Continue
  │  NO  → Use Team (different domains → specialists)
  │
  ├─ Do tasks modify DIFFERENT files?
  │  YES → Can use Parallel
  │  NO  → Use Sequential or Team
  │
  ├─ Do you have CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS enabled?
  │  YES → Can use Team
  │  NO  → Use Parallel or Sequential
  │
  ├─ Is this a large feature (>2 hours of work)?
  │  YES → Team (better coordination)
  │  NO  → Sequential or Parallel
  │
  └─ Use this decision:
     - <30 min, few files → Sequential
     - 30-90 min, independent tasks → Parallel
     - >90 min, complex → Team
```

---

## Examples by Scenario

### Scenario 1: Implement User Registration (Small Feature)

**Scope:** Create User entity, repository, use case, controller

**Decision:** Sequential

**Workflow:**
```
/craftsman:design       → Design User aggregate
/craftsman:spec         → Write tests for User behavior
/craftsman:scaffold     → Generate User entity + VO
/craftsman:test         → Implement test cases
/craftsman:scaffold     → Generate UserRepository
/craftsman:scaffold     → Generate CreateUserUseCase
/craftsman:test         → Write use case tests
/craftsman:verify       → Validate all layers
/craftsman:git          → Commit
```

**Rationale:** Tasks depend on each other (entity before repository, use case depends on entity). One developer. Clear sequence.

---

### Scenario 2: Review Multi-Domain PR (15 changed files)

**Scope:** Review API endpoints, React components, database migrations, configuration

**Decision:** Parallel

**Workflow:**
```
/craftsman:parallel

Identify independent tasks:
  ✅ Backend API review (read-only)
  ✅ Frontend component review (read-only)
  ✅ Database migration review (read-only)
  ✅ Configuration audit (read-only)

All tasks are read-only → Safe to parallelize

Agents run concurrently, results aggregated
Estimated speedup: 3-4x faster than sequential review
```

**Rationale:** All tasks are independent read operations on different files. No conflicts. Much faster than reviewing sequentially.

---

### Scenario 3: Implement Payment Checkout System (Large Feature)

**Scope:**
- Domain: Payment, Order, Cart aggregates
- Backend: API endpoints, integrations
- Frontend: Checkout flow, payment form
- Infrastructure: Payment gateway config, webhooks
- Security: PCI compliance, fraud checks

**Decision:** Team

**Workflow:**
```
/craftsman:team create
  Template: feature (backend + frontend + review)
  Customize: Add security specialist

Team: [Architect, Backend, Frontend, Security]
Shared task list:
  - [ ] Design Payment & Order aggregates
  - [ ] Specify payment API endpoints
  - [ ] Scaffold backend domain layer
  - [ ] Implement payment provider integration
  - [ ] Specify frontend checkout flow
  - [ ] Build checkout React components
  - [ ] Implement payment form
  - [ ] Security review: PCI compliance
  - [ ] Integration tests
  - [ ] Load testing

Agents pick tasks based on expertise:
  Architect → Domain design
  Backend   → API endpoints, integration
  Frontend  → Checkout UI
  Security  → Compliance, fraud detection
```

**Rationale:** 
- Multiple domains (backend/frontend/security)
- Specialists needed (payment integrations, PCI compliance)
- Cross-cutting concerns (security review)
- High complexity justifies coordination overhead

---

## Cost Comparison (Hypothetical Feature)

Feature: "Add invoice generation system" (~60 lines, 3 files)

| Workflow | Setup | Execution | Cost | Total |
|----------|-------|-----------|------|-------|
| Sequential | 0 | 6 Sonnet calls | $0.024 | ~$0.024 |
| Parallel | 1 Opus | 3 Sonnet calls | $0.012 + $0.016 | ~$0.028 |
| Team | 1 Sonnet (lead) | 2 agents × 3 tasks | $0.008 + $0.048 | ~$0.056 |

**Notes:**
- Sequential is cheapest for simple tasks
- Team cost justified when quality/scope >> cost difference
- Parallel is sweet spot for medium tasks with no dependencies

---

## When Teams Exceed Budgets

If team cost is too high:

1. **Use Sequential** for simple features
2. **Use Parallel** for code reviews
3. **Use Team only for**:
   - Security-critical features
   - Large refactorings
   - Multi-domain implementations
   - When quality >> cost

4. **Optimize teams**:
   - Start with 2-3 agents (not 5)
   - Disable hooks if not needed: `agent_hooks: false` in config
   - Use sequential for dependent tasks in team workflow

---

## Command Integration Map

```
Sequential workflow:
  /craftsman:design → /craftsman:spec → /craftsman:scaffold → 
  /craftsman:test → /craftsman:verify → /craftsman:git

Parallel workflow:
  /craftsman:parallel [tasks] → /craftsman:verify → /craftsman:git

Team workflow:
  /craftsman:team create → [agents work via task list] → 
  /craftsman:verify → /craftsman:git
```

All workflows end with:
- `/craftsman:verify` - Final validation
- `/craftsman:git` - Atomic commit

---

## Troubleshooting

### "Can I switch workflows mid-way?"

Yes. You can:
1. Create a plan with `/craftsman:plan`
2. Execute tasks sequentially if dependencies arise
3. Parallelize later independent batches
4. Switch to team if complexity increases

### "Team agents are slow. Should I use Sequential instead?"

Maybe. Consider:
- Setup overhead: ~30 seconds (one-time)
- Execution: If parallel speedup > 30s, team wins
- Quality: If team catches issues, it's worth the overhead

### "Do all agents need special models?"

No. Agent model assignments are:
- Team Lead: Sonnet
- Team members: Sonnet  
- Hooks validation: Haiku (fast, cheap)
- You can downgrade non-critical agents to Haiku in team config

---

## Key Takeaways

| Scenario | Use |
|----------|-----|
| Task < 10 min, linear | Sequential |
| Task < 30 min, independent parts | Parallel |
| Task > 30 min, multiple domains | Team |
| Code review, multi-file | Parallel |
| High-security feature | Team |
| Learning the plugin | Sequential |
| Speed is critical | Parallel |
| Quality is critical | Team |

Choose based on your constraints (time, budget, quality, learning curve).
