# Legacy Rescue Playbook

A field guide for the hardest job in software: changing code you are afraid to touch. This is the operational companion to the `/craftsman:legacy` command and the legacy knowledge pillars. It presents the working developer's toolbox for regaining control of an untested, undocumented codebase, step by step.

## What You'll Learn

- [x] How to get a foothold in an inherited codebase in the first days
- [x] How to prioritize where to spend effort (hotspots, not everything)
- [x] How to get untestable code under test without breaking it first
- [x] How to make large structural changes without ever leaving the build red
- [x] How to explain the work to non-technical stakeholders

## Prerequisites

- Familiarity with the [Beginner](./beginner.md) and [Intermediate](./intermediate.md) guides
- `/craftsman:legacy` available (run `/craftsman:healthcheck` to confirm)

---

## The One Rule

> Legacy code is not old code. It is code you are afraid to change because nothing tells you when you break it.

Every technique below serves a single loop:

```
1. Get a safety net around the part you must touch
2. Make the change under the net
3. Refactor, net still green
```

Never skip step 1. A change without a net is a bet, not an engineering decision.

---

## Phase 1: Get a Foothold

You have just inherited an unfamiliar system. Resist the urge to read everything or "clean it up." Solve foundational problems one at a time.

| Move | Why first |
|------|-----------|
| Run it locally | Nothing else is possible until you can execute it |
| Run the tests (if any) | Any signal, even a red suite, is your first instrument |
| Deploy it once | Understanding the release path demystifies the whole system |
| Take notes as you go | Your newcomer perspective is a fresh, perishable asset |

**Mindset:** better, not perfect. You will not understand everything and you do not need to. Consistent 1% improvements compound; demanding total comprehension guarantees overwhelm.

Start here in the tool:

```
/craftsman:legacy audit
I just inherited this codebase. No tests, no docs. Where do I start?
```

The audit confirms the basics, ranks the risk, and produces a `LEGACY-AUDIT.md` that tells you where to begin, not everything that is wrong. See [taking-over-legacy](../../knowledge/legacy/taking-over-legacy.md).

---

## Phase 2: Prioritize by Hotspot

Not all debt is worth the same. The best signal for *where* to refactor combines two dimensions from behavioral code analysis:

- **Complexity** (how hard the file is to understand)
- **Churn** (how often it actually changes, from git history)

A file that is complex *and* changes constantly is a productivity tax you pay every sprint. A file that is complex but never changes can be left alone.

```
Complexity
  high │  refactor        │  refactor
       │  when it slows    │  FIRST
       │  you (top-left)   │  (top-right)
       │───────────────────┼──────────────
       │  leave alone      │  keep clean
   low │  (bottom-left)    │  (bottom-right)
       └───────────────────┴──────────────
              low churn         high churn
```

