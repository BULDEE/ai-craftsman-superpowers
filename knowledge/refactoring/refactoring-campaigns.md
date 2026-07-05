# Refactoring Campaigns

> "When everything is urgent, nothing is."

A refactoring **campaign** is a deliberate, multi-file improvement effort, not a one-off tidy-up. The danger in a large legacy codebase is drowning: a static-analysis tool reports thousands of issues, fixing them all would take years, and stakeholders will not pay to change code that "works" for the sake of a metric. A campaign succeeds by being **ruthlessly prioritized**: touch the few places where improvement actually pays back, and leave the rest.

## Where to Start: Hotspots

Not all technical debt is worth the same. The best signal for *where* to spend refactoring effort combines two dimensions (Adam Tornhill's behavioral analysis, via Nicolas Carlo):

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

## Executing a Campaign

- **Safety net first.** Every hotspot you touch gets a characterization net before you change it ([[legacy/characterization-testing]]). No net, no refactor.
- **Batch by hotspot, not by rule.** Fix one file (or one aggregate) thoroughly, ship it, move on. Sweeping one rule across a hundred files produces an un-reviewable diff and stalls.
- **Micro-commit.** Commit every small, safe step; keep PRs reviewable. A campaign is a long chain of tiny green commits, not one heroic branch (see [[refactoring/mikado-method]] on shipping often).
- **Be opportunistic (the Boy Scout Rule).** When you are already editing a hotspot for a feature, leave it a little cleaner. Campaign work folded into feature work is the cheapest debt repayment there is.
- **The daily refactoring hour.** A standing, time-boxed slot keeps the campaign moving without a big-bang project nobody funds.

## Measuring a Campaign

Track the hotspot scores over time so the campaign shows results, not just activity. This plugin records violations, corrections, and structural metrics in its SQLite store (via `metrics-query.py`); a hotspot's complexity and violation counts trending down across sessions is the evidence that the campaign is working. Falling change-cost on the top-right files is the outcome that matters; line-coverage or issue-count deltas are weaker proxies.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Refactor everything | Years of work, no stakeholder buy-in, burnout | Only the top-right quadrant |
| Prioritize by severity alone | You fix critical issues in never-touched files | Factor in churn |
| No safety net | Silent regressions during the campaign | Characterize each hotspot first |
| One rule across all files | Un-reviewable diff, high merge-conflict risk | Batch by hotspot and ship each |
| Big-bang refactoring project | Unfunded, unfinished, drifts from main | Fold into feature work + a daily hour |

## Related

- [[legacy/characterization-testing]] - the net every hotspot gets before you touch it.
- [[legacy/legacy-techniques]] - the seams and moves used inside each hotspot.
- [[refactoring/mikado-method]] - discovering and delivering a large hotspot change without breaking main.
- [[refactoring-techniques]] - the safe transformations a campaign applies.
