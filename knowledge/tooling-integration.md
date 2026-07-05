# Integrating With Analysis Tools

> This plugin is the **action layer**, not another analysis tool. It consumes what SonarQube, PHPStan, ESLint, deptrac, and CodeScene find, and turns it into SOLID/Clean transformations enforced in the AI loop.

A frequent, fair objection: "We already have static-analysis and complexity tools. Are you duplicating them?" The answer is no, and this file is the explicit boundary so the answer holds up under scrutiny.

## What Mature Tools Do, and Where They Stop

| Tool | Finds | Where it runs | Stops at |
|------|-------|---------------|----------|
| SonarQube | Complexity, smells, coverage, security | CI, dashboard | A report a human reads later |
| PHPStan / Psalm | Type errors, dead code, level rules | CLI, CI | A list of violations |
| ESLint / Biome | Lint, complexity, style | Editor, CI | Auto-fixable nits + warnings |
| deptrac / dependency-cruiser | Layer/architecture violations | CI | A pass/fail on boundaries |
| CodeScene / code-forensics | Hotspots, change coupling, knowledge maps | Periodic analysis | A visualization |

They answer **"what is wrong."** None of them answer **"what do I do about it, right now, in the code I am writing."** That gap is this plugin.

## What This Plugin Adds (the Action Layer)

| Dimension | Analysis tools | This plugin |
|-----------|----------------|-------------|
| When | CI / on demand / periodic | **Write-time: every Write and Edit in the AI loop** |
| Consumer | A human reading a dashboard | **Claude, which self-corrects before you see the code** |
| Output | A number or a flag | **A SOLID/Clean transformation + the technique to apply** |
| Question answered | "What is wrong?" | "**What do I do, and how?**" |

A tool says "cognitive complexity 71." The plugin says "this is a god class: Extract Class here, push the rule into the entity, here is the resulting code," and blocks the write until Claude complies. That is a different job.

## The Rule: Consume, Don't Re-Compute

Where a tool's output exists, **use it**; do not produce a worse second opinion.

- **L2 static analysis** already delegates to the real tools: `vendor/bin/phpstan analyse --level=max`, ESLint, ruff/mypy, shellcheck. The plugin maps their errors into its rule vocabulary; it does not re-implement type inference.
- **L3 architecture** delegates to `deptrac` / `dependency-cruiser` for the Dependency Rule; it does not re-write a layer checker.
- **`/craftsman:legacy audit --from <report>`** ingests an existing SonarQube, PHPStan, ESLint, or CodeScene report as the complexity/hotspot signal, and only falls back to its own computation when no report is provided.

The single source of truth stays the tool the team already trusts. The plugin's job is to act on it.

## Why a Built-In Fallback Still Exists

`hooks/lib/structural_metrics.py` computes `NEST001` (nesting), `LOC001` (method length), `GOD001` (class span), and `PARAM001` (parameter count). On the surface these overlap with SonarQube and PHPStan. They exist for two reasons a CI tool cannot cover, not to compete:

1. **Zero-dependency, real-time signal.** It runs on **every** Write/Edit, in milliseconds, with **no tool installed** (Level 1 of the quality gate). SonarQube runs in CI, minutes to hours later; it is not in the write loop. The fallback is what makes the gate work on a fresh machine and on the very keystroke that introduces the smell.
2. **Language-agnostic.** One brace-aware analyzer covers PHP, TypeScript, Python, and more, so a new pack inherits structural rules before anyone wires up a language-specific tool.

When a real tool **is** present, prefer it: the fallback is the floor, not the ceiling.

## Wiring It Up

Two concrete moves make "consume, don't re-compute" real on a project that already runs tools:

```bash
# 1. Feed an existing report into the legacy audit instead of recomputing.
/craftsman:legacy audit --from sonar-report.json
/craftsman:legacy audit --from codescene-hotspots.csv
/craftsman:legacy audit --from phpstan.json

# 2. Silence the built-in rule that a trusted tool already owns, in .craft-rules.yml
```

```yaml
# .craft-rules.yml - SonarQube owns complexity here, so stand the duplicate down.
rules:
  GOD001: off        # SonarQube's cognitive-complexity gate is the source of truth
  LOC001: warn       # keep as a soft real-time hint only
```

The plugin still enforces everything a tool does *not* cover (DDD layering at write-time, value-object usage, the SOLID/Clean transformation), and now speaks with one voice on the metrics a tool already owns.

## Resolving Conflicts (Two Opinions)

If the tool and the built-in fallback disagree (SonarQube says "fine", `GOD001` fires), the rule is:

- **The configured tool wins on its own axis.** If the team runs SonarQube with a tuned complexity threshold, that threshold is the source of truth; relax or disable the overlapping built-in rule via the rules engine (`GOD001: off` at project or directory level).
- **The built-in wins only when no tool covers that axis** (a fresh repo, a language with no analyzer, the pre-CI moment).

Never maintain two live thresholds for the same metric; pick the tool the team trusts and silence the duplicate.

## Positioning in One Sentence

> Analysis tools tell you *what* is wrong. This plugin ingests that, tells the AI *what to do about it*, and enforces the SOLID/Clean fix at write-time. It sits on top of your tools, not in their lane.

## Related

- [[refactoring/refactoring-campaigns]] - hotspots (churn x complexity); ingests a CodeScene report when available, computes from git otherwise.
- [[legacy/communicating-tech-debt]] - turning tool output (enclosure diagrams) into a management case.
- [[principles]] - the SOLID targets the action layer transforms code toward.
- [[clean-architecture]] - the boundaries deptrac verifies and the plugin enforces in the write loop.
