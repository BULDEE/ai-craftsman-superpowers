---
model: haiku
description: "Quality metrics and local dashboard. Use when reviewing violation trends, session history, correction patterns, or rendering the aggregated multi-repository dashboard (--dashboard)."
effort: low
disable-model-invocation: true
---

# /craftsman:metrics - Quality Metrics Dashboard

## Outcome Contract

- **Outcome**: a data-grounded picture of code quality trends, and a decision about pending learned instincts.
- **Done when**: trends are read from the metrics database, not estimated; every pending instinct candidate got an explicit approve or reject from the user.
- **Evidence**: the SQLite query output, the hotspot ranking, and the instinct candidate list.

You are a **metrics analyst** reporting on code quality trends.

## Process

### Step 1: Load All Metrics

Use the Bash tool to query the metrics database. Run all 4 queries in a single call:
```bash
DB=$(cat ~/.claude/craftsman-metrics-db-path 2>/dev/null || echo ~/.claude/plugins/data/craftsman/metrics.db); echo "=== VIOLATIONS ===" && sqlite3 -header -column "$DB" "SELECT rule, severity, COUNT(*) as total, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE timestamp > datetime('now','-7 days') GROUP BY rule, severity ORDER BY total DESC;" 2>/dev/null || echo "No metrics yet."; echo "=== TREND ===" && sqlite3 -header -column "$DB" "SELECT date(timestamp) as day, COUNT(*) as violations, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No trend data yet."; echo "=== SESSIONS ===" && sqlite3 -header -column "$DB" "SELECT date(timestamp) as day, COUNT(*) as sessions, SUM(violations_blocked) as blocked, SUM(violations_warned) as warned FROM sessions WHERE timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No session data yet."; echo "=== CORRECTIONS ===" && sqlite3 -header -column "$DB" "SELECT rule, action, COUNT(*) as count FROM corrections WHERE timestamp > datetime('now','-30 days') GROUP BY rule, action ORDER BY count DESC LIMIT 10;" 2>/dev/null || echo "No correction data yet."
```

### Step 2: The semantic layer's own numbers

The Level 2 semantic layer (Haiku subprocesses on Write/Edit and at Stop) costs
real money on every run, and until it recorded anything nobody could say what it
returned. Read its numbers with the shipped function, never by adding rows up
yourself:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/metrics-db.sh" && metrics_haiku_report 30
```

It prints six lines: runs, findings, the share of findings Level 1 never saw on
the same file, the Haiku fixed rate, the Level 1 fixed rate for comparison, and
Haiku seconds per accepted finding.

Two of those lines can legitimately say something other than a percentage, and
what they say matters:

- `not computable yet` on the unseen share means the findings predate the exact
  path column. Report it as "no comparison possible yet", never as zero.
- `n/a` on a fixed rate means no finding has been resolved in the window, which
  is an empty sample and not a rate of zero. **Never recommend turning the layer
  off on an `n/a`.**

**Report them, then say what they mean.** The share Level 1 never saw is the
only thing that justifies a second layer existing. If the Haiku fixed rate is a
NUMBER and comes in below Level 1's after 200 verdicts, say so plainly and
recommend `agent_hooks: false`: that is a measurement, not an opinion. If there
are fewer than 200 verdicts, or either rate is `n/a`, say the sample is too
small and give the count. A recommendation to switch off a layer on a missing
number is worse than no recommendation.

One caveat to state whenever you report the fixed rate: a Haiku finding and a
Level 1 finding are not equally cheap to fix. A missing `declare(strict_types=1)`
is one line; "this aggregate mutates another aggregate's state" may be a
redesign. A lower fixed rate is evidence, not proof, and the two rates are
printed side by side so a reader can weigh that rather than divide.

### Step 3: Does each rule earn its severity

The correction loop records whether a user fixed a finding or suppressed it,
and until #44 nothing read that number back. Measured on one real database
over five months: PHP002 fixed 2 times and ignored 153, a 98.7% rejection,
still blocking every write it fired on. Read the shipped report, never rows
you add up yourself, because it proposes relaxing a gate:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/metrics-db.sh" && metrics_acceptance_report 90
```

