# Characterization Testing

> "A characterization test documents the actual behavior of a piece of code." - Michael Feathers

When you must change code that has **no tests**, you cannot start from the specification: you do not yet know what the code is supposed to do, only what it *does*. A characterization test pins that current behavior so you can refactor underneath it with confidence. It is the entry point to any legacy rescue: get a net, then change the code.

## One Technique, Many Names

The same idea appears under several labels; they are interchangeable:

| Name | Popularized by |
|------|----------------|
| Characterization Test | Michael Feathers, *Working Effectively with Legacy Code* |
| Golden Master | the oldest name |
| Snapshot Test | Facebook's Jest |
| Approval Test | approvaltests.com (the most actively maintained libraries) |

The mindset differs from TDD: you are **not** asserting the *correct* answer, you are recording the *current* one, even if it is wrong. Bugs get frozen too, on purpose: your job right now is to not change behavior, not to fix it.

| | Unit test (TDD) | Characterization test |
|---|-----------------|-----------------------|
| Asserts | The *correct* behavior from a spec | The *current* behavior, as-is |
| Written | Before the code (red-green-refactor) | After the code, around existing behavior |
| On a found bug | Fails (good, drives a fix) | Passes (the bug is frozen on purpose) |
| Lifespan | Permanent | Temporary scaffolding, replaced by unit tests |
| Purpose | Drive design | Enable safe change of untested code |

## The Recipe

1. **Execute** the code with representative inputs.
2. **Capture** its output as a string (a serialized value, printed lines, a rendered document).
3. **Approve** that string as the reference (the "approved" or "golden" file), committed alongside the test.
4. **Check coverage**: run coverage to confirm the captured runs actually exercise the branches you are about to touch. Uncovered lines are behavior you have not pinned.
5. **Verify the net catches changes**: introduce an obvious mistake (flip a condition, change a constant) and confirm the test goes red. A characterization test that never fails protects nothing.

On the next run, the framework diffs the fresh output against the approved file. A difference is either a regression you caused (fix it) or an intended change (approve the new output).

```typescript
test("supermarket receipt is unchanged", () => {
  const receipt = checkout([apples(5), bread(2)]);
  // The framework compares this string to the committed .approved.txt
  approvals.verify(printReceipt(receipt));
});
```

```python
# The same shape in Python with an approval library.
def test_payroll_is_unchanged(verify):
    outputs = [str(calculate_payroll(e)) for e in [salaried(), hourly(), on_leave()]]
    verify("\n".join(outputs))   # first run writes .approved; later runs diff against it
```

The first run has no approved file, so it fails; you inspect the produced output and, if it is plausible, approve it. That approved file is committed and becomes the oracle.

## Step by Step on a Legacy Function

Suppose you inherit a 200-line `calculatePayroll(employee)` with no tests and you must add a new bonus rule. Do not read it line by line hoping to understand it; characterize it first.

1. Pick a handful of representative inputs: a salaried employee, an hourly one, one with overtime, one on leave. You do not need to understand the code to choose these; pick shapes that look different.
2. Call the function with each and print whatever it returns and does. If it returns nothing, reach for the tracker beacon below.
3. Run the tests. They fail, because there is no approved file yet. Look at the produced output: if it is plausible, approve it. You have just frozen the current behavior, warts and all.
4. Run coverage. If the "on leave" branch is still uncovered, you are missing an input; add one until the lines you intend to touch are green.
5. Break something on purpose (return `0` from a helper). Confirm at least one approved test goes red. Now the net is proven.

Only now do you add the bonus rule. When an approved file changes, you know exactly which behavior your edit moved, and you decide whether that change was intended.

## Golden Master for a Whole Program

The technique scales past a single function. For a legacy batch job or a CLI, drive the whole program with a set of recorded inputs and capture its entire output (stdout, generated files, final database state serialized to text). This whole-program golden master is often the *only* net you can get quickly on tangled code with no seams, and it buys you enough safety to start carving seams from the inside. Combine it with generated inputs (fuzzing a range of values) to widen coverage cheaply.

## Capturing Side Effects: the Tracker Beacon

Often the behavior you care about is not in the return value: the code logs, mutates hidden state, or calls a collaborator. Inject an **optional tracker** that does nothing by default (so production is unchanged) and records in tests.

```javascript
// Default no-op in production; a beacon in tests.
this.add = function (playerName, track = () => {}) {
  players.push(playerName);
  places[this.howManyPlayers() - 1] = 0;
  track(places);           // beacon - captured only when a tracker is passed
  track(purses);
  return true;
};

// In the test, collect what the beacon saw and approve it.
function createTracker() {
  const logs = [];
  const track = (object) => logs.push(JSON.stringify(object));
  return [track, () => logs.join("\n")];
}
```

The added parameter is a temporary **shim**, not a permanent hack: remove it as you refactor the code into something testable by design.

```python
# The same beacon in Python: an injected recorder, default no-op.
def add_player(name, track=lambda _obj: None):
    players.append(name)
    track(players)          # silent in production, captured in the test

def test_add_player_records_state(verify):
    seen = []
    add_player("Nicolas", track=lambda obj: seen.append(str(obj)))
    verify("\n".join(seen))
```

