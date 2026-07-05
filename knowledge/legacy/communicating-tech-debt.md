# Communicating Technical Debt

> "Focus on the code, not the coder." - Nicolas Carlo

Refactoring is often blocked not by difficulty but by a failure to communicate. Managers and clients do not fund "code quality"; they fund outcomes. This file is the craft of translating technical debt into business language a decision-maker will act on, and of telling a stakeholder the truth about their codebase without blame or alarm.

## Why This Is a Craft Skill

A refactoring you cannot get funded does not happen. The engineer who can frame debt in cost, risk, and velocity terms unblocks the work that the engineer who only says "the code is bad" never will. Persuasion is part of the job, not a distraction from it.

## Five Arguments That Land With Managers

Translate the technical concern into the metric the manager already tracks.

| Argument | Business framing | The lever it pulls |
|----------|------------------|--------------------|
| Volatility of feature cost | "Refactoring reduces the *volatility* in the marginal cost of each feature" | Budget predictability |
| Quantified quality cost | "Last quarter we spent 63% of the dev budget fixing quality issues" | Direct financial cost |
| The debt metaphor | "We took technical loans to ship fast; we now pay interest on every change" | Speed now vs. speed later |
| Developer turnover | "10% of time on quality reduces attrition; replacing a senior costs months" | Talent retention cost |
| Support efficiency | "20% on refactoring halves first-response time, with positive ROI" | Support cost and CSAT |

Two framing rules make these work:

- **Speak their unit.** Managers hear cost, risk, predictability, and time-to-market; they do not hear cyclomatic complexity. Convert every technical claim into one of theirs.
- **Bring a number.** "The code is fragile" is an opinion; "one preventable bug cost us $1M and this class caused three of the last five incidents" is a case. Track declining velocity, rising bug counts, and incident frequency so you have the number when you need it.

### Translate, don't complain

The same request, badly and well framed:

```
# Rejected - technical, no business hook
"The OrderService is a 900-line god class with cyclomatic complexity 71.
 We need two sprints to refactor it."

# Funded - business unit, evidence, bounded ask
"Checkout changes take us 3-4 days each and caused 3 of the last 5 incidents.
 One file is the cause. Two weeks on it drops that to hours per change and
 removes the incident source. Here is the churn-vs-complexity chart."
```

### A cost you can compute

You rarely need precision, only an order of magnitude a manager can act on:

```
Recurring bug in module X:  ~1 incident / week
Cost per incident:          ~4 dev-hours + support time
Annual cost:                52 x 4 = 208 dev-hours (~1.3 dev-months)
Fix (root cause refactor):  ~40 hours, once
=> Payback in under 3 months, then pure saving.
```

Bring that arithmetic to the conversation and the debate stops being about taste.

## The Continuous Alternative to Asking Permission

Large refactorings need approval and often lose the argument. Small ones do not: fold an extra hour into each bug fix and an extra day into each feature. This compounds without a business case and is usually the faster route to a healthier codebase than a funded "refactoring project" (see the daily refactoring hour in [[refactoring/refactoring-campaigns]]).

## Enclosure Diagrams: Make Debt Visible

The single most persuasive artifact for non-technical stakeholders is a picture, not a metric. An **enclosure diagram** (a treemap) encodes the whole codebase in three dimensions:

| Visual channel | Encodes | Read as |
|----------------|---------|---------|
| Rectangle/bubble size | Code complexity | How hard this file is |
| Color intensity (red) | Change frequency (churn) | How often it hurts you |
| Nesting | Folder hierarchy | Where it lives |

The message compresses to one sentence a manager grasps instantly: **"Refactor the big red bubbles first: these are your top productivity blockers, based on the last 12 months of actual work."** Because it is grounded in real churn, not abstract complexity, it reads as ROI rather than perfectionism.