It prints acceptance per rule (`fixed / (fixed + ignored)`, lowest first), the
rules proposed for relaxation (under 30% acceptance over 20 or more outcomes,
`--threshold` and `--min-occurrences` to move the bar), each with the
`.craft-rules.yml` line to write, and the share of violations that never
produced any outcome at all.

**Report the proposals; do not apply them.** A relaxation is a decision the
user records as a `decision:` line in the owning manifest (see
`packs/python/pack.yml` for the vocabulary), with the measured rate and the
reason, so the next maintainer does not relitigate it. `n/a` means no outcome
in the window, an empty sample and not a rate of zero.

The no-outcome share is the other half of the picture. A rule that fires
thousands of times with no correction ever recorded is either never acted on
or never observed, and this report cannot tell which: say so, with the count,
rather than reading silence as acceptance.

### Step 4: Present Report

Format the data as a clear report:

```
## Quality Metrics - [Project Name] - Last 7 Days

### Violations by Rule
| Rule | Severity | Total | Blocked | Ignored |
|------|----------|-------|---------|---------|
| ...  | ...      | ...   | ...     | ...     |

### Daily Trend (14 days)
| Day        | Violations | Blocked | Ignored |
|------------|-----------|---------|---------|
| ...        | ...       | ...     | ...     |

### Sessions
| Day        | Sessions | Blocked | Warned |
|------------|----------|---------|--------|
| ...        | ...      | ...     | ...    |

### Acceptance per Rule (90 days)
| Rule | Fixed | Ignored | Acceptance |
|------|-------|---------|------------|
| ...  | ...   | ...     | ...        |

Proposed relaxations: [rule: warn, with the measured rate, or none]
Violations with no recorded outcome: [N rules, X% of the volume]

### Semantic Layer (Level 2, Haiku)
| Metric | Value |
|--------|-------|
| Runs (30d) | ... |
| Findings | ... |
| Findings Level 1 never saw | ... |
| Haiku fixed rate | ... |
| Level 1 fixed rate | ... |
| Seconds per accepted finding | ... |

Verdict on the layer: [keep / too early to say, N verdicts / turn off, and why]

### Key Insights
- Top violation: [rule] ([count] occurrences)
- Trend: [improving/stable/degrading] over last 7 days
- Blocking rate: [X]% of violations were blocked by hooks
```

If no data exists, explain that metrics are collected automatically as the user writes code, and suggest writing some code to start collecting data.

### Step 5: Correction Trends

The corrections data was already loaded in Step 1 (=== CORRECTIONS === section). Use that data to add a **Correction Trends** section to the report:

```
### Correction Trends (30 days)
| Rule | Action | Count |
|------|--------|-------|
| ...  | ...    | ...   |
```

If correction data exists, highlight:
- Rules most frequently auto-corrected (hook learned the pattern)
- Rules most frequently manually fixed (potential for new hook)

### Step 6: Quality Score

Calculate a quality score based on the data already loaded:

```
Score = 100 - (blocked_violations × 5) - (warnings × 1) + (corrections_fixed × 3)
```

Where:
- `blocked_violations` = SUM(blocked) from violations in last 7 days
- `warnings` = COUNT of warned violations in last 7 days
- `corrections_fixed` = COUNT of corrections with action='fix' in last 30 days

Add to the report:

```
### Quality Score
  Score: <X>/100
  Base: 100
  Blocked violations (×5): -<N> (<count> violations)
  Warnings (×1): -<N> (<count> warnings)
  Corrections fixed (×3): +<N> (<count> fixes applied)

  Trend: <↑ Improving | → Stable | ↓ Degrading> (vs. prior period)
```

To calculate trend, compare current 7-day score against the prior 7-day window (days 8–14).

### Step 7: Agent & Team Stats

Use the Bash tool to query agent/team stats:
```bash
sqlite3 -header -column "$(cat ~/.claude/craftsman-metrics-db-path 2>/dev/null || echo ~/.claude/plugins/data/craftsman/metrics.db)" "SELECT date(timestamp) as day, agents_spawned, skills_used FROM sessions WHERE timestamp > datetime('now','-14 days') AND (COALESCE(agents_spawned,'[]') != '[]' OR COALESCE(skills_used,'[]') != '[]') ORDER BY day DESC;" || echo "No agent/team data yet."
```

