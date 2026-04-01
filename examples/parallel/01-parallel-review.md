# Example: Parallel Code Review Workflow

This example demonstrates using `/craftsman:parallel` to review a complex pull request across multiple domains simultaneously.

## Context: The Pull Request

**PR:** #247 - "Refactor order processing with async jobs"

**Changed files:** 28 files across 4 domains
- Backend API (8 files): New order service, async job handlers
- React Frontend (12 files): Order form, status dashboard, notifications
- Infrastructure (5 files): Job queue config, database migrations
- Tests (3 files): Unit and integration tests

**Review approach:** Sequential review would take 60-90 minutes. Parallel review can do it in 15-20 minutes by analyzing each domain independently.

---

## Step 1: Decompose Review Tasks

```bash
/craftsman:plan
> We need to review PR #247 across 4 independent domains.
> What are the key review areas?
```

**Output: Task Decomposition**

```markdown
## Review Decomposition: PR #247

### Domain 1: Backend Service Layer
**Files affected:** 8
- src/Service/OrderService.php
- src/Service/OrderJobHandler.php
- src/Repository/OrderRepository.php
- src/ValueObject/OrderStatus.php
- src/Event/OrderCreated.php
- tests/Unit/Service/OrderServiceTest.php
- tests/Integration/OrderRepository/DoctrinePersistenceTest.php
- config/services.yaml (job queue config)

**Review focus:**
- Clean architecture: Is OrderService in the right layer?
- Job queue integration: Are jobs properly serialized?
- Idempotency: Can the job be retried safely?
- Error handling: What happens if job fails 3 times?
- Events: Are domain events correctly emitted?

**Estimated time:** 8 minutes
**Scope:** Read-only, no modifications needed during review

---

### Domain 2: React Frontend UI
**Files affected:** 12
- src/components/Order/OrderForm.tsx
- src/components/Order/OrderStatus.tsx
- src/components/Order/OrderTimeline.tsx
- src/hooks/useOrderPolling.ts
- src/hooks/useNotifications.ts
- src/types/order.ts
- src/api/orderApi.ts
- src/styles/OrderForm.module.scss
- tests/components/Order/OrderForm.test.tsx
- tests/hooks/useOrderPolling.test.tsx
- README.md (updated docs)

**Review focus:**
- Component structure: Are components properly separated?
- Hooks: Is useOrderPolling efficient (polling interval)?
- API integration: Does component correctly handle async states?
- Accessibility: Forms, error messages, loading states
- TypeScript: No `any`, proper types
- Tests: Coverage adequate for changes?

**Estimated time:** 12 minutes
**Scope:** Read-only, no modifications needed

---

### Domain 3: Infrastructure & Configuration
**Files affected:** 5
- docker-compose.yml (Redis config for job queue)
- config/jobs.yaml (job handlers mapping)
- config/database.yaml (new schema)
- migrations/2026_03_30_create_jobs_table.sql
- k8s/deployment.yaml (job worker replicas)

**Review focus:**
- Database migration: No breaking changes?
- Job queue: Correct serialization format?
- Scaling: Can system handle 1000 jobs/min?
- Monitoring: Are job failures logged?
- Backwards compatibility: Can we rollback safely?

**Estimated time:** 8 minutes
**Scope:** Read-only, no modifications needed

---

### Domain 4: Tests
**Files affected:** 3
- tests/Unit/Service/OrderServiceTest.php
- tests/Integration/OrderRepository/DoctrinePersistenceTest.php
- tests/Feature/OrderProcessingEndToEndTest.php

**Review focus:**
- Test coverage: Do tests cover new async behavior?
- Test strategy: Are edge cases covered (job retry, timeout)?
- Integration tests: Do they test the full flow?
- Flakiness: Could tests fail randomly (timing issues)?
- Performance: Are tests running in reasonable time?

**Estimated time:** 5 minutes
**Scope:** Read-only, analysis only

---

## Task Dependency Analysis

|        | Backend | Frontend | Infra | Tests |
|--------|---------|----------|-------|-------|
| Backend | -       | ✅       | ✅    | ✅    |
| Frontend | ✅     | -        | ✅    | ✅    |
| Infra  | ✅      | ✅       | -     | ✅    |
| Tests  | ✅      | ✅       | ✅    | -     |

**All tasks are independent read-only analyses:** Safe for full parallelization
```