Rank your codebase without any external tool:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/lib/hotspot_analysis.py" --since 12.month --top 15
```

Already running SonarQube, CodeScene, or PHPStan? Feed their report in instead of recomputing a weaker signal:

```
/craftsman:legacy audit --from sonar-report.json
```

The plugin is the action layer on top of those tools, not a competitor. See [refactoring-campaigns](../../knowledge/refactoring/refactoring-campaigns.md) and [tooling-integration](../../knowledge/tooling-integration.md).

---

## Phase 3: Get a Net (Characterization Testing)

When you must change code with no tests, you cannot start from the specification: you do not yet know what the code is *supposed* to do, only what it *does*. A characterization test pins the current behavior, bugs and all, so you can refactor underneath it.

The same idea travels under several names, all interchangeable: characterization test, golden master, snapshot test, approval test.

```
/craftsman:legacy cover
I need to refactor calculateShipping() but there are no tests and it prints to stdout.
```

The recipe:

1. **Silence side effects with a seam.** A *seam* is a place where you can change behavior without editing there. Extract the `print` into a `log()` method, subclass, and override `log()` to do nothing in the test.
2. **Record current behavior.** Run the code across representative inputs and capture the output as the approved baseline.
3. **Prove the net catches change.** Introduce a deliberate mistake; a test *must* go red. A net that never fails protects nothing. Revert the break.

Only now is the code safe to change. Bugs you discovered are *frozen* for now; fix them deliberately later, one at a time. See [characterization-testing](../../knowledge/legacy/characterization-testing.md) and [legacy-techniques](../../knowledge/legacy/legacy-techniques.md).

### The dependency-breaking toolbox

| Technique | Use when |
|-----------|----------|
| **Subclass & Override** | A method does something untestable (I/O, clock, randomness); override it in a test subclass |
| **Wrap & Sprout** | You must add behavior to a scary method; write the new logic in a fresh, tested method and call it from the old one |
| **Extract & Decouple Core** | The logic worth testing is buried in glue code; extract it to a pure function you can test directly |

These are ordinary developer techniques, not magic. Reach for the least invasive one that gets the code under test.

---

## Phase 4: Change Under the Net

With a green net, you can finally make the structural change. Two disciplines keep you safe.

### Small, always-green steps

Every refactoring is a sequence of tiny, behavior-preserving moves, each followed by a green test run and a commit. If the net goes red, the *last* move is the culprit; revert it. You are never more than one `git revert` from safety. See [refactoring-techniques](../../knowledge/refactoring-techniques.md).

### The Mikado Method for the big ones

When a change is large and full of unknown unknowns, do not open a giant branch that stays broken for a week. Instead, discover the graph of prerequisites one timebox at a time, and only ever commit code that works.

```
1. Attempt the change directly
2. It breaks something → note the prerequisite, REVERT
3. Do the prerequisite first (recurse if it too has prerequisites)
4. Once leaves are done, the original change applies cleanly
```

Anything you discover but are not tackling right now goes in a **Parking** list so you stay focused. See [mikado-method](../../knowledge/refactoring/mikado-method.md).

```
/craftsman:refactor
Untangle OrderService using Mikado; keep every commit green.
```

---

## Phase 5: Migrate the Big Stuff (Strangler Fig)

To replace a whole subsystem without a risky big-bang rewrite, grow the new implementation *around* the old one and cut over route by route. A routing layer (branch-by-abstraction) sends a slice of traffic to the new path; when every slice is migrated, the old code is deleted. The system is shippable the entire time. See [strangler-fig](../../knowledge/legacy/strangler-fig.md).

```
/craftsman:legacy migrate
Replace the legacy TaxEngine with a new pricing service, one route at a time.
```

---

## Phase 6: Communicate the Work

Refactoring is blocked more often by a failure to communicate than by difficulty. Managers fund outcomes, not "code quality." Translate debt into business language:

> "Checkout changes take days and caused two recent incidents. One file is the cause. Two focused weeks drop that to hours per change, payback under three months."

Ground the case in real churn, not abstract complexity, and it reads as ROI rather than perfectionism. When talking about the codebase, **focus on the code, not the coder**: never use churn or knowledge maps to rank people; that destroys the trust the analysis depends on. See [communicating-tech-debt](../../knowledge/legacy/communicating-tech-debt.md).

---

## Putting It Together

For a serious rescue, chain the whole pipeline:

```
/craftsman:legacy audit          # map risk, pick the hotspot
  → /craftsman:legacy cover       # net the file you must change
  → /craftsman:legacy untangle    # break dependencies
  → /craftsman:refactor           # Mikado, green every step
  → /craftsman:legacy migrate     # strangler-fig the subsystem
```

For a large, multi-week effort, hand the campaign to the `legacy-surgeon` agent or the `legacy-takeover` team template, which sequences an architect, the surgeon, a security review, and documentation.

## Practice

Refactoring is a motor skill; you build it by repetition under constraints. Drill the reflexes on a small, self-contained kata before you need them on production code. The `refactoring-katas` knowledge file curates a progression from tangled-but-simple to production-like chaos. See [refactoring-katas](../../knowledge/refactoring/refactoring-katas.md).

---

## Knowledge References

- [taking-over-legacy](../../knowledge/legacy/taking-over-legacy.md) - first days in an inherited codebase
- [characterization-testing](../../knowledge/legacy/characterization-testing.md) - building the safety net
- [legacy-techniques](../../knowledge/legacy/legacy-techniques.md) - the dependency-breaking toolbox
- [communicating-tech-debt](../../knowledge/legacy/communicating-tech-debt.md) - the stakeholder conversation
- [strangler-fig](../../knowledge/legacy/strangler-fig.md) - incremental subsystem replacement
- [mikado-method](../../knowledge/refactoring/mikado-method.md) - large changes without a broken build
- [refactoring-campaigns](../../knowledge/refactoring/refactoring-campaigns.md) - hotspot prioritization
- [refactoring-techniques](../../knowledge/refactoring-techniques.md) - the behavior-preserving move catalog
- [refactoring-katas](../../knowledge/refactoring/refactoring-katas.md) - deliberate practice
- [tooling-integration](../../knowledge/tooling-integration.md) - consuming SonarQube / CodeScene / PHPStan reports
