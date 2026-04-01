# Command Chaining Guide

Learn how to chain AI Craftsman commands together into cohesive workflows. Each command has explicit inputs and outputs designed for clean composition.

## Philosophy

Commands are designed for composition:
- Each command is **focused** (does one thing well)
- Outputs are **usable** by next command in chain
- Dependencies are **explicit** (what needs to exist before running)
- Flows are **testable** (verify output at each step)

---

## Standard Workflow: Feature Implementation

The foundational flow for implementing a new feature from start to commit.

### Phase 1: Design & Specification

```
1. /craftsman:design
   Input:  Feature description
   Output: Domain model (entities, aggregates, value objects)
   Files:  Markdown design document in conversation

2. /craftsman:spec
   Input:  Design document from step 1
   Output: Test specifications (behavior/edge cases/errors)
   Files:  spec/ directory with test names and assertions
```

**Verify:** Design is unambiguous, spec test names are clear.

### Phase 2: Code Generation

```
3. /craftsman:scaffold
   Input:  Design + spec from steps 1-2
   Output: Implementation skeletons (entities, repositories, use cases)
   Files:  src/ directories created with interfaces
```

**Verify:** Scaffolded structure matches design layers (Domain → Application → Infrastructure).

### Phase 3: Implementation & Testing

```
4. /craftsman:test
   Input:  Scaffolded code from step 3
   Output: Test implementations (passing tests)
   Files:  tests/ files with full test bodies
```

**Verify:** All tests pass, code coverage is adequate.

### Phase 4: Quality & Verification

```
5. /craftsman:challenge
   Input:  Implemented code from steps 3-4
   Output: Architecture critique + recommendations
   Files:  Challenge report in conversation
```

**Verify:** Address critical issues before committing. Non-critical suggestions noted for future.

```
6. /craftsman:verify
   Input:  All code files
   Output: Quality report (layers, naming, patterns)
   Files:  Verification report
```

**Verify:** All checks pass (PHPStan, ESLint, dependency validation).

### Phase 5: Commit

```
7. /craftsman:git
   Input:  All modified files
   Output: Committed changes with message
   Files:  Git history updated
```

**Verify:** `git log` shows atomic, well-formed commit.

---

### Full Example: User Registration Feature

```bash
# Step 1: Design
/craftsman:design
> I need to implement user registration in an e-commerce system.
> Users have email, password (hashed), created_at, and soft-delete support.
> Emit UserRegistered domain event.

# Output: Design markdown with:
# - User entity structure
# - UserId value object
# - UserRepository interface
# - UserRegistered event

# Step 2: Specification
/craftsman:spec

# Claude reads design and writes specs:
# SHOULD
# - Accept valid emails
# - Hash password on creation
# - Emit UserRegistered event
# SHOULD NOT
# - Validate email existence (external)
# EDGE CASES
# - Empty email → throws
# - Duplicate email → throws (if not soft-delete)

# Step 3: Scaffold
/craftsman:scaffold

# Output:
# src/Domain/Entity/User.php (skeleton)
# src/Domain/ValueObject/UserId.php (skeleton)
# src/Domain/Repository/UserRepositoryInterface.php
# src/Domain/Event/UserRegistered.php (event)
# src/Application/UseCase/RegisterUser/...
# src/Infrastructure/Doctrine/DoctrineUserRepository.php

# Step 4: Test
/craftsman:test

# Output:
# tests/Unit/Domain/Entity/UserTest.php (all tests implemented)
# tests/Unit/Domain/ValueObject/UserIdTest.php
# tests/Unit/Application/RegisterUserUseCaseTest.php
# tests/Integration/Infrastructure/DoctrineUserRepositoryTest.php

# Step 5: Challenge
/craftsman:challenge

# Claude reviews code and suggests:
# - Missing error handling in repository
# - Event dispatch missing in use case
# - Consider Email value object (implicit)

# Fix issues, then continue

# Step 6: Verify
/craftsman:verify

# Output:
# ✅ PHPStan: 0 errors
# ✅ Domain layers: clean
# ✅ Naming conventions: OK

# Step 7: Git
/craftsman:git

# Creates commit:
# feat(user): implement user registration
#
# - Create User entity with email and hashed password
# - Add UserId value object for type safety
# - Implement UserRepository interface
# - Add UserRegistered domain event
# - Add comprehensive unit and integration tests
```

---

## Workflow: Bug Debugging

Quick, focused debugging flow when something is broken.

```
1. /craftsman:debug
   Input:  Error message + stack trace
   Output: Root cause analysis + hypotheses
   Files:  Debug session notes

2. /craftsman:test
   Input:  Suspected root cause from debug
   Output: Regression test (captures the bug)
   Files:  tests/ with new test case

3. /craftsman:scaffold
   Input:  Test + analysis
   Output: Fix implementation
   Files:  Modified source files

4. /craftsman:verify
   Input:  All code files
   Output: Quality report
   Files:  Verification report

5. /craftsman:git
   Input:  All modified files
   Output: Committed fix
   Files:  Git history
```