## Scrubbing Unstable Data

If an approval test fails on every run without a code change, the output contains **unstable data**, usually timestamps, UUIDs, or randomness. Do not weaken the test; **scrub** the unstable parts, replacing them with a constant.

```
# Raw output - fails every run                # Scrubbed - stable
"id": "B618F1A2-6816-46BA-9AF2-E39834F7E01F"  "id": "**Scrubbed-ID**"
"created_at": "2026-01-01T12:29:12.827Z"      "created_at": "**Scrubbed-Date**"
```

An advanced scrubber preserves identity: the same original value maps to the same placeholder (`**Scrubbed-ID-1**`, `**Scrubbed-ID-2**`), so you still see relationships between fields without depending on their volatile values.

```typescript
// A scrubber is just a function applied to the output before approval.
const scrub = (out: string): string =>
  out
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "**Scrubbed-ID**")
    .replace(/\d{4}-\d{2}-\d{2}T[\d:.]+Z/g, "**Scrubbed-Date**");

approvals.verify(scrub(renderUsers(users)));
```

## The Printer: Make the Approved Output Readable

For simple values, serialization is enough. When the output is messy, write a custom **Printer** that turns it into something a human can read and review. This is why "Approval Test" beats "Snapshot Test": the way you *print* the behavior is part of the test's value.

```
apples                    9.95
  1.99 * 5.000
5 for 6.99(apples)       -2.96

Total:                    6.99
```

A receipt-shaped printer for a checkout kata is far easier to diff and reason about than a raw JSON blob. Refine the printer as you learn what the code actually does.

```typescript
// A custom printer turns a messy result into a human-reviewable approved value.
function printReceipt(r: Receipt): string {
  const lines = r.items.map((i) => `${i.name.padEnd(20)}${(i.total / 100).toFixed(2).padStart(8)}`);
  return [...lines, "", `${"Total:".padEnd(20)}${(r.total / 100).toFixed(2).padStart(8)}`].join("\n");
}
```

When you change the printer, every approved file changes too; do that as a deliberate, separate step so a formatting change never hides a behavior change.

## Checking the Net Catches Change

A characterization test is only worth the disk it sits on if it fails when behavior changes. Prove it deliberately:

```bash
# 1. Suite is green. 2. Introduce an obvious mistake in the code under test.
# 3. Run again: at least one approved test MUST go red.
sed -i 's/return total/return 0/' src/checkout.js
npm test   # expect a failing approval; if it stays green, your net has a hole
git checkout src/checkout.js   # revert the deliberate break
```

If nothing goes red, you have not actually pinned the behavior you are about to change; add inputs until you do.

## Coverage as a Map, Mutation as the Proof

Two checks keep a characterization suite honest:

- **Coverage** tells you *which* behavior you have captured. Aim to cover the code you are about to change; the [[refactoring/refactoring-campaigns]] hotspot analysis points you at where that is.
- **Mutation** (deliberately breaking the code) proves the captured tests would *notice* a change. Coverage without a failing mutant is a false sense of safety.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Asserting the "correct" value | You are writing a spec, not characterizing; it fails immediately | Record what the code *does*, bugs included |
| Flaky approved file | Red on every run, team ignores it | Scrub dates/UUIDs/randomness |
| Unreadable approved blob | Reviews rubber-stamp diffs | Write a custom Printer |
| Stubbing a global (`console.log`) to silence a side effect | Global state leak across tests, test coupled to implementation | Isolate the side effect behind a seam and override it - see [[legacy/legacy-techniques]] |
| Never checking the net catches changes | The test protects nothing | Introduce an obvious mistake and confirm red |
| Approving output without reading it | You freeze a bug you could have caught, or noise | Read the diff before approving the first time |
| Keeping characterization tests forever | They pin implementation, not intent | Replace them bottom-up with real unit tests as you refactor |

## Tooling

Most languages have an actively maintained Approval Tests library (see approvaltests.com); pick the one for your stack rather than hand-rolling the diff.

| Language | Library |
|----------|---------|
| JavaScript / TypeScript | jest-image-snapshot / jest snapshots, approvals |
| Python | approvaltests, syrupy |
| PHP | approvals-php |
| Java / Kotlin | ApprovalTests.Java |
| C# | ApprovalTests.Net, Verify |

Any of these gives you the approve/diff loop, a scrubber hook, and a printer hook; you supply the domain-shaped printer.

## Rule

> Characterization freezes what the code *does*, not what it *should* do. Get the golden master green first, prove it catches change, and only then refactor or fix.

## Related

- [[legacy/legacy-techniques]] - seams, Subclass & Override, and the moves that make untestable code testable enough to characterize.
- [[testing-strategy]] - once behavior is pinned, replace characterization tests bottom-up with real unit tests.
- [[refactoring/mikado-method]] - "get this under a characterization test" is usually the first Mikado subgoal.
- [[refactoring-techniques]] - the safe transformations you apply once the golden master is green.