---

## Step 2: Execute Parallel Reviews

```bash
/craftsman:parallel
```

Claude orchestrates 4 agents simultaneously:

### Agent 1: Backend Service Review

**Task:** Review order service layer, job handling, domain events

**Input:**
```
Review PR #247 backend changes:

Files:
- src/Service/OrderService.php (NEW)
- src/Service/OrderJobHandler.php (NEW)
- src/Repository/OrderRepository.php (MODIFIED)
- src/ValueObject/OrderStatus.php (MODIFIED)
- src/Event/OrderCreated.php (MODIFIED)
- config/services.yaml (MODIFIED)

Focus areas:
1. Clean architecture: Service, Repository, Value Object placement
2. Job queue integration: Serialization, error handling, retries
3. Idempotency: Safe to retry jobs?
4. Domain events: Correct emission and subscribers
5. Error scenarios: Job fails 3 times, what happens?

Output format:
- Findings grouped by severity (critical, warning, info)
- Quote problematic code snippets
- Suggest specific fixes
```

**Output: Backend Review Report**

```markdown
## Backend Service Review

### Critical Issues
None ✅

### Warnings

**W1: Job Serialization**
Location: OrderJobHandler.php:42
```php
public function handle(OrderCreatedEvent $event): void {
    dispatch(new ProcessOrderJob($event));  // Event passed directly
}
```
Issue: Domain event is not serialized for the queue. If event structure changes, old jobs in queue will fail.
Suggestion: Pass only the OrderId to the job, reconstruct event from repository.

**W2: Error Handling**
Location: OrderJobHandler.php:65
```php
try {
    $this->service->processOrder($orderId);
} catch (Exception $e) {
    Log::error('Order processing failed: ' . $e->getMessage());
    // No retry mechanism specified
}
```
Issue: Job fails silently after one attempt. No exponential backoff or dead-letter queue.
Suggestion: Use queue driver's native retry mechanism (Laravel: dispatch()->retry(3)->delay(...))

**W3: Missing Idempotency Check**
Location: OrderService.php:15
```php
public function processOrder(OrderId $id): void {
    $order = $this->repository->findById($id);
    $order->process();  // What if already processed?
    $this->repository->save($order);
}
```
Issue: Job retry could process the same order twice.
Suggestion: Add guard: `if ($order->isProcessed()) return;`

### Positive Findings

**P1: Event Design**
Location: src/Event/OrderCreated.php
```php
final class OrderCreated extends DomainEvent {
    public function __construct(
        readonly OrderId $orderId,
        readonly Money $totalAmount,
    ) {}
}
```
Good: Value objects in event (OrderId, Money). Immutable. Clean.

**P2: Service Dependency Injection**
Location: OrderService.php:5
```php
public function __construct(
    private readonly OrderRepositoryInterface $repository,
    private readonly EventPublisherInterface $publisher,
) {}
```
Good: Dependencies injected, interfaces used. Testable.

**P3: Repository Abstraction**
The new OrderRepository interface is clean and follows DDD patterns.

### Summary
- Critical issues: 0
- Warnings: 3 (job serialization, error handling, idempotency)
- Positive: 3
- Recommendation: Address warnings before merge. Quick fixes (~10 min).
```

---

### Agent 2: Frontend UI Review

**Task:** Review React components, hooks, TypeScript, accessibility

**Input:**
```
Review PR #247 frontend changes:

Files:
- src/components/Order/OrderForm.tsx (NEW)
- src/components/Order/OrderStatus.tsx (NEW)
- src/hooks/useOrderPolling.ts (NEW)
- src/api/orderApi.ts (MODIFIED)
- tests/components/Order/OrderForm.test.tsx (NEW)

Focus areas:
1. Component design: Separation of concerns, prop drilling
2. Hooks: useOrderPolling efficiency (polling interval, cleanup)
3. API integration: Async states (loading, error, success)
4. Accessibility: ARIA labels, form validation errors
5. TypeScript: No `any`, proper types
6. Test coverage: Edge cases, error scenarios

Output format:
- Findings grouped by severity
- Code snippets with explanations
- Specific recommendations
```

**Output: Frontend Review Report**