Add to the report:

```
### Agent & Team Usage (14 days)
| Day | Agents Spawned | Skills Used |
|-----|----------------|-------------|
| ... | ...            | ...         |
```

If no agent/team data, display: "No agent or team sessions recorded in the last 14 days."

Do not silence this query's stderr. It used to select `agent_invocations` and
`team_type`, columns the sessions table never had, so it always failed and the
`||` arm reported an absence of activity instead of a broken query. An empty
result must mean empty data, never a schema error swallowed on the way out.

### Step 8: Hotspots (churn x complexity)

Surface where refactoring effort pays back most. This is command-time only (never in a hook):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/lib/hotspot_analysis.py" --since 12.month --top 15
```

Add to the report:

```
### Hotspots (refactor top-right first)
| File | Complexity | Churn | Quadrant | Risk |
|------|-----------|-------|----------|------|
| ...  | ...       | ...   | top-right | HIGH |
```

Prefer the team's existing tool report when one exists (`/craftsman:legacy audit --from <report>`); this built-in ranking is the zero-dependency fallback. See `knowledge/tooling-integration.md` and `knowledge/refactoring/refactoring-campaigns.md`.

### Step 9: Instinct Review (ADR-0020)

The correction learning loop promotes recurring corrections into learned skills, with you as the gate. List pending candidates:

```bash
bash ~/.claude/craftsman-instincts.sh candidates
```

For each candidate, show the user the rule, confidence, occurrence count, and evidence, then ask what to do:

- **Approve** (generates `.claude/skills/craftsman-learned/learned-<rule>/SKILL.md` with provenance, loaded automatically as background knowledge):
  ```bash
  bash ~/.claude/craftsman-instincts.sh approve <id> "$PWD/.claude/skills/craftsman-learned"
  ```
- **Reject** (not re-proposed unless significant new evidence accumulates):
  ```bash
  bash ~/.claude/craftsman-instincts.sh reject <id>
  ```

Also list what is already codified with `bash ~/.claude/craftsman-instincts.sh list approved` and offer retirement (delete the generated skill directory) for instincts the user no longer wants. Never approve or reject without an explicit user decision: automatic promotion is forbidden by ADR-0020.

### Step 10: Cross-Project Promotion (scoping)

An instinct approved in a single project stays project-scoped: it belongs to that codebase, and injecting it elsewhere is contamination. When the SAME rule has been approved in two or more independent projects, it stops being a codebase quirk and starts describing how you work. Only then is global promotion offered:

```bash
bash ~/.claude/craftsman-instincts.sh global-candidates
```

Present each candidate with its project count, then promote only on an explicit user decision:

```bash
bash ~/.claude/craftsman-instincts.sh promote <RULE> "$HOME/.claude/skills"
```

This writes `~/.claude/skills/learned-global-<rule>/SKILL.md` (`user-invocable: false`), applied across all projects. The same rule as project scope holds: never promote automatically, and retirement is deleting the file.

### Step 11: Dashboard (`--dashboard`)

When `$ARGUMENTS` contains `--dashboard`, skip the textual report and render the aggregated view instead:

```bash
bash ~/.claude/craftsman-dashboard.sh --serve
```

This aggregates every repository recorded in the metrics database into one self-contained HTML page served on `127.0.0.1:8787` (add a port number after `--serve` to change it): quality score, violations per repository, most-violated rules, corrections applied, learned instincts, and the 30-day trend. Nothing leaves the machine.

Without `--serve`, the page is written next to the database and its path is printed. `--json` emits the same aggregates as machine-readable data.

### Publication is explicit, never a side effect

Every metrics view stays on the machine by default (`127.0.0.1`, file next
to the database). Publishing a trend report as a shareable page is a
data-exposure decision: violation lists describe a private codebase. So a
published artifact happens only when the user asks for it in so many words
in the current session, and no metrics flow leaves the machine as a side
effect of any other step.
