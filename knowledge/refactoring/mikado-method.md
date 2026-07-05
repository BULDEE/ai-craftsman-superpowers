# The Mikado Method

> "You can't anticipate what needs to be done first, but you regularly check where you are going so you can adapt to whatever comes up."

The Mikado Method (Ola Ellnestam & Daniel Brolund, popularized for legacy work by Nicolas Carlo) is how you make a large change in a codebase full of **unknown unknowns** without ever leaving it broken. Instead of a big risky branch, you discover the graph of prerequisites one timebox at a time, and you only ever commit code that works.

## When to Use It

- A change whose full extent you cannot see up front (the classic legacy trap).
- Every attempt uncovers "but first I have to change this other thing", recursively.
- You keep saying "almost done" for days and cannot back it with evidence.

If you can already see the whole change and it is small, you do not need Mikado; just do it. Mikado earns its overhead exactly when the depth of the change is unknown.

## The Two Phases

The method is a loop with a timer (about 10 minutes is best):

```
Write the goal down
        |
   Start timer  (~10 min)
        |
  Goal done before the timer?
        |                         |
       NO  (Discovery)           YES  (Delivery)
        |                         |
  List blocking subgoals     Commit
   (unrelated? -> Parking)    Tick off the goal
        |                     (optionally open an intermediate PR)
   git reset --hard           |
        |                     Pick the next subgoal
   Pick a subgoal  <----------+
```

### Discovery Phase

Attempt the goal directly. When the timer rings and it is not done:

1. Write down every prerequisite you just discovered as a **subgoal** node, drawing the dependency graph of what must happen first.
2. `git reset --hard` - **throw the attempt away.** You keep the *knowledge* (the graph), not the broken code.
3. Pick one subgoal and start a new timer against it.

Reverting is not failure; it is the mechanism. You attacked the problem to *learn its shape*, and now you know one more prerequisite. Repeating this turns an unknowable change into an explicit graph of small, known tasks.

### Delivery Phase

After discovering subgoals over and over, you reach leaves that take under ten minutes. Now you deliver:

- Work from the **leaves of the graph** inward. A leaf has no unmet prerequisite, so it always completes cleanly.
- Each completed leaf makes its parents easier, like dominoes.
- The codebase stays working the whole time, so you can **ship multiple times**: open intermediate PRs for the preparatory work. Deliver often to avoid the merge conflicts of a long-running branch. Delivering often is what makes you go faster.

## A Worked Example

Goal: **replace scattered `console.log()` calls with a proper injectable logger** in a legacy service. You try it directly and immediately hit a wall: the `Transaction` class logs inline, `Ticket` logs inline, there is no logger abstraction, and there are no tests. `git reset --hard`, and note what blocked you. After a few Discovery timeboxes the graph looks like this:

```
Replace console.log() with a logger   <- the goal (last thing to do)
  |-- Wrap calls into ConsoleLogger
  |     |-- Create Logger interface
  |     |-- Create ConsoleLogger class
  |-- Update the call sites
  |     |-- Refactor Transaction to inject the logger  <- was a hidden prerequisite
  |     |-- Migrate Ticket to use the Logger interface
  |-- Expose the logger through configuration
  |     |-- Import it from configuration
  |     |-- Extract Logger into the common lib
  |-- (safety net) Test create() / print() / cancel()   <- do these FIRST
```

Delivery works the leaves first: write the characterization tests, create the interface and `ConsoleLogger`, inject them into `Transaction` and `Ticket` one at a time (committing and shipping each), wire configuration, and only then flip the final `console.log` calls. Every step ships green; the goal at the top is reached last, almost trivially, because every prerequisite is already done.

## The Parking

In legacy code you constantly spot unrelated messes near what you are changing. You cannot chase every one, but your brain keeps nagging. Create a **Parking**: a node deliberately *not* connected to the goal, where you dump stray thoughts, refactorings, and TODOs.

The Parking frees your mind because it trusts the note instead of your memory. At the end, you decide to tackle some, file issues for others, or drop the rest: if a parked item is truly important, it will come back on its own.

