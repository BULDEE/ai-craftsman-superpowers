# Code Smells: The Judgment Layer

> "A smell is a hint that something might be wrong, not a rule that something is." - after Kent Beck & Martin Fowler

The [[refactoring-techniques]] catalogue tells you *how* to change code. This file is about *whether* you should: the judgment layer for the smells that are not clear-cut. Each one below is a signal to think, not an automatic defect. Treating smells as absolute rules produces its own mess (needless indirection, dogmatic splits); the craft is knowing when the smell is real.

## Boolean Parameters

A boolean argument is a common smell because of three real problems:

- **Unreadable at the call site.** `validatePrices(true, passengers, prices)` says nothing; you must open the function to learn what `true` means.
- **It declares the function does two things.** A boolean usually toggles between two behaviors tangled in one body, a Single Responsibility violation. Each new variant tempts another boolean, and you drift toward the "17 props" function.
- **Control coupling.** It is the easiest way to bolt on slightly different behavior, so it becomes a magnet for more mess.

```typescript
// Smell - the caller cannot read intent, the function does two things.
function exportReport(data: Report, asPdf: boolean): Buffer { /* ... */ }
exportReport(report, true);   // true what?

// Fix A - split into two intention-revealing functions.
function exportReportAsPdf(data: Report): Buffer { /* ... */ }
function exportReportAsCsv(data: Report): Buffer { /* ... */ }

// Fix B - a named option when the axis is real and may grow.
function exportReport(data: Report, opts: { format: "pdf" | "csv" }): Buffer { /* ... */ }
exportReport(report, { format: "pdf" });
```

**When a boolean is fine:** when the caller naturally has that value from the outside (UI toggle, a data field) and you would otherwise write a conditional just to pick a function. `setEnabled(value)` beats `if (value) enable(); else disable();`.

| Fix | Use when |
|-----|----------|
| Extract a named variable | Minimum effort; at least the call site reads |
| Options object / named args | The flag is one of several, or more may come |
| Enum / constant | The concept has meaning beyond true/false |
| Split into two functions | The two behaviors are genuinely separate |

## Wrapper Functions (Functions That Just Call Another)

A function whose whole body is `return other()` looks pointless, but the verdict is **it depends**; a wrapper is a diagnostic, not a defect.

**It earns its place when it adds:**
- **Meaning.** `transaction.addRefundRequest()` hides the mechanics behind a business name. The name *is* the value.
- **A seam.** A thin wrapper is where you will later inject behavior, override in a test, or adapt an API (see [[legacy/legacy-techniques]]).
- **An abstraction level.** "Is alive" and "heart is beating" are different levels; a wrapper that raises the level is useful.
- **Future flex.** When the requirement "change the transaction's state on a refund" arrives, the existing wrapper is the one place to add it.

**It is a smell when it is:**
- **A perpetual pass-through** that never adds meaning, seam, or level: pure indirection.
- **A Middle Man**: an intermediate object that forwards most of its calls and represents no real concept.

```php
// Good - the wrapper names a business operation and gives you a place to grow.
public function addRefundRequest(RefundRequest $r): void
{
    $this->refunds->append($r);   // tomorrow: also flip status, emit an event
}

// Smell - Middle Man: forwards everything, means nothing.
public function getName(): string { return $this->details->getName(); }
public function getEmail(): string { return $this->details->getEmail(); }
// ...if TransactionDetails is just a pass-through, inline it.
```

Rule of thumb: refactor a wrapper away only when you *need* to change the code and it reveals a class that carries no concept. Do not delete wrappers preemptively; many are load-bearing.

## "AND" in a Function Name

A name like `getResponseIdAndAddResponseToDb()` reveals a Single Responsibility violation: it mixes a **query** (returns a value) with a **command** (a side effect), which surprises callers and breaks Command-Query Separation ([[principles]]).

But the counter-intuitive craft point: **an honest "AND" name is better than a misleading short one.** It signals the double duty at review time and prevents the bug where a caller assumes a pure query. Naming is a journey, and "AND" is a valid waypoint:

1. Replace the bad name with obvious nonsense (`doStuff`).
2. Get to an honest name.
3. Get to a *completely* honest name, "AND" included.
4. Split the responsibilities (now the "AND" disappears naturally).
5. Introduce a higher-level abstraction.
6. Reach domain-driven naming.

You do not have to reach step 6 today. Staying at step 3, an honest `AND` name, is perfectly fine until you understand the code well enough to split it meaningfully. The smell is the *tangling*, not the word.

## Long Methods: Reveal the Structure First

Before splitting a long method, *see* its shape. A cheap trick: paste the method into a word-frequency counter. The words that repeat most (a variable, a collaborator) reveal the hidden sub-responsibilities and the seams where an Extract Function is natural. This turns "this method is too long" into "these three clusters want to be three methods".

## Defactoring: Removing Abstraction on Purpose

**Defactoring** is the deliberate inverse of extraction: inlining or collapsing an abstraction to make code clearer. It is not a mistake; it is a tool.

Use it when:
- An abstraction **tells you no more than the expression it wraps** (a temp variable holding `(x)` adds cognitive load, not meaning). Inline it.
- An old abstraction **blocks a better refactoring**. Collapse it first, understand the real behavior, then extract differently.

Defactoring is a **cognitive precursor** to refactoring: temporary mental scaffolding. You inline to understand legacy behavior, then re-extract along better lines. This maps to the **two hats**: wearing the *refactoring hat* you minimize abstraction to expose logic; wearing the *change hat* you modify behavior. Switching deliberately tells you whether collapsing an abstraction serves understanding or just destroys useful structure.

```javascript
// Defactor - the variable adds nothing the expression doesn't already say.
- const isEmpty = items.length === 0;
- if (isEmpty) return;
+ if (items.length === 0) return;
```

## Smells That Are Almost Always Real

Not everything is a judgment call. These, this plugin flags or you should treat as near-certain defects:

| Smell | Signal | Fix |
|-------|--------|-----|
| God class | `GOD001` | Extract classes - see [[anti-patterns/god-object]] |
| Deep nesting | `NEST001` | Guard clauses, polymorphism |
| Long method | `LOC001` | Extract Function after revealing structure |
| Too many parameters | `PARAM001` | Introduce Parameter Object |
| Primitive obsession | (review) | Value objects - see [[anti-patterns/primitive-obsession]] |
| Business logic in a controller | controller-leak | Push into a use case |

## Related

- [[refactoring-techniques]] - the mechanical transformations that fix these smells safely.
- [[principles]] - SRP and Command-Query Separation, the principles most of these smells violate.
- [[legacy/legacy-techniques]] - wrappers as seams; defactoring to understand untested code.
- [[clean-code]] - naming, small functions, and the readability these smells trade against.
