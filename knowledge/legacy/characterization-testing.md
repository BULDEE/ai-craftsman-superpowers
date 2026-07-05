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

## Scrubbing Unstable Data

If an approval test fails on every run without a code change, the output contains **unstable data**, usually timestamps, UUIDs, or randomness. Do not weaken the test; **scrub** the unstable parts, replacing them with a constant.

```
# Raw output - fails every run                # Scrubbed - stable
"id": "B618F1A2-6816-46BA-9AF2-E39834F7E01F"  "id": "**Scrubbed-ID**"
"created_at": "2026-01-01T12:29:12.827Z"      "created_at": "**Scrubbed-Date**"
```

An advanced scrubber preserves identity: the same original value maps to the same placeholder (`**Scrubbed-ID-1**`, `**Scrubbed-ID-2**`), so you still see relationships between fields without depending on their volatile values.

## The Printer: Make the Approved Output Readable

For simple values, serialization is enough. When the output is messy, write a custom **Printer** that turns it into something a human can read and review. This is why "Approval Test" beats "Snapshot Test": the way you *print* the behavior is part of the test's value.

```
apples                    9.95
  1.99 * 5.000
5 for 6.99(apples)       -2.96

Total:                    6.99
```

A receipt-shaped printer for a checkout kata is far easier to diff and reason about than a raw JSON blob. Refine the printer as you learn what the code actually does.

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

## Related

- [[legacy/legacy-techniques]] - seams, Subclass & Override, and the moves that make untestable code testable enough to characterize.
- [[testing-strategy]] - once behavior is pinned, replace characterization tests bottom-up with real unit tests.
- [[refactoring/mikado-method]] - "get this under a characterization test" is usually the first Mikado subgoal.
- [[refactoring-techniques]] - the safe transformations you apply once the golden master is green.
