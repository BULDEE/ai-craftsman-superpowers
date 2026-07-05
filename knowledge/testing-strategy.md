# Testing Strategy

> "Working code is a low bar." - the whole point of tests is to keep code *changeable*, not merely working today.

A test suite is an asset only if it stays fast, trustworthy, and cheap to maintain. More than half of test-automation efforts fail not for lack of tests but because the suite grows too complex and too expensive to maintain (All4Test / Chrysocode, ADTF 2020). Strategy is deciding **what** to test, **at which level**, and **how** to keep it maintainable.

## The Pyramid (and the Trophy)

Put most of your testing effort where feedback is fastest and failures are most precise. This plugin's default target:

| Level | Share | Speed | Answers |
|-------|-------|-------|---------|
| Unit | ~70% | milliseconds | Does this rule/behavior compute correctly in isolation? |
| Integration | ~20% | seconds | Do these units + a real adapter (DB, queue) collaborate? |
| End-to-end | ~10% | seconds to minutes | Does a full user journey work through the real stack? |

Two shapes to know:

- **Ice-cream cone (anti-pattern)**: mostly slow E2E tests, few unit tests. Slow, flaky, and vague about *why* something broke.
- **Testing trophy**: for UI-heavy front-ends, integration tests carry more weight than the strict pyramid suggests, because most component bugs live at the wiring between units. Adjust the ratio to where your risk actually is; do not treat 70/20/10 as dogma.

## Test Types and Their Responsibilities

| Type | Scope | Substitutes | Owns |
|------|-------|-------------|------|
| Unit | One class/function | All collaborators | Business-rule correctness |
| Component | One module/aggregate | External systems | In-module collaboration |
| Integration | Code + one real dependency | The rest | Adapter correctness (SQL, HTTP) |
| Contract | Boundary between two services | The other side | The shared schema/protocol |
| End-to-end | Full stack | Nothing | A critical user journey |

Each level has a job; do not re-test at E2E what a unit test already proves. A rule verified by a fast unit test does not need a browser to prove it again.

## FIRST: Properties of a Good Unit Test

| Property | Meaning |
|----------|---------|
| **F**ast | Milliseconds; a slow suite stops being run |
| **I**solated | No dependence on other tests, order, or shared mutable state |
| **R**epeatable | Same result every run, any machine, offline (no clock, no network, no random) |
| **S**elf-validating | Pass/fail is automatic; no human reads output to decide |
| **T**imely | Written with (or before) the code, not months later |

`R` is where most flakiness hides: inject a `Clock`, seed randomness, and never hit a real network in a unit test.

## What to Test, and How

**Test behavior, not implementation.** Assert on observable outcomes, not on private fields or the sequence of internal calls. Tests coupled to implementation break on every refactor and stop protecting you.

**One concept per test.** A test that asserts three unrelated things fails ambiguously and reads poorly. One behavior, one test, one reason to fail.

**Arrange / Act / Assert.** Keep the three sections separate and non-overlapping (see [[tdd]] for naming and the reversed-writing trick).

```python
# Bad - couples the test to HOW it works, and checks two concepts
def test_checkout():
    svc = CheckoutService(repo := Mock())
    svc.checkout(cart)
    repo.save.assert_called_once()          # implementation detail
    assert svc._last_total == 30            # private field

# Good - asserts observable behavior, one concept
def test_checkout_charges_the_cart_total():
    payments = FakePaymentGateway()
    CheckoutService(InMemoryOrders(), payments).checkout(cart_of(30))
    assert payments.charged() == Money.euros(30)
```

## Test Doubles

A **test double** stands in for a real collaborator. Know the five kinds and pick the least powerful that does the job (Meszaros):

| Double | Purpose | Verifies |
|--------|---------|----------|
| Dummy | Fills a required parameter, never used | nothing |
| Stub | Returns canned answers | nothing (state) |
| Spy | A stub that also records how it was called | calls, after the fact |
| Mock | Pre-programmed with expectations | calls, and fails if unmet |
| Fake | A real, simplified implementation (in-memory repo) | behavior, via state |

Prefer a **fake** over a **mock** where you can: a fake exercises the real contract, while a mock asserts a call sequence and re-couples the test to implementation. Reserve mocks for true boundaries you cannot run (a payment API, an email sender).