```markdown
## Frontend UI Review

### Critical Issues

**C1: Memory Leak in useOrderPolling**
Location: src/hooks/useOrderPolling.ts:18
```tsx
useEffect(() => {
    const interval = setInterval(() => {
        fetchOrderStatus();
    }, 3000);  // No cleanup!
}, []);
```
Issue: Interval is never cleared. Component unmounts → memory leak.
Suggestion:
```tsx
useEffect(() => {
    const interval = setInterval(() => {
        fetchOrderStatus();
    }, 3000);
    return () => clearInterval(interval);  // Add cleanup
}, []);
```

**C2: Infinite Render Loop Risk**
Location: src/components/Order/OrderForm.tsx:34
```tsx
useEffect(() => {
    setFormData({...formData, quantity: 1});  // formData as dependency
}, [formData]);  // CIRCULAR!
```
Issue: Effect depends on formData, but also modifies it → infinite loop.
Suggestion: Separate initial setup (no deps) from updates (specific deps).

### Warnings

**W1: Polling Interval Too Aggressive**
Location: src/hooks/useOrderPolling.ts:5
```tsx
const POLLING_INTERVAL = 3000;  // 3 seconds
```
Issue: Every 3 seconds = 1200 API calls/hour. Will overwhelm server on high traffic.
Suggestion: Use exponential backoff or Server-Sent Events instead.

**W2: Missing Error Handling**
Location: OrderForm.tsx:50
```tsx
const order = await api.createOrder(data);
// What if network fails? API error? Timeout?
```
Issue: No error boundary or error state. User sees nothing if request fails.
Suggestion: Add try-catch, set error state, show user message.

**W3: TypeScript: Implicit `any`**
Location: src/api/orderApi.ts:12
```tsx
export function getOrder(id) {  // Missing type annotation
    return fetch(`/api/orders/${id}`);
}
```
Suggestion: Add type annotations: `getOrder(id: string): Promise<Order>`

### Positive Findings

**P1: Component Isolation**
OrderStatus is a pure presentational component. No side effects. Reusable.

**P2: Accessibility**
Forms have proper labels, error messages are aria-live. Good practice.

**P3: Test Strategy**
Test fixtures are well-structured. Tests are deterministic (no flakiness).

### Summary
- Critical issues: 2 (memory leak, infinite loop)
- Warnings: 3 (polling interval, error handling, TypeScript)
- Positive: 3
- Recommendation: Fix critical issues before merge. Test in React StrictMode to catch effects.
```

---

### Agent 3: Infrastructure Review

**Task:** Review database schema, job queue config, deployment settings

**Input:**
```
Review PR #247 infrastructure changes:

Files:
- docker-compose.yml (MODIFIED)
- config/jobs.yaml (NEW)
- migrations/2026_03_30_create_jobs_table.sql (NEW)
- k8s/deployment.yaml (MODIFIED)

Focus areas:
1. Database migration: Correctness, backwards compatibility, rollback plan
2. Job queue: Configuration, serialization format, monitoring
3. Scaling: Can system handle traffic spike?
4. Monitoring: Are failures logged and alertable?
5. Deployment: Health checks, zero-downtime migration

Output format:
- Findings grouped by severity
- Migration analysis
- Scaling assessment
```

**Output: Infrastructure Review Report**

```markdown
## Infrastructure Review

### Critical Issues

**C1: Missing Rollback Plan for Migration**
Location: migrations/2026_03_30_create_jobs_table.sql
```sql
CREATE TABLE jobs (
    id BIGINT PRIMARY KEY,
    status VARCHAR(20),
    ...
);
ALTER TABLE jobs ADD CONSTRAINT ...;
```
Issue: Migration has no DOWN step. If deployment fails, we can't rollback.
Suggestion: Create down migration:
```sql
-- down
DROP TABLE jobs CASCADE;
```

### Warnings

**W1: Job Queue Configuration Incomplete**
Location: config/jobs.yaml:5
```yaml
queue:
  driver: redis
  connection: default
  retry_after: 300  # 5 minutes
  timeout: 60       # 60 seconds
  # Missing: max_retries, dead_letter_queue