## Why It Works

| Reason | Effect |
|--------|--------|
| You start fresh every time | No tunnel where you lose track of what you changed or when you'll be done |
| The timebox is short | Reverting costs at most ~10 minutes of redoable work |
| You reflect every iteration | You cannot anticipate the order, but you adapt to what surfaces |

Two more benefits fall out: you can **stop almost anytime** (an interruption is cheap because the next step is written down), and your daily status becomes honest - a real progress bar of ticked subgoals instead of "almost done".

## Combine It

Mikado composes with the other legacy disciplines:

- **Micro-committing**: inside a Delivery step, commit every couple of minutes so each subgoal is itself a chain of checkpoints. See [[refactoring/refactoring-campaigns]].
- **Incremental refactoring**: many subgoals are safe, mechanical moves (extract, change signature, migrate callers). See [[refactoring-techniques]].
- **Characterization tests**: on untested code, the first subgoals are often "get this under a test" before any change. See [[legacy/characterization-testing]].

## Common Mistakes

| Mistake | Consequence | Correction |
|---------|-------------|------------|
| Pushing through instead of reverting | You accumulate broken, intertwined changes with no way back | Timebox and `git reset --hard`; keep the graph, drop the code |
| No timer | Discovery drifts into an hours-long tunnel | Start a ~10 minute timer every attempt |
| Working from the root | You try the goal before its prerequisites exist; nothing completes | Always deliver from the leaves inward |
| Chasing unrelated messes | You lose the goal in a swamp of side-quests | Put them in the Parking, decide later |
| One giant final commit | Un-reviewable, un-revertable, un-bisectable | Commit each subgoal; ship intermediate PRs |

## Mikado vs Just Refactoring

Plain refactoring assumes you can see the target and the path. Mikado is for when you **cannot**: it is a discovery protocol layered on top of refactoring. Once Discovery has drawn the graph, each Delivery step is ordinary safe refactoring. Think of Mikado as the map-making, and [[refactoring-techniques]] as the walking.

## Tooling and Overkill

- Start low-tech: pen and paper keep you focused and add zero friction. For remote pairs, a fast mind-map tool (e.g. mindmup) works; avoid anything that makes creating a connected node slow.
- This plugin's `/refactor` Mikado mode persists the graph across sessions (in `.craftsman/mikado.json`) so an interruption never loses it.
- Do not automate the revert away or skip the timer: the discipline of letting go of code you wrote is the skill being built.

## Cheat Sheet

1. Write the goal at the top of a graph.
2. Start a ~10 minute timer and attempt the goal (or current subgoal) directly.
3. Timer rings, goal done? **Yes** -> commit, tick it off, optionally ship a PR, pick the next subgoal.
4. **No** -> write down the blocking prerequisites as child nodes; drop anything unrelated into the Parking.
5. `git reset --hard` to return to a working state; keep only the graph.
6. Pick a subgoal (prefer a leaf) and go to step 2.
7. Repeat until the goal at the top falls out for free.

## On Letting Go

The hardest part is step 5: throwing away code that "almost worked". It feels wasteful, but it is the whole point. The value you produced in a Discovery timebox is *knowledge*, captured in the graph, not the diff. If reverting feels painful, that is a signal you need to practice it more, not that the method is wrong: worst case you redo ten minutes of work, and next time you will take smaller, safer steps by reflex. Being able to let go of code you wrote is a craft skill in its own right, and it is what lets you move fast on code that would otherwise trap you.

If you genuinely need a fragment of the reverted attempt, `git stash` it before resetting so it stays available for reference while your working tree returns to green.

## Related

- [[refactoring-techniques]] - the safe moves each Mikado subgoal is usually made of.
- [[legacy/legacy-techniques]] - seams and dependency-breaking, the subgoals Mikado uncovers most in legacy.
- [[legacy/strangler-fig]] - the same "keep it working, deliver often" philosophy at the architecture scale.