```typescript
// Stub - canned answer, no verification. Use to steer a path.
const clock: Clock = { now: () => new Date("2026-01-01") };

// Fake - a real, simple implementation of the port. Verify via its state.
class InMemoryOrders implements OrderRepository {
  private readonly rows = new Map<string, Order>();
  save(o: Order) { this.rows.set(o.id, o); }
  count() { return this.rows.size; }
}

// Mock - expectation on an unrunnable boundary. Use sparingly.
test("a failed charge sends an alert", () => {
  const alerts = mock<AlertService>();
  new Checkout(new InMemoryOrders(), failingGateway()).run(cart);
  expect(alerts.send).toHaveBeenCalledWith(expect.objectContaining({ kind: "charge_failed" }));
});
```

Rule of thumb: if your test needs three mocks and asserts on call order, the design is probably wrong, not the test. Introduce a port and a fake instead (see [[hexagonal]]).

## End-to-End Tests That Survive

E2E tests are the most expensive and the most fragile. Three practices keep them maintainable (ADTF 2020):

**1. Describe behavior, not the UI.** A scenario should speak of user intentions, not tabs, buttons, or checkboxes. The UI can then change with only the step implementation updated, at no test-maintenance cost.

```gherkin
# Imperative (bad) - hides intent behind UI mechanics; breaks when the UI moves
Scenario: I can create an item in the list
  When the text "Adopt BDD" is typed into the input field
  And the "Add" button is clicked
  Then the item "Adopt BDD" is shown in the list

# Declarative (good) - states the purpose; survives UI change
Scenario: I can add a task
  When I add a task "Adopt BDD"
  Then a new task "Adopt BDD" exists
```

**2. Use concrete data.** Vague scenarios ("I add a task / a task is created") cannot characterize behavior or lift ambiguity. Name the actual value ("Adopt BDD"), so the expected outcome is unmistakable.

**3. One behavior per scenario.** Chaining "add then delete" in one scenario falsely implies a dependency and makes failures ambiguous. Keep each behavior a separate, independent scenario.

**Page Object Model.** Encapsulate every screen's locators and interactions behind a page object; tests call `todosPage.submit(task)`, never raw selectors. When markup changes, one page object changes, not fifty tests. For actor-centric flows, Screenplay refines POM further.

## Why Integration and Contract Tests Earn Their Place

Unit tests prove each unit; they say nothing about the wiring. Most production incidents live at boundaries: a wrong SQL mapping, a serialized field that changed shape, a queue message a consumer no longer understands. Two targeted levels catch these cheaply:

- **Integration test**: run the real adapter against the real dependency (a test database, a local broker). It is the only level that proves your Doctrine mapping or your HTTP client actually works.
- **Contract test**: pin the schema shared by two services so neither breaks the other silently. The consumer records what it expects; the provider verifies it still delivers exactly that.

```typescript
// Contract (consumer side): "I expect this exact response shape."
const expected = { id: "o1", status: "confirmed", total: 3000 };
providerMock.given("order o1 is confirmed")
  .uponReceiving("a request for order o1")
  .willRespondWith({ status: 200, body: expected });
// The provider replays this contract in its own CI: drift fails a build, not production.
```

A handful of these replaces a swarm of slow E2E tests that would otherwise be your only defense against boundary drift.

## Test Smells

| Smell | Why it hurts | Fix |
|-------|--------------|-----|
| Assertion-free test | Green means nothing | Assert an observable outcome |
| Mystery guest | Depends on hidden external data/file | Make inputs explicit in the test |
| Test that mirrors the code | Breaks on every refactor | Assert behavior, not structure |
| Conditional logic in a test | Untested test; branches hide bugs | One path per test |
| Slow unit test | Suite stops being run | Remove I/O; inject clock/network |

## Coverage: Measure Risk, Not Lines

A line-coverage percentage is a weak proxy. High coverage with assertion-free tests proves nothing; 60% coverage that exercises every business rule and boundary is worth more than 95% that only touches getters. Target the code where a defect is costly or likely (the domain, the money paths), and accept low coverage on trivial glue.

## Flaky Tests

A test that passes and fails without code changes is worse than no test: it trains the team to ignore red. Policy:

1. **Quarantine** it immediately (out of the blocking suite).
2. **Fix the determinism** (usually a clock, network, ordering, or timing assumption) or **delete** it.
3. Never "retry until green": a green-on-retry test hides a real race.

## Legacy Entry Point

When code has no tests, you cannot start with the pyramid. Pin current behavior with **characterization tests** first, then refactor under that net and add real tests bottom-up. See [[legacy/characterization-testing]] and [[legacy/legacy-techniques]].

## Related

- [[tdd]] - unit tests written first, red-green-refactor, AAA, and test doubles in the small.
- [[clean-architecture]] - the architectural boundary is a testability boundary; the humble object makes UIs unit-testable.
- [[principles]] - dependency inversion is what lets you substitute a fake at a port.
