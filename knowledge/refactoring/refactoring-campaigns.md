# Refactoring Campaigns

> "When everything is urgent, nothing is."

A refactoring **campaign** is a deliberate, multi-file improvement effort, not a one-off tidy-up. The danger in a large legacy codebase is drowning: a static-analysis tool reports thousands of issues, fixing them all would take years, and stakeholders will not pay to change code that "works" for the sake of a metric. A campaign succeeds by being **ruthlessly prioritized**: touch the few places where improvement actually pays back, and leave the rest.

## Where to Start: Hotspots

Not all technical debt is worth the same. The best signal for *where* to spend refactoring effort combines two dimensions drawn from behavioral code analysis:

- **Complexity**: how hard the code is to understand and change.
- **Churn**: how often it actually changes.

A file that is complex **and** changed often is a bottleneck slowing the team every week. A file that is complex but never touched costs nothing today. Prioritize the intersection.

## Computing a Hotspot Map

### 1. Complexity

Any reasonable metric works; having a metric beats hunting for the perfect one. Cyclomatic complexity is popular; when no tool exists for your language, **lines of code** is a serviceable proxy (bigger files trend more complex). This plugin computes structural complexity via its `NEST001` (nesting), `LOC001` (file size), and `GOD001` (god class) signals in `structural_metrics.py`.

### 2. Churn

Churn comes straight from version-control history; twelve months is representative.

```bash
git log --format=format: --name-only --since=12.month \
  | egrep -v '^$' \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -50
```

- `git log --format=format: --name-only --since=12.month` - just the changed file names over a year.
- `egrep -v '^$'` strips blank lines; `sort | uniq -c` counts each file; `sort -nr | head -50` keeps the 50 most-changed.
- Filter noise with another `egrep`, e.g. drop generated files: `| egrep -v '\.json$'`.

For a codebase abandoned for months, shift the window to the last active period: `--since=16.month --until=4.month`.

### 3. Combine

Plot complexity on the Y axis and churn on the X axis. The quadrants tell you what to do:

| Quadrant | Complexity | Churn | Action |
|----------|-----------|-------|--------|
| Top-right | High | High | **Refactor first** - the bottleneck |
| Top-left | High | Low | Ignore, unless you expect to touch it soon |
| Bottom-right | Low | High | Fine; simple and it works |
| Bottom-left | Low | Low | Leave it alone |

Tools that automate the whole map: `churn-php` (PHP), `code-complexity` (Node, language-agnostic), Code Climate, and CodeScene. This plugin's `/legacy audit` and planned `hotspot_analysis.py` produce the same ranking and render it in the audit report.

## Prioritization: An Eisenhower Matrix for Code

The hotspot map is the Eisenhower matrix applied to code: **Important = Complexity, Urgent = Churn**. "Do first" is the top-right; the rest waits or is dropped. Refactoring those files first has a measurable impact on velocity, because the team is very likely to work in them again soon.

When two hotspots compete, rank by **return on investment**: expected reduction in future change-cost divided by the effort to refactor. A greedy pass down that ROI-ordered list clears the biggest bottleneck first and keeps the campaign delivering value even if it is cut short. Refactoring is effectively infinite; the goal is not to finish, it is to spend a bounded budget where it pays back most.

## A Worked Hotspot Ranking

Suppose the churn command and a complexity tool give you this for a Symfony backend:

| File | Complexity | Churn (12mo) | Quadrant | Verdict |
|------|-----------|--------------|----------|---------|
| `Application/Checkout/CheckoutHandler.php` | 48 | 61 | top-right | **Refactor first** |
| `Domain/Pricing/PriceCalculator.php` | 39 | 44 | top-right | **Refactor second** |
| `Infrastructure/Legacy/TaxEngine.php` | 71 | 3 | top-left | Ignore (nobody touches it) |
| `Infrastructure/Meta/AdsClient.php` | 12 | 52 | bottom-right | Fine (simple, stable enough) |
| `Domain/Catalog/Sku.php` | 6 | 4 | bottom-left | Leave alone |