### Example: Memory Leak in Caching Layer

```bash
# Step 1: Debug
/craftsman:debug
> My Node.js app leaks ~10MB per hour.
> Heap profile shows objects accumulating in CacheManager.cache Map.

# Output:
# Root cause: Cache never evicts old entries
# Hypothesis 1: No TTL mechanism
# Hypothesis 2: LRU not implemented
# Hypothesis 3: Manual clear not called

# Step 2: Test (capture bug)
/craftsman:test
> Write a test that demonstrates memory leak:
> Create 1000 cache entries, verify old ones are evicted

# Output: tests/CacheManagerTest.php with test case that initially fails

# Step 3: Fix
/craftsman:scaffold

# Output:
# src/CacheManager.js (modified with TTL + LRU eviction)

# Step 4: Verify
/craftsman:verify

# Step 5: Commit
/craftsman:git
```

---

## Workflow: Code Refactoring

Large refactoring flow for systematic code improvements.

```
1. /craftsman:plan
   Input:  Refactoring scope (e.g., "remove setters everywhere")
   Output: Structured plan with tasks and dependencies
   Files:  Plan document

2. /craftsman:refactor
   Input:  Plan + current code
   Output: Refactored code
   Files:  Modified source files

3. /craftsman:test
   Input:  Refactored code
   Output: Tests updated for new structure
   Files:  tests/ files updated

4. /craftsman:verify
   Input:  All code files
   Output: Quality report
   Files:  Verification report

5. /craftsman:git
   Input:  All modified files
   Output: Committed refactoring
   Files:  Git history
```

### Example: Remove All Setters

```bash
# Step 1: Plan
/craftsman:plan
> Remove all setters from our codebase.
> Replace with immutable pattern (new objects via methods).

# Output:
# TASK-001: Find all setters (grep)
# TASK-002: Convert setters to factory methods (10 files)
# TASK-003: Update tests (5 test files)
# TASK-004: Verify no regressions
# Estimated: 2 hours

# Step 2: Refactor
/craftsman:refactor
> Use the plan. Systematically remove setters.

# Output: Source files updated

# Step 3: Update Tests
/craftsman:test

# Output: Test files updated for immutable pattern

# Step 4: Verify
/craftsman:verify

# Step 5: Commit
/craftsman:git
```

---

## Workflow: Parallel Task Execution

When you have independent tasks that can run simultaneously.

```
1. /craftsman:plan
   Input:  Multiple independent tasks
   Output: Decomposed task list
   Files:  Plan document

2. /craftsman:parallel
   Input:  Plan from step 1
   Output: Results from all independent agents
   Files:  Multiple modified files (different scopes)

3. /craftsman:verify
   Input:  All code files
   Output: Quality report
   Files:  Verification report

4. /craftsman:git
   Input:  All modified files
   Output: Committed changes
   Files:  Git history
```

### Example: Multi-Domain Code Review

```bash
# Step 1: Plan (decompose)
/craftsman:plan
> Review this PR across 3 domains: API, Frontend, Tests.

# Output:
# TASK-A: API layer review (src/API/...)
# TASK-B: React components review (src/Components/...)
# TASK-C: Test coverage review (tests/...)
# All tasks: independent, can run in parallel

# Step 2: Parallelize
/craftsman:parallel

# Output:
# Agent 1: API critique
# Agent 2: React critique
# Agent 3: Test coverage critique
# Results aggregated

# Step 3: Verify all files
/craftsman:verify

# Step 4: Commit
/craftsman:git
```

---

## Workflow: Team-Based Large Feature

Complex feature requiring multiple specialists.

```
1. /craftsman:team create
   Input:  Feature description
   Output: Team assembled, task list created
   Files:  .claude/teams/<name>.yml

2. [Agents work via shared task list]
   - Each agent claims available tasks
   - Updates task list with results
   - Respects dependencies
   Duration: Until all tasks complete

3. /craftsman:verify
   Input:  All code files
   Output: Quality report
   Files:  Verification report

4. /craftsman:git
   Input:  All modified files
   Output: Committed changes
   Files:  Git history
```

### Example: Payment Processing Feature

```bash
# Step 1: Create team
/craftsman:team create
> Implement payment processing system with Stripe integration

# Template: feature (backend + frontend + review)
# Customize: Add payment specialist

# Output: Team created with 3 agents
# Shared task list:
# [ ] Design Payment aggregate
# [ ] Design Order aggregate
# [ ] Specify payment API endpoints
# [ ] Scaffold payment domain layer
# [ ] Scaffold payment use cases
# [ ] Integrate Stripe SDK
# [ ] Build checkout form
# [ ] Add PCI compliance tests
# [ ] Integration tests

# Step 2: Agents execute (automatic)
# Architect claims: Domain design tasks
# Backend claims: API + integration tasks
# Frontend claims: Checkout form tasks
# Each agent updates task list

# Step 3: Verify
/craftsman:verify

# Step 4: Commit
/craftsman:git
```

