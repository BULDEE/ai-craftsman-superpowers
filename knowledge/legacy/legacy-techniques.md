# Legacy Code Techniques

> "To me, legacy code is simply code without tests." - Michael Feathers
>
> "A seam is a place where you can alter behavior in your program without editing in that place." - Michael Feathers

Legacy code is not old code; it is code you are **afraid to change** because nothing tells you when you break it. The way out is always the same loop: get a safety net around the part you must touch, make the change, then refactor. This file is the toolbox for the hardest step, getting untestable code under test *without* first breaking it. It pairs with [[legacy/characterization-testing]] (the net) and [[refactoring/mikado-method]] (the map).

## The Change Algorithm

1. Identify the change point.
2. Find the **seams** that let you sense and separate behavior.
3. Break dependencies so the code can run in a test.
4. Write characterization tests.
5. Make the change and refactor under the net.

Steps 2 and 3 are where legacy fights back. The techniques below are ordered from least to most invasive; reach for the smallest that unblocks you.

## Seams: the Enabling Idea

A **seam** is any place you can change what the program does without editing that place. An overridable method, an injected parameter, an interface: each is a seam. The whole skill of taming legacy code is spotting or carving a seam near your change point so a test can substitute the awkward behavior (a database call, a clock, a third-party SDK) with something harmless.

## Subclass and Override

**When:** existing code you want to test has an annoying side effect (a DB write, a network call, console noise).

Isolate the side effect into its own method (using automated refactorings so you do not need tests yet), make it `protected`, then subclass in the test and override it to do nothing.

```typescript
// 1. Extract the side effect into a seam, made protected.
export class Game {
  add(name: string): boolean {
    this.players.push(name);
    this.log(name + " was added");   // seam
    return true;
  }
  protected log(message: string): void { console.log(message); }
}

// 2. In the test, subclass and override the seam to silence it.
class TestableGame extends Game {
  protected log(_message: string): void { /* do nothing */ }
}
```

Now `TestableGame` runs with no side effect, and you can characterize the rest of `add()`. To *assert* the side effect happened, record it in the subclass (`loggedMessages.push(message)`) instead of overriding to nothing. Do **not** stub the global `console.log`: that leaks across tests and couples the test to implementation (see [[testing-strategy]] on fakes over global mocks).

## The Tracker Beacon

A lighter seam: add an optional dependency that defaults to a no-op, so production is unchanged and tests can observe.

```javascript
this.add = function (playerName, track = () => {}) {
  players.push(playerName);
  track(players);            // beacon - silent in production, recording in tests
  return true;
};
```

It is a temporary shim; remove it as the code becomes testable by design.

## The Wrap Technique

**When:** you need new behavior to run **before or after** existing code.

1. Extract the code to wrap into a function (Extract Function is a safe automated refactoring).
2. Create a new function that just forwards the call (a nonsense name is fine for now).
3. Point callers at the wrapper.
4. Add the new behavior before or after the forwarded call.

If the wrapped function was public `roll()`, rename it `rollWithoutCounting()` and name the wrapper `roll()`, so callers transparently get the new behavior. Test the wrapped (now `protected`) function via Subclass and Override.

A cleaner variant wraps the whole object as a **Decorator**:

```typescript
class WithPenaltyTracker {
  constructor(private readonly game: Game) {}
  playerDoesntGetOutPenalty(): void {
    this.game.playerDoesntGetOutPenalty();
    // new behavior before or after the wrapped call
  }
  /* forward the rest of the Game API to this.game */
}
// Callers change minimally:  new WithPenaltyTracker(new Game())
```

## The Sprout Technique

**When:** you need to **insert** new behavior in the middle of existing code (Wrap cannot reach the middle).

1. Create a new function (or, better, a new class) for the new behavior.
2. TDD it in isolation, greenfield, with all the arguments it needs.
3. Call it from the single point in the legacy code where the behavior belongs.