Tools: `code-forensics` and CodeScene (both built on Adam Tornhill's code-maat) generate these in minutes from git history. This is the same churn-times-complexity data as [[refactoring/refactoring-campaigns]], drawn for an executive audience instead of an engineering one.

Building one takes minutes, not a project:

1. Clone the repository you want to analyze.
2. Scaffold a small Node project with `code-forensics` and Gulp.
3. Point the gulpfile at the repository path.
4. Run the hotspot analysis over the last 12 months.
5. Open the local web server; the treemap renders itself.

A 26k-line codebase surfaces its two worst hotspots in that time. Screenshot the treemap, circle the big red bubbles, and that image is your slide.

### Reading the diagram in the room

- **A big pale bubble** (complex, rarely changed): scary but low priority; do not spend the budget here.
- **A small red bubble** (simple, changed constantly): fine; it is doing its job.
- **A big red bubble** (complex and churning): this is where the money leaks. Point at it and say "this is what slows the team every week."

## Telling a Client the Hard Truth

When you must report that a codebase is in bad shape, honesty and diplomacy are not in tension; blame is the thing to avoid.

- **Respect the predecessors.** "Web development moves fast and future constraints are hard to anticipate" is both true and disarming. Never make the previous team the villain; you inherit trust by not spending theirs.
- **Show, don't tell.** Walk them through one concrete, abstracted example: "I expected this to be one word in one file. Changing it here broke seven other places." A demonstrated ripple beats the word "messy".
- **Use visuals.** A dependency diagram or an enclosure diagram conveys cascading complexity without jargon. Non-technical people are not stupid; keep it high-level and they will follow.
- **Reframe your role.** You are the professional who knows modern practice and can chart the way out, not the critic of what exists.
- **Set a boundary.** If the client will not invest in quality at all, declining is legitimate: taking the work guarantees burnout and a worse codebase.

## A Sample Manager Conversation

The shape that works: acknowledge the goal, present evidence, make a bounded ask, name the payback, and offer a small first step.

```
You:      Checkout is our slowest area to change. I pulled the numbers.
Manager:  How slow?
You:      3-4 days per change, and it caused 3 of the last 5 incidents.
          One file, OrderService, is behind most of it. [shows the treemap]
Manager:  Why not just be more careful?
You:      Careful is what makes it slow: every change risks the other 7 places
          it touches. Two focused weeks removes that coupling.
Manager:  Two weeks is a lot. What do we get?
You:      Checkout changes drop from days to hours, and the incident source
          goes away. Payback in under three months, then it is pure saving.
Manager:  Can we do it without stopping features?
You:      Yes. I will do it in small shippable steps behind the current
          behavior, one PR at a time. Nothing goes dark. I can start on the
          worst method this week and show you the first result Friday.
```

Notice what the engineer never said: "the code is bad", "the last team was sloppy", or "cyclomatic complexity". Every sentence is in the manager's currency.

## Timing the Conversation

*When* you raise debt matters as much as *how*.

| Moment | Why it works |
|--------|--------------|
| Right after an incident | The cost is fresh and undeniable |
| When estimating a feature in a hotspot | You can quote the extra days the debt adds |
| At planning, with the treemap | Prioritization is the manager's job; give them the map |
| Never mid-crisis as a lecture | It reads as blame and gets dismissed |

Attach the ask to a decision the manager is already making; do not open a separate "we should talk about quality" meeting that competes with features on its own.

## What Not to Do

| Anti-pattern | Why it backfires | Instead |
|--------------|------------------|---------|
| "The code is a mess" | An opinion, easily dismissed | Show a measured ripple or a hotspot |
| Blaming the previous team | Burns trust, invites defensiveness | Focus on the code, not the coder |
| Asking for a big "refactoring project" | Reads as risk with no feature value | Fold small refactors into feature work |
| Cyclomatic-complexity charts for execs | Speaks a language they do not | An enclosure diagram and a cost number |
| Alarmism ("it will all collapse") | Cries wolf, loses credibility | A prioritized, evidence-based plan |

## Rule

> Managers do not fund "clean code"; they fund predictability, saved cost, and retained talent. Translate every technical claim into one of those, back it with a number and a picture, and ask for a small bounded step, not a project.

## Related

- [[refactoring/refactoring-campaigns]] - the hotspot data (churn x complexity) behind enclosure diagrams, for the engineering audience.
- [[legacy/legacy-techniques]] - the techniques you fund by winning these arguments.
- [[legacy/strangler-fig]] - the "no big-bang rewrite" story that reassures a nervous stakeholder.
