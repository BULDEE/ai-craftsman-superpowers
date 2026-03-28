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