The campaign plan writes itself: `CheckoutHandler` and `PriceCalculator` are the only two worth a deliberate effort now. `TaxEngine` is scary (71 complexity) but irrelevant this quarter because it barely changes; spending days on it would be pure vanity metric. You attack `CheckoutHandler` first: characterize it, extract its use case from the controller, break the god method into intention-revealing steps, and ship each in a reviewable PR. When a feature later forces you into `TaxEngine`, that is the moment to clean it, not before.

### Before and after on the first hotspot

The refactor of a top-right hotspot is small, safe steps, not a rewrite. `CheckoutHandler` starts as a god method:

```php
// Before - one method validates, prices, persists, charges, and formats.
final class CheckoutHandler
{
    public function __invoke(Request $request): JsonResponse
    {
        $items = $request->get('items');
        if (empty($items)) { return new JsonResponse(['error' => 'empty'], 422); }
        $total = 0;
        foreach ($items as $i) { $total += $i['price'] * $i['qty']; }        // pricing
        if ($request->get('coupon')) { $total = $total * 0.9; }              // rule
        $this->em->getConnection()->insert('orders', ['total' => $total]);   // persistence
        $this->stripe->charge($total);                                       // side effect
        return new JsonResponse(['total' => number_format($total / 100, 2)]);// formatting
    }
}
```

```php
// After - the god method is decomposed; each concern has a home.
final readonly class PlaceOrder                 // Application use case
{
    public function __construct(
        private OrderRepository $orders,
        private PaymentGateway $payments,
    ) {}

    public function __invoke(PlaceOrderCommand $command): OrderId
    {
        $order = Order::place($command->lines, $command->coupon); // pricing + rules in the entity
        $this->payments->charge($order->total());
        $this->orders->save($order);
        return $order->id();
    }
}
// The controller now only translates HTTP <-> command/response; the presenter formats.
```

Each move (Extract Function, Move Statements, Introduce Parameter Object) ships as its own green commit under the characterization net.

## Beyond Hotspots: X-Ray Techniques

Churn-times-complexity finds the *files* worth refactoring. Behavioral code analysis goes further, mining git history for signals a single snapshot cannot show:

| Technique | What it reveals | Action |
|-----------|-----------------|--------|
| **X-Ray to function level** | Which *functions* inside a hot file actually churn (diffs parsed against function definitions) | Refactor the hot method, not the whole 2k-line file |
| **Change (temporal) coupling** | Files that keep changing *together* over time | Co-locate them, or remove the hidden coupling / copy-paste |
| **Code age** | Stable-old and brand-new code is healthy; constantly-patched code is not | Target the *unstable* code; leave stable old code alone |
| **Knowledge distribution** | Contributor concentration per module (diffusion score) | Many minor contributors in 3 months = higher bug risk; consolidate ownership |

Two rules from the same source sharpen prioritization:

- **The trend matters more than the threshold.** A file whose complexity is *rising* release over release is a better target than one that is merely large and stable.
- **Coupled things should be co-located.** If `OrderService` and `InvoicePrinter` always change together but live in different modules, that temporal coupling is a design smell to fix, not a coincidence.

A hard caveat: **never use these metrics to evaluate individuals.** Knowledge maps and churn are for finding risk and asking for help, not for ranking people; misusing them destroys the trust the analysis depends on. See [[legacy/taking-over-legacy]] for the who-to-ask side of the same data.

## Executing a Campaign

- **Safety net first.** Every hotspot you touch gets a characterization net before you change it ([[legacy/characterization-testing]]). No net, no refactor.
- **Batch by hotspot, not by rule.** Fix one file (or one aggregate) thoroughly, ship it, move on. Sweeping one rule across a hundred files produces an un-reviewable diff and stalls.
- **Micro-commit.** Commit every small, safe step; keep PRs reviewable. A campaign is a long chain of tiny green commits, not one heroic branch (see [[refactoring/mikado-method]] on shipping often).
- **Be opportunistic (the Boy Scout Rule).** When you are already editing a hotspot for a feature, leave it a little cleaner. Campaign work folded into feature work is the cheapest debt repayment there is.
- **The daily refactoring hour.** A standing, time-boxed slot keeps the campaign moving without a big-bang project nobody funds.

