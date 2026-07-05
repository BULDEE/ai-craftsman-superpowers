# Taking Over a Legacy Codebase

> "Make it better, not perfect. Improve the system by 1% and let it compound." - Nicolas Carlo

Inheriting an unfamiliar, undocumented, under-tested codebase is the most common and most daunting legacy situation. This file is the playbook for the first days: how to gain a foothold, build understanding without drowning, and find the humans who still hold the context. It feeds the `/craftsman:legacy audit` flow.

## The Mindset

- **Stay curious, not frustrated.** You are rarely alone in this; colleagues and stakeholders hold context that makes the mess tractable. Ask.
- **Better, not perfect.** You will not understand everything, and you do not need to. Consistent 1% improvements compound; demanding perfection guarantees overwhelm.
- **Accept partial understanding.** Comprehension deepens over time; act on what you know and expand the edge of the known gradually.

## First Moves, In Order

Momentum comes from solving foundational problems one at a time, not everything at once.

| Step | Why first |
|------|-----------|
| 1. Get it running locally | Nothing else is possible until you can execute it |
| 2. Get the tests running | A green (or any) suite is your first safety signal |
| 3. Get it deploying | Understanding the release path demystifies the system |
| 4. Take notes as you go | Your newcomer perspective is a fresh, perishable asset |
| 5. Read the classics | Feathers' *Working Effectively with Legacy Code* expands your toolbox beyond intuition |

Capture notes in plain markdown or short ADRs ([[legacy/communicating-tech-debt]] links to why ADRs earn maintainer esteem): terminology, gotchas, "why is it like this" answers. What is obvious to you now will be invisible in a month.

## Dive From the Edges, Not the Middle

Attacking a large codebase from the center causes overwhelm. Start where you can *observe* the system working: its edges.

- **Input edges:** the button, form, API endpoint, or CLI command that triggers your use case.
- **Output edges:** the HTTP response, the rendered page, the written file, the DB row.

Then trace between them:

1. **Find a checkpoint.** Search for the unique button text, route, or class name that starts your use case.
2. **Bookmark it** in your editor so you can always return.
3. **Follow execution with a debugger**, watching how data transforms step by step.
4. **Track the data**, not the control flow: values reveal intent faster than reading every branch.
5. **Expand the known edge.** Add a bookmark wherever understanding stops; that boundary is your work list.
6. **Reach the opposite edge** (the HTTP call, the response, the persisted result).

If you get lost, restart from the last checkpoint. Leave clarifying comments and tiny safe refactorings (a rename) as you go, but keep your eyes on the use case, not on every mess you pass.

```
[UI button "Place order"]  <- input edge, your checkpoint
        | debugger, watch the data
   OrderController -> PlaceOrder -> Order::place() -> OrderRepository::save()
        | keep going, bookmarking the edge of the unknown
[HTTP 201 + order id]      <- output edge, you now understand one full path
```

One traced path is worth a hundred pages skimmed: you now own a slice of the system with certainty.

## Knowledge Maps: Find Who Still Knows

Code is only half the inheritance; the other half is *who understands it*. A **Knowledge Map** turns git history into a picture of ownership: for each file, who has committed most. Built in about ten minutes with `code-forensics` over a year of history, it renders as an enclosure diagram of contributors.

What it tells you:

| Signal | What to do |
|--------|-----------|
| One person owns a hot file | That is who to ask; also a bus-factor risk |
| The top contributor has left | Critical knowledge is gone; prioritize documenting/testing it |
| A region is untouched for years | Knowledge is likely lost; treat changes there with extra care |
| Ownership does not match team structure | Organizational misalignment worth surfacing |

This is the same git-history data as [[refactoring/refactoring-campaigns]] hotspots, aimed at people instead of files: it answers "who do I ask?" and "where is the risk if they leave?".

## Refactor and Test as You Go

Two habits turn passive reading into active understanding:

- **Refactor as you learn.** The moment you decode a cryptic name, rename it. Your fresh eyes make implicit logic explicit for the next newcomer; that clarity is cheapest to add now.
- **Write the missing tests.** A characterization test on the code you are about to touch does three things at once: it teaches you the behavior, it de-risks your change, and it exposes design problems ([[legacy/characterization-testing]]). Testing existing code comprehends it faster and more safely than staring at it.

## The Seven-Point Checklist

1. Stay curious; ask people.
2. Get it running (then tests, then deploy).
3. Take notes as you go.
4. Refactor as you go (start with names).
5. Read the classic legacy books.
6. Write the missing tests on what you touch.
7. Make it better, not perfect.

## Mapping to This Plugin

- `/craftsman:legacy audit` produces the hotspot and dependency picture that tells you *where* to point the edge-diving technique first.
- The Knowledge Map complements the audit: hotspots say *what* is risky, the map says *who* to ask about it.
- Notes and decisions belong in ADRs; the `doc-writer` agent can help formalize them.

## Related

- [[legacy/legacy-techniques]] - the seams and moves you apply once you understand a slice.
- [[legacy/characterization-testing]] - the net that makes "write the missing tests" safe.
- [[refactoring/refactoring-campaigns]] - hotspots and knowledge distribution from the same git data.
- [[legacy/communicating-tech-debt]] - turning what you learn into a case management will fund.
