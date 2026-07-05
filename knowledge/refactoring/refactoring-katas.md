# Refactoring Katas: Deliberate Practice

> "The emphasis is on how you work, not just what you accomplish." - Nicolas Carlo

Refactoring is a motor skill: you get good at it by repetition under constraints, the way musicians and martial artists do. A **kata** is a small, self-contained coding exercise you repeat deliberately to build the reflexes you will need on real legacy code. This file is the curriculum and the practice method.

## Why Katas, Not Just Real Work

On production code, the stakes are high and the feedback is slow, so you fall back on habits instead of building better ones. A kata strips the problem down to one skill, removes the risk, and lets you repeat the *movement* until it is a reflex. The point is not to finish the exercise; it is to notice *how* you work and improve it. Finishing a kata once teaches almost nothing; doing it five times, each with a tighter constraint, rewires how you refactor.

## The Five Legacy Katas

A progression from tangled-but-simple to production-like chaos:

| Kata | Repo | Teaches | Level |
|------|------|---------|-------|
| **Gilded Rose** | emilybache/GildedRose-Refactoring-Kata | Add tests, refactor, then add a feature to tangled conditionals (no I/O) | Beginner |
| **Tennis** | emilybache/Tennis-Refactoring-Kata | Refactoring under time pressure with tests already provided; 3 smell variants | Beginner+ |
| **Trip Service** | sandromancuso/trip-service-kata | Breaking dependencies (HTTP/DB calls that throw) with no tests | Intermediate |
| **Expense Report** | christianhujer/expensereport | Isolating a stdout dependency; extract core logic from output | Intermediate |
| **Trivia Game** | jbrains/trivia | Everything at once: no tests, non-trivial logic, stdout + randomness | Advanced |

Do them in that order. Gilded Rose and Tennis build the refactor-under-a-net reflex; Trip Service and Expense Report teach dependency-breaking; Trivia resembles a real codebase and combines them all.

## A Worked Kata: Gilded Rose

The classic beginner kata. You are handed a tangled `updateQuality()` full of nested conditionals and asked to add a new item type without breaking the old rules. The disciplined path:

1. **Net first.** The code has no tests but is pure (no I/O), so a golden master is trivial: run `updateQuality` across every item and every `sellIn`/`quality` combination, capture the output, approve it ([[legacy/characterization-testing]]).

```python
# One characterization test pins the entire current behavior.
def test_gilded_rose_golden_master(verify):
    lines = []
    for name in ITEM_NAMES:
        for sell_in in range(-1, 12):
            for quality in range(0, 51):
                item = Item(name, sell_in, quality)
                update_quality([item])
                lines.append(f"{name} {sell_in} {quality} -> {item.sell_in} {item.quality}")
    verify("\n".join(lines))
```

2. **Refactor under the net.** Now transform the nested conditionals with tiny green steps: extract each item's rule into its own function, replace the type-checking conditional with polymorphism, and rerun the golden master after every move. It never goes red because you never change behavior.
3. **Only then add the feature.** With clean, tested code, the new "Conjured" item is a small, safe addition, exactly the point of the exercise: refactoring *earns* the easy feature.

Notice the shape: **net, then refactor, then feature**, the same loop as [[legacy/legacy-techniques]] on real code.

## The Core Strategy

One principle makes every legacy kata (and real legacy code) tractable:

> Start **testing** from the shallowest branch, and start **refactoring** from the deepest one.

Testing the shallow, easy paths first gets a safety net up fast without fighting dependencies. Refactoring from the deepest, most-nested code first collapses the complexity that makes everything else hard to read. Put a characterization net around the behavior before you touch it ([[legacy/characterization-testing]]), then carve.

## How to Practice Deliberately

Doing the kata is not practicing; *deliberate* practice has structure:

- **Pick one technique per run.** Do Gilded Rose focusing only on Extract Function, then again focusing only on Replace Conditional with Polymorphism. Isolating the skill is the point.
- **Timebox and repeat.** A short, repeated session beats one long slog. Reset and redo.
- **Commit in tiny steps.** Frequent micro-commits keep the code green and make each move a checkpoint ([[refactoring/mikado-method]]).
- **Optimize your feedback loop.** Make the tests run in milliseconds; slow feedback kills deliberate practice.
- **Work without references** once you know the path; struggling to recall the technique is what builds the memory.
- **Reflect.** Take notes on what worked and what stalled. Understanding *why* a move succeeded is the improvement.