## Measuring a Campaign

Track the hotspot scores over time so the campaign shows results, not just activity. This plugin records violations, corrections, and structural metrics in its SQLite store (via `metrics-query.py`); a hotspot's complexity and violation counts trending down across sessions is the evidence that the campaign is working. Falling change-cost on the top-right files is the outcome that matters; line-coverage or issue-count deltas are weaker proxies.

A campaign scoreboard makes progress visible and fundable:

| Metric | Start | After 4 weeks | Reads as |
|--------|-------|---------------|----------|
| Top-right hotspots | 5 | 2 | Bottlenecks being cleared |
| `CheckoutHandler` complexity | 48 | 19 | The worst offender is tamed |
| `GOD001` violations (top-right files) | 3 | 0 | God classes decomposed |
| Median time-to-change a hotspot | 2 days | 4 hours | The velocity win, the real payoff |

Report the **velocity** number to stakeholders (time-to-change), not the complexity score. "We ship checkout changes in hours instead of days" funds a campaign; "cyclomatic complexity dropped 60%" does not.

## Campaign Playbooks

Most campaigns fit one of a few shapes. Each is a bounded, shippable arc, not an open-ended cleanup.

### Decompose a God Class

1. Rank god classes by churn; take the top-right one (`GOD001` + high churn).
2. Characterize its public behavior ([[legacy/characterization-testing]]).
3. List its distinct responsibilities; Extract Class one at a time, committing each.
4. Push rules into entities/value objects; put I/O behind ports.
5. Reduce the original to a thin orchestrator or delete it. Stop when `GOD001` clears.

### Kill Primitive Obsession Codebase-Wide

1. Grep for the offending primitive in signatures (`string $email`, `int $amount`).
2. Introduce the value object once ([[anti-patterns/primitive-obsession]]).
3. Migrate call sites hotspot-first, not alphabetically; each file is one commit.

```php
// The mechanical, safe transformation applied per hotspot.
- public function register(string $email): void
+ public function register(Email $email): void
```

### Extract a Bounded Context

1. Identify a cluster of high-churn files that speak one sub-language.
2. Draw the seam (a facade or an interface) around it; route callers through it.
3. Strangle it into its own module behind that seam ([[legacy/strangler-fig]]).
4. Delete the seam once the context stands alone.

Each playbook has a clear "done", which is what keeps a campaign from becoming an infinite refactor.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Refactor everything | Years of work, no stakeholder buy-in, burnout | Only the top-right quadrant |
| Prioritize by severity alone | You fix critical issues in never-touched files | Factor in churn |
| No safety net | Silent regressions during the campaign | Characterize each hotspot first |
| One rule across all files | Un-reviewable diff, high merge-conflict risk | Batch by hotspot and ship each |
| Big-bang refactoring project | Unfunded, unfinished, drifts from main | Fold into feature work + a daily hour |

## Quick-Start Checklist

1. Run the churn command over the last 12 months.
2. Get a complexity score (or fall back to lines of code).
3. Plot churn vs complexity; mark the top-right quadrant.
4. Pick the single highest-churn, highest-complexity file.
5. Characterize its behavior before changing anything.
6. Apply one safe refactoring per commit; ship reviewable PRs.
7. Record the file's complexity and time-to-change; repeat with the next hotspot.

## Rule

> Spend your refactoring budget where the code is both complex and changing. Everywhere else, leave it alone: a campaign that touches everything finishes nothing.

## Related

- [[legacy/characterization-testing]] - the net every hotspot gets before you touch it.
- [[legacy/legacy-techniques]] - the seams and moves used inside each hotspot.
- [[refactoring/mikado-method]] - discovering and delivering a large hotspot change without breaking main.
- [[refactoring-techniques]] - the safe transformations a campaign applies.