```
Issue: No max retries specified. Jobs might retry forever or be lost.
Suggestion: Add max_retries and route to dead_letter_queue after failures.

**W2: No Monitoring/Alerting for Failed Jobs**
Location: k8s/deployment.yaml (no changes)
Issue: If job queue fills up or jobs fail, no alert. Operations team won't know.
Suggestion: Add Prometheus metrics, set alert threshold (e.g., >100 failed jobs/min).

**W3: Scaling Not Tested Under Load**
Location: k8s/deployment.yaml:12
```yaml
job-worker:
  replicas: 2  # Hardcoded
```
Issue: Can 2 replicas handle 1000 orders/day? Unknown.
Suggestion: Load test with k6, measure throughput per replica.

### Positive Findings

**P1: Backwards Compatible Migration**
New `jobs` table doesn't touch existing tables. Safe to deploy.

**P2: Proper Health Checks**
Docker health check for Redis queue presence. Good monitoring foundation.

**P3: Immutable Job Configuration**
Config loaded at startup, not changed during runtime. Predictable.

### Summary
- Critical issues: 1 (missing rollback)
- Warnings: 3 (queue config, monitoring, load testing)
- Positive: 3
- Recommendation: Add rollback migration before merge. Consider load test optional (can do in staging).
```

---

### Agent 4: Test Coverage Review

**Task:** Review test coverage, edge cases, test strategy

**Input:**
```
Review PR #247 test changes:

Files:
- tests/Unit/Service/OrderServiceTest.php (NEW)
- tests/Integration/OrderRepository/DoctrinePersistenceTest.php (MODIFIED)
- tests/Feature/OrderProcessingEndToEndTest.php (NEW)

Focus areas:
1. Coverage: What % of new code is tested?
2. Edge cases: Job retry, timeout, concurrent orders?
3. Test quality: Unit vs integration vs feature tests
4. Determinism: Can tests fail randomly?
5. Performance: How long do tests run?

Output format:
- Coverage analysis
- Missing test scenarios
- Performance assessment
```

**Output: Test Coverage Report**

```markdown
## Test Coverage Review

### Coverage Analysis

**New code in PR:** 145 lines
**Lines tested:** 118 lines
**Coverage:** 81%

**Breakdown:**
- OrderService: 95% (18/19 methods tested)
- OrderJobHandler: 72% (5/7 methods tested)
- OrderRepository changes: 88% (7/8 methods tested)

### Findings

**W1: Missing Test Cases**

1. Job Retry Scenario
Location: tests/Unit/Service/OrderServiceTest.php
Missing: What happens when OrderService throws exception? Job should retry.
Suggestion: Add test case:
```php
public function testJobRetriesOnServiceFailure() {
    // Arrange: Mock repository to throw exception on first call
    // Act: Call job handler
    // Assert: Job marked for retry
}
```

2. Concurrent Order Processing
Missing: Two jobs process same order simultaneously. What happens?
Suggestion: Add integration test with race condition.

3. Job Timeout
Missing: What if job takes >60 seconds?
Suggestion: Add test that verifies timeout handling.

### Positive Findings

**P1: Feature Test is Comprehensive**
OrderProcessingEndToEndTest covers full flow:
1. Create order → 2. Trigger job → 3. Verify processing → 4. Check status
Good testing strategy.

**P2: Mocking Strategy**
Unit tests properly mock Repository and EventPublisher. Fast and isolated.

**P3: Deterministic Tests**
No timing-dependent assertions. Tests will pass consistently.

### Performance

**Test execution time:** 2.3 seconds (small test suite, good)
**Test isolation:** Each test cleans up after itself. No flakiness risk.

### Summary
- Coverage: 81% (acceptable)
- Missing scenarios: 3 (job retry, concurrency, timeout)
- Test quality: Good
- Performance: Excellent (fast tests)
- Recommendation: Add 3 missing edge case tests before merge.
```

---

## Step 3: Aggregate Results

```bash
/craftsman:parallel [results aggregation]
```

**Consolidated Review Report:**