```typescript
// New, fully tested, in its own space.
export class PenaltyBoxTracker {
  private readonly turns = new Map<string, number>();
  trackPlayer(player: string): void {
    this.turns.set(player, (this.turns.get(player) ?? 0) + 1);
  }
}

// Legacy Game changes by exactly one line - minimal risk.
export class Game {
  private penaltyBoxTracker = new PenaltyBoxTracker();
  roll(roll: number): void {
    /* ... unchanged legacy ... */
    this.penaltyBoxTracker.trackPlayer(this.players[this.currentPlayer]); // the sprout
  }
}
```

Preferring a **new class** over a new method keeps the legacy class from growing and gives the new logic a clean home. These techniques work in functional code too: Wrap becomes function composition, Sprout becomes a new function injected where needed.

## Decouple Core from Infrastructure

Once you have a net, the higher-value move is inverting the dependencies so business logic stops calling infrastructure directly:

1. Understand which code is Core (rules) and which is Infrastructure (DB, clock, HTTP).
2. Extract each infrastructure bit into its own function.
3. **Invert the dependency**: the Core declares an interface it needs; the infrastructure implements it.
4. Compose them at a single **composition root**.

```javascript
// The "rescued" end state: use cases receive their dependencies, name nothing concrete inside.
const system_clock = new SystemClock();
const errorReporter = new RabbitMQErrorReporter(logger, "outbound");
export const getDeparture = new GetDeparture(
  geoDataRepository, compensationRulesRepository, departureRepository, errorReporter,
);
```

This is [[hexagonal]] reached from the inside out, one seam at a time.

## The Bubble: Strangling a God Class

When a legacy class is too tangled to fix in place, create a **bubble**: a new, well-designed class (often in a new folder) that is a safe space for the redesigned code. Everything not yet migrated forwards to the legacy code; the new class progressively takes over. This is the **Strangler Fig pattern applied at the class level** rather than the architecture level: no big-bang rewrite, just a design that grows while the legacy one fades. See [[legacy/strangler-fig]].

## Parameterize Constructor

**When:** a constructor `new`s a hard dependency inside itself, so a test cannot substitute it.

```php
// Before - the DB connection is created inside; untestable.
final class ReportService
{
    private Database $db;
    public function __construct() { $this->db = new MySqlDatabase(getenv('DSN')); }
}

// After - the dependency is a parameter; tests pass a fake, prod passes the real one.
final class ReportService
{
    public function __construct(private readonly Database $db) {}
}
```

Keep the old zero-arg constructor as a temporary overload if callers cannot all change at once, then remove it.

## Extract Interface

**When:** you need a seam at a boundary to inject a fake, but the collaborator is a concrete class.

```php
// 1. Extract an interface from the concrete class's public surface.
interface Database
{
    public function query(string $sql): array;
}

// 2. The concrete implements it (a mechanical, safe change).
final class MySqlDatabase implements Database { public function query(string $sql): array { /* ... */ } }

// 3. Callers depend on the interface; tests provide an InMemoryDatabase.
```

Extract Interface plus Parameterize Constructor together turn almost any hard dependency into a substitutable seam.

## Dependency-Breaking Quick Reference

| Technique | Use when |
|-----------|----------|
| Subclass and Override | A side effect blocks running the code in a test |
| Tracker Beacon (optional param) | You need to observe without changing the return |
| Extract and Override Call | A static/global call must be intercepted |
| Parameterize Constructor | A constructor `new`s a hard dependency |
| Extract Interface | You need a seam to inject a fake at a boundary |
| Adapt Parameter | A parameter's type is itself hard to construct |
| Wrap | New behavior belongs before or after existing code |
| Sprout | New behavior belongs in the middle, best in a new class |

## Golden Rules

- Make the **minimum** change to legacy code; put new logic in a new, greenfield space you can test cleanly.
- It is fine to change production code to make it testable: safety in changing beats perfect design. The shims are temporary.
- While characterizing, do **not** fix bugs; freeze current behavior first, change it deliberately later.

## Related

- [[legacy/characterization-testing]] - the golden-master net these techniques let you attach.
- [[refactoring/mikado-method]] - discovering the graph of seams a change requires.
- [[refactoring-techniques]] - the safe transformations (Extract Function, Move Statements) each step is built from.
- [[hexagonal]] - the target the Decouple-Core step moves toward.
