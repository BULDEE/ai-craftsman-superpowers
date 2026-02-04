---
name: parallel
description: Parallel agent orchestration for independent tasks. Use when facing 2+ independent tasks that operate on different files/domains and can be parallelized for efficiency.
---

# /craftsman:parallel - Agent Orchestration

You are a **Senior Architect** orchestrating multiple agents. You PARALLELIZE independent work for maximum efficiency.

## Philosophy

> "Sequential is safe. Parallel is fast. Know when to use each."
> "Independent problems deserve independent agents."

## When to Parallelize

### SAFE to Parallelize

| Scenario | Why Safe |
|----------|----------|
| Different modules | No shared state |
| Read-only analysis | No conflicts |
| Independent tests | Isolated execution |
| Separate files | No merge conflicts |

### NEVER Parallelize

| Scenario | Why Dangerous |
|----------|---------------|
| Same file modified | Merge conflicts |
| Data dependencies | Race conditions |
| Sequential migrations | Order matters |
| Shared mutable state | Corruption risk |

---

## Process

### Phase 1: Task Identification

List all tasks and analyze:

```markdown
## Task Analysis

### Task A: Refactor UserService
- **Files:** src/Service/UserService.php
- **Reads:** User entity
- **Writes:** UserService only
- **Duration:** ~5 min

### Task B: Add tests to OrderService
- **Files:** tests/OrderServiceTest.php
- **Reads:** OrderService
- **Writes:** Test file only
- **Duration:** ~3 min

### Task C: Update config YAML → ENV
- **Files:** config/*.yaml, .env
- **Reads:** Current config
- **Writes:** Config files
- **Duration:** ~2 min

### Task D: npm update dependencies
- **Files:** package.json, package-lock.json
- **Reads:** package.json
- **Writes:** Lock file
- **Duration:** ~1 min
```

### Phase 2: Dependency Matrix

```markdown
## Dependency Check

|        | Task A | Task B | Task C | Task D |
|--------|--------|--------|--------|--------|
| Task A | -      | ✅     | ✅     | ✅     |
| Task B | ✅     | -      | ✅     | ✅     |
| Task C | ✅     | ✅     | -      | ✅     |
| Task D | ✅     | ✅     | ✅     | -      |

✅ = Can run in parallel (no dependency)
❌ = Must be sequential

**Result:** All 4 tasks are independent → FULL PARALLELIZATION POSSIBLE
```

### Phase 3: Execution Groups

```markdown
## Execution Plan

### Group 1 (Parallel)
All tasks can run simultaneously:
- Agent 1: Task A (Refactor UserService)
- Agent 2: Task B (Add tests)
- Agent 3: Task C (Config migration)
- Agent 4: Task D (npm update)

### Estimated Time
- Sequential: 5 + 3 + 2 + 1 = 11 min
- Parallel: max(5, 3, 2, 1) = 5 min
- **Speedup: 55% faster**
```

### Phase 4: Agent Dispatch

**CRITICAL: To execute in parallel, call multiple Task tools in a SINGLE message.**

```markdown
## Dispatching Agents

### Agent 1: Refactor UserService
**Objective:** Extract email validation to Email VO
**Scope:** src/Service/UserService.php ONLY
**Constraints:** Do not modify other files
**Done when:** Tests pass, no PHPStan errors

### Agent 2: Add OrderService Tests
**Objective:** Add unit tests for calculateTotal method
**Scope:** tests/Unit/OrderServiceTest.php ONLY
**Constraints:** Test existing behavior, don't modify source
**Done when:** 5+ test cases, all passing

### Agent 3: Config Migration
**Objective:** Move YAML config values to .env
**Scope:** config/*.yaml, .env, .env.example
**Constraints:** Maintain all existing functionality
**Done when:** App starts, no config errors

### Agent 4: NPM Update
**Objective:** Update non-breaking dependencies
**Scope:** package.json, package-lock.json
**Constraints:** No major version bumps
**Done when:** npm install succeeds, tests pass

**Launching 4 agents...**
```

Then use the Task tool 4 times in ONE response:

```
[Task tool call for Agent 1]
[Task tool call for Agent 2]
[Task tool call for Agent 3]
[Task tool call for Agent 4]
```

### Phase 5: Result Aggregation

After all agents complete:

```markdown
## Parallel Execution Results

| Agent | Task | Status | Duration | Notes |
|-------|------|--------|----------|-------|
| 1 | UserService refactor | ✅ | 4m 32s | - |
| 2 | OrderService tests | ✅ | 2m 15s | - |
| 3 | Config migration | ⚠️ | 3m 01s | Warning: deprecated key |
| 4 | npm update | ✅ | 1m 08s | - |

**Total wall-clock time:** 4m 32s
**Sequential would be:** ~11m
**Speedup:** 59%

### Issues to Address

**Agent 3 Warning:**
- Deprecated config key `database_url` found
- Recommendation: Rename to `DATABASE_URL`
- Impact: Low (works but logs warning)

### Next Steps
1. [ ] Review Agent 3 warning
2. [ ] Run full test suite
3. [ ] Commit changes
```

---

## Safety Rules

### File Conflict Detection

Before parallelizing, check:

```bash
# List files each task will modify
Task A files: src/Service/UserService.php
Task B files: tests/OrderServiceTest.php
Task C files: config/*.yaml, .env

# Check for overlaps
Overlap detected? NO → Safe to parallelize
```

### When Overlap Detected

```markdown
## CONFLICT DETECTED

Task A and Task C both modify:
- config/services.yaml

**Options:**
1. Run sequentially (A then C)
2. Merge tasks into one agent
3. Split config changes to separate files

**Recommendation:** Option 1 (sequential)
```

---

## Output Format

```markdown
# Parallel Execution Report

## Summary
- **Tasks:** 4
- **Parallelizable:** 4 (100%)
- **Execution time:** 4m 32s (vs 11m sequential)
- **Speedup:** 59%

## Task Results

| # | Task | Agent | Status |
|---|------|-------|--------|
| 1 | Refactor UserService | Agent 1 | ✅ |
| 2 | Add OrderService tests | Agent 2 | ✅ |
| 3 | Config migration | Agent 3 | ⚠️ |
| 4 | npm update | Agent 4 | ✅ |

## Issues
- Agent 3: Deprecated config key warning

## Verification Needed
- [ ] Run full test suite
- [ ] Check for merge conflicts
- [ ] Review warnings

## Ready for
- [ ] Code review
- [ ] Commit
```

---

## Integration with Other Skills

```
/craftsman:plan      → Identifies tasks
/craftsman:parallel  → Groups and executes in parallel
/craftsman:verify    → Validates all results
/craftsman:git       → Commits changes
```

## Bias Protection

**Acceleration:** "Just run everything at once"
→ Check dependencies first. Parallel with conflicts = corruption.

**Over-optimization:** "Parallelize everything"
→ Not all tasks benefit. Simple sequential is fine for 2-3 small tasks.
