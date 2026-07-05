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

## Telling a Client the Hard Truth

When you must report that a codebase is in bad shape, honesty and diplomacy are not in tension; blame is the thing to avoid.

- **Respect the predecessors.** "Web development moves fast and future constraints are hard to anticipate" is both true and disarming. Never make the previous team the villain; you inherit trust by not spending theirs.
- **Show, don't tell.** Walk them through one concrete, abstracted example: "I expected this to be one word in one file. Changing it here broke seven other places." A demonstrated ripple beats the word "messy".
- **Use visuals.** A dependency diagram or an enclosure diagram conveys cascading complexity without jargon. Non-technical people are not stupid; keep it high-level and they will follow.
- **Reframe your role.** You are the professional who knows modern practice and can chart the way out, not the critic of what exists.
- **Set a boundary.** If the client will not invest in quality at all, declining is legitimate: taking the work guarantees burnout and a worse codebase.

## What Not to Do

| Anti-pattern | Why it backfires | Instead |
|--------------|------------------|---------|
| "The code is a mess" | An opinion, easily dismissed | Show a measured ripple or a hotspot |
| Blaming the previous team | Burns trust, invites defensiveness | Focus on the code, not the coder |
| Asking for a big "refactoring project" | Reads as risk with no feature value | Fold small refactors into feature work |
| Cyclomatic-complexity charts for execs | Speaks a language they do not | An enclosure diagram and a cost number |
| Alarmism ("it will all collapse") | Cries wolf, loses credibility | A prioritized, evidence-based plan |

## Related

- [[refactoring/refactoring-campaigns]] - the hotspot data (churn x complexity) behind enclosure diagrams, for the engineering audience.
- [[legacy/legacy-techniques]] - the techniques you fund by winning these arguments.
- [[legacy/strangler-fig]] - the "no big-bang rewrite" story that reassures a nervous stakeholder.