For beginners, first watch a worked example (Sandro Mancuso's Trip Service walkthrough is the classic) to see the solution path, then reproduce it from memory.

## A Practice Progression

```
Week 1  Gilded Rose x3     - build the add-test-then-refactor reflex
Week 2  Tennis x3          - refactor fast with tests already there
Week 3  Trip Service x2    - Extract-and-Override to break a hard dependency
Week 4  Expense Report x2  - pull logic out from behind stdout
Week 5  Trivia x2          - the full legacy experience, net-first
```

Each repetition, add a constraint: no mouse, no manual test runs, a 25-minute cap, or "only automated refactorings". Constraints force new pathways and expose habits you did not know you had.

## Constraint Variations

The second time through a kata, add a constraint to force new pathways. Rotate these:

| Constraint | What it trains |
|------------|----------------|
| Only IDE-automated refactorings | Trust and speed with safe transformations |
| No mouse, keyboard only | Fluency in your editor's refactoring shortcuts |
| 25-minute hard cap | Prioritizing the highest-leverage move first |
| One technique only (e.g. Extract Function) | Deep mastery of a single move |
| Commit every 2 minutes | The micro-committing reflex on risky code |
| Golden master only, no reading the code | Trusting the net instead of comprehension |
| Delete and redo from scratch | Muscle memory of the whole path |

The kata stays the same; the constraint is what you are actually practicing.

## Designing Your Own Kata

When a real codebase teaches you a lesson, distill it into a kata for the team:

1. Extract the tangled function into a tiny standalone project.
2. Strip identifying details; keep the shape of the mess.
3. Remove the tests (or keep only a golden master) so the exercise starts where legacy does.
4. Write down the goal ("add feature X without breaking Y") and a time box.

A shared kata turns one painful production experience into a repeatable lesson for everyone.

## Mapping to This Plugin

- The kata skills map one-to-one onto [[legacy/legacy-techniques]] (seams, Subclass & Override, Wrap & Sprout) and [[legacy/characterization-testing]] (the golden-master net).
- The `Extract Method and Override` move practiced in Trip Service is exactly the dependency-breaking technique the `/craftsman:legacy untangle` flow guides you through.
- Practice katas in the language of your active pack so the reflexes transfer directly to your production code.

## Practice Mistakes to Avoid

| Mistake | Why it wastes the practice | Instead |
|---------|---------------------------|---------|
| Rushing to finish | You practice speed, not skill | Slow down; the process is the point |
| Skipping the net | You practice unsafe change | Golden master before any refactor |
| Doing it once | No reflex is built | Repeat with a new constraint each time |
| Big commits | You lose the checkpoint habit | Commit every small green step |
| No reflection | You repeat the same habits | Note what worked and why, each run |
| Always reading the solution | You never build recall | Watch once, then reproduce from memory |

## What Each Kata Uniquely Drills

- **Gilded Rose** trains the full *net -> refactor -> feature* loop on pure logic; it is where the reflex is born.
- **Tennis** removes the net-building step (tests are given) so you practice *refactoring speed* alone.
- **Trip Service** has no tests and throws from HTTP/DB calls, forcing *Extract-and-Override* to break dependencies before you can even write a test.
- **Expense Report** hides behavior behind stdout, drilling the *isolate the side effect* move (a seam around output).
- **Trivia** combines missing tests, randomness, and stdout: the closest thing to real production legacy, to be attempted only once the isolated skills are reflexes.

## Rule

> A kata is practiced, not completed. Repeat it under tightening constraints, net-first every time, and watch how you work; the reflexes you build are what carry over to the real legacy code that matters.

## Related

- [[legacy/legacy-techniques]] - the techniques each kata drills.
- [[legacy/characterization-testing]] - the net you put up first in every kata.
- [[refactoring-techniques]] - the catalogue of moves you isolate one at a time.
- [[tdd]] - red-green-refactor, the loop underneath the practice.
