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
DB=~/.claude/plugins/data/craftsman/metrics.db; echo "=== VIOLATIONS ===" && sqlite3 -header -column "$DB" "SELECT rule, severity, COUNT(*) as total, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE timestamp > datetime('now','-7 days') GROUP BY rule, severity ORDER BY total DESC;" 2>/dev/null || echo "No metrics yet."; echo "=== TREND ===" && sqlite3 -header -column "$DB" "SELECT date(timestamp) as day, COUNT(*) as violations, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No trend data yet."; echo "=== SESSIONS ===" && sqlite3 -header -column "$DB" "SELECT date(timestamp) as day, COUNT(*) as sessions, SUM(violations_blocked) as blocked, SUM(violations_warned) as warned FROM sessions WHERE timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No session data yet."; echo "=== CORRECTIONS ===" && sqlite3 -header -column "$DB" "SELECT rule, action, COUNT(*) as count FROM corrections WHERE timestamp > datetime('now','-30 days') GROUP BY rule, action ORDER BY count DESC LIMIT 10;" 2>/dev/null || echo "No correction data yet."
```

### Step 5: Present Report

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
sqlite3 -header -column ~/.claude/plugins/data/craftsman/metrics.db "SELECT date(timestamp) as day, agent_invocations, team_type FROM sessions WHERE timestamp > datetime('now','-14 days') AND (agent_invocations > 0 OR team_type IS NOT NULL) ORDER BY day DESC;" 2>/dev/null || echo "No agent/team data yet."
```

Add to the report:

```
### Agent & Team Usage (14 days)
| Day | Agent Invocations | Team Type |
|-----|------------------|-----------|
| ... | ...              | ...       |
```

If no agent/team data, display: "No agent or team sessions recorded in the last 14 days."

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