```markdown
# PR #247 Review Summary

## Domains Analyzed (Parallel)
- ✅ Backend Service (8 min)
- ✅ React Frontend (12 min)
- ✅ Infrastructure (8 min)
- ✅ Test Coverage (5 min)

**Total review time:** 12 min (max) vs 33 min (sequential) = 64% speedup

## Findings Summary

### By Severity

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 3     | Must fix before merge |
| Warning  | 9     | Strongly recommended |
| Info     | 9     | Nice-to-have |

### By Domain

| Domain | Critical | Warning | Positive |
|--------|----------|---------|----------|
| Backend | 0 | 3 | 3 |
| Frontend | 2 | 3 | 3 |
| Infrastructure | 1 | 3 | 3 |
| Tests | 0 | 3 | 3 |

### Critical Issues Requiring Fixes

1. **Frontend: Memory leak in useOrderPolling**
   - Fix: Add cleanup function to interval
   - Time: 2 minutes
   - Severity: High (production blocker)

2. **Frontend: Infinite render loop in OrderForm**
   - Fix: Remove circular dependency in useEffect
   - Time: 3 minutes
   - Severity: High (app crash risk)

3. **Infrastructure: Missing rollback migration**
   - Fix: Create down migration for jobs table
   - Time: 5 minutes
   - Severity: High (deployment safety)

### Recommended Fixes (Before Merge)

**Backend:**
- W1: Fix job serialization (pass OrderId only)
- W2: Add queue retry mechanism
- W3: Add idempotency guard

**Frontend:**
- W1: Change polling interval from 3s to 10s
- W2: Add error boundary and error handling
- W3: Add type annotations to API functions

**Infrastructure:**
- W2: Add max_retries and dead_letter_queue config
- W3: Plan load test in staging

**Tests:**
- Add 3 missing edge case tests (retry, concurrency, timeout)

## Recommendation

**Do not merge as-is.**

**Fix critical issues (2-3 items):** ~10 minutes
**Fix recommended warnings (6 items):** ~20 minutes
**Total additional work:** ~30 minutes

**After fixes:** Ready to merge

## Next Steps

1. [ ] Assign fixes to reviewer/developer
2. [ ] Run second verification pass on fixed code
3. [ ] Approve and merge
4. [ ] Deploy to staging, run load test
5. [ ] Deploy to production

---

## Why Parallel Review Worked

1. **Domains are independent:** Backend logic, frontend UI, infra config don't overlap
2. **All read-only:** No modifications during review, just analysis
3. **Different expertise:** Backend engineer, frontend specialist, infrastructure expert
4. **Comprehensive coverage:** 4 reviews > 1 person reviewing everything
5. **Speed:** 4 agents in parallel = 75% faster than sequential

## Cost Comparison

| Approach | Time | Cost | Quality |
|----------|------|------|---------|
| One reviewer (sequential) | 33 min | $0.08 | Good |
| Parallel (4 reviewers) | 12 min | $0.12 | Better |
| Speedup | 64% faster | +50% cost | +40% quality |

**Value:** For complex multi-domain PRs, parallel review is worth the extra cost.
```

---

## Step 4: Verify & Commit

After fixes are applied:

```bash
/craftsman:verify
```

Output:
```
✅ All critical issues resolved
✅ Tests passing with new edge cases
✅ Code quality metrics within range
✅ Infrastructure rollback plan in place
```

```bash
/craftsman:git
```

Output:
```
refactor(order): add async job processing for order handling

Backend:
- Add OrderJobHandler for async order processing
- Implement job serialization with OrderId only (safe retry)
- Add idempotency check to prevent duplicate processing
- Integrate with queue driver with max_retries and dead_letter_queue

Frontend:
- Add OrderForm with validation and error handling
- Create useOrderPolling hook with polling interval (10s)
- Implement error boundary for graceful failure
- Add proper TypeScript annotations

Infrastructure:
- Create jobs table with down migration (rollback support)
- Configure Redis queue with retry strategy
- Add health checks for queue monitoring
- Plan load testing in staging environment

Tests:
- Add unit tests for OrderService (95% coverage)
- Add integration tests for full flow
- Add edge case tests (job retry, concurrency, timeout)

Reviewed-by: @backend-specialist, @frontend-specialist, @infra-expert
```

---

## Key Takeaway

Parallel review **is most effective for**:
- Multi-domain PRs (backend + frontend + infra)
- Large changesets (>10 files)
- Different reviewer expertise
- High-quality requirements

Parallel review **is NOT needed for**:
- Single-file changes
- Changes in one domain only
- Simple bug fixes
- Code changes by one specialist
