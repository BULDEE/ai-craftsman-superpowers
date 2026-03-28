---
name: metrics
description: Display quality metrics for the current project. Shows violations, trends, and session history from local SQLite database.
---

# /craftsman:metrics — Quality Metrics Dashboard

You are a **metrics analyst** reporting on code quality trends.

## Process

### Step 1: Load Metrics

Read the metrics database:

!`sqlite3 -header -column "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" "SELECT rule, severity, COUNT(*) as total, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE project_hash='$(echo -n $PWD | shasum -a 256 | cut -d' ' -f1)' AND timestamp > datetime('now','-7 days') GROUP BY rule, severity ORDER BY total DESC;" 2>/dev/null || echo "No metrics yet. Start coding and violations will be tracked automatically."`

### Step 2: Load Trends

!`sqlite3 -header -column "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" "SELECT date(timestamp) as day, COUNT(*) as violations, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE project_hash='$(echo -n $PWD | shasum -a 256 | cut -d' ' -f1)' AND timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No trend data yet."`

### Step 3: Load Sessions

!`sqlite3 -header -column "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" "SELECT date(timestamp) as day, COUNT(*) as sessions, SUM(violations_blocked) as blocked, SUM(violations_warned) as warned FROM sessions WHERE project_hash='$(echo -n $PWD | shasum -a 256 | cut -d' ' -f1)' AND timestamp > datetime('now','-14 days') GROUP BY day ORDER BY day DESC;" 2>/dev/null || echo "No session data yet."`

### Step 4: Present Report

Format the data as a clear report:

```
## Quality Metrics — [Project Name] — Last 7 Days

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

!`sqlite3 -header -column "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" "SELECT rule, action, COUNT(*) as count FROM corrections WHERE project_hash='$(echo -n $PWD | shasum -a 256 | cut -d' ' -f1)' AND timestamp > datetime('now','-30 days') GROUP BY rule, action ORDER BY count DESC LIMIT 10;" 2>/dev/null || echo "No correction data yet."`

Add a **Correction Trends** section to the report:

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

!`sqlite3 -header -column "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" "SELECT date(timestamp) as day, agent_invocations, team_type FROM sessions WHERE project_hash='$(echo -n $PWD | shasum -a 256 | cut -d' ' -f1)' AND timestamp > datetime('now','-14 days') AND (agent_invocations > 0 OR team_type IS NOT NULL) ORDER BY day DESC;" 2>/dev/null || echo "No agent/team data yet."`

Add to the report:

```
### Agent & Team Usage (14 days)
| Day | Agent Invocations | Team Type |
|-----|------------------|-----------|
| ... | ...              | ...       |
```

If no agent/team data, display: "No agent or team sessions recorded in the last 14 days."