---

## Command Output Types

Understanding what each command produces helps chain them effectively.

| Command | Output Type | Used By |
|---------|-------------|---------|
| `/craftsman:design` | Markdown document | spec, scaffold |
| `/craftsman:spec` | Test specifications | scaffold, test |
| `/craftsman:scaffold` | Source code skeletons | test, challenge |
| `/craftsman:test` | Test implementations | verify, git |
| `/craftsman:challenge` | Critique + recommendations | Manual review |
| `/craftsman:verify` | Quality report | Manual review |
| `/craftsman:git` | Committed changes | Repo history |
| `/craftsman:debug` | Root cause analysis | Manual review |
| `/craftsman:refactor` | Refactored source | test, verify, git |
| `/craftsman:plan` | Structured plan | parallel, team |
| `/craftsman:parallel` | Aggregated results | verify, git |
| `/craftsman:team` | Team + task list | Manual coordination |

---

## Chaining Best Practices

### 1. Verify Output Before Next Step

```bash
# DON'T: Chain blindly
/craftsman:design → /craftsman:spec → /craftsman:scaffold → ...

# DO: Verify at each step
/craftsman:design
# Read the design, ask: Is this right?
# If not, re-run design with clarification

/craftsman:spec
# Read the specs, ask: Are the test names clear?

/craftsman:scaffold
# Check the scaffolded structure
```

### 2. Save Context Between Commands

Use markdown notes to preserve:
- Design decisions
- Specification details
- Test strategy
- Known risks

```markdown
## Implementation Notes

### Design Decision
- User aggregate includes email + password
- Email is value object for validation
- Soft-delete via deleted_at field

### Known Risks
- Password hashing must use bcrypt (not MD5)
- UserRepository must check for soft-deleted users
```

### 3. Use Challenge to Catch Issues Early

Don't skip `/craftsman:challenge` before testing.

```bash
/craftsman:scaffold     # Generate code
/craftsman:challenge    # Review architecture BEFORE tests
# If issues: fix, then test
/craftsman:test         # Now safe to test
```

### 4. Parallelize When Safe

Use `/craftsman:parallel` for:
- Code review (multiple domains)
- Multiple independent features
- Multi-file refactoring

But NOT for:
- Dependent tasks
- Same file modifications
- Merged results

---

## Debugging Chain Failures

### "Test failed after scaffold"

```
Likely cause: Spec misunderstood by scaffold command
Solution: 
1. Review spec output (was it detailed enough?)
2. Re-run scaffold with clarified spec
3. Re-run tests
```

### "Scaffold output doesn't match design"

```
Likely cause: Design lacked detail
Solution:
1. Re-run design with examples
2. Re-run scaffold pointing to enhanced design
```

### "Challenge found critical issue"

```
Don't just commit anyway. Either:
1. Fix the issue in scaffold
2. Update code to address critique
3. Re-test with changes
4. Re-verify before git
```

---

## Integration with Git

All chains should end with `/craftsman:git` for atomic commits.

The git command:
- Detects all modified files
- Generates conventional commit message
- Creates single atomic commit
- Validates commit follows conventions

Example:
```bash
feat(payment): implement checkout with Stripe integration

- Add Payment aggregate with status state machine
- Create Order aggregate with line items
- Implement CheckoutUseCase
- Scaffold PaymentRepository
- Add comprehensive integration tests
- Implement PCI-DSS compliance checks

Fixes: #42
```

---

## Command Execution Time

Reference for planning chains:

| Command | Typical Time | Model |
|---------|--------------|-------|
| `/craftsman:design` | 2-5 min | Sonnet |
| `/craftsman:spec` | 2-3 min | Sonnet |
| `/craftsman:scaffold` | 3-5 min | Sonnet |
| `/craftsman:test` | 3-5 min | Sonnet |
| `/craftsman:challenge` | 3-5 min | Opus |
| `/craftsman:verify` | 1-2 min | Haiku |
| `/craftsman:git` | <1 min | Haiku |
| `/craftsman:debug` | 3-5 min | Sonnet |
| `/craftsman:refactor` | 3-8 min | Sonnet |
| `/craftsman:plan` | 3-5 min | Opus |
| `/craftsman:parallel` | 5-10 min (N tasks) | Opus + N×Sonnet |
| `/craftsman:team` | 10-30 min (full feature) | Sonnet (team lead) + Sonnet (agents) |

**Total feature chain:** ~30-45 minutes for complete implementation + review.

---

## Next Steps

- Start with [Sequential workflow](#standard-workflow-feature-implementation)
- Graduate to [Parallel tasks](#workflow-parallel-task-execution) for reviews
- Adopt [Team workflow](#workflow-team-based-large-feature) for large features
