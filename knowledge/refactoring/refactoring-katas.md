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

## Mapping to This Plugin

- The kata skills map one-to-one onto [[legacy/legacy-techniques]] (seams, Subclass & Override, Wrap & Sprout) and [[legacy/characterization-testing]] (the golden-master net).
- The `Extract Method and Override` move practiced in Trip Service is exactly the dependency-breaking technique the `/craftsman:legacy untangle` flow guides you through.
- Practice katas in the language of your active pack so the reflexes transfer directly to your production code.

## Related

- [[legacy/legacy-techniques]] - the techniques each kata drills.
- [[legacy/characterization-testing]] - the net you put up first in every kata.
- [[refactoring-techniques]] - the catalogue of moves you isolate one at a time.
- [[tdd]] - red-green-refactor, the loop underneath the practice.
