#!/usr/bin/env bash
# =============================================================================
# Metrics Database Helper
# Shared by all hooks for recording violations and sessions.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/metrics-db.sh"
#   metrics_init
#   metrics_record_violation "PHP001" "src/Domain/**/*.php" "critical" 1 0
#   metrics_record_session 120 '["design","entity"]' '[]' 3 2
# =============================================================================

METRICS_DB_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
METRICS_DB="${METRICS_DB_DIR}/metrics.db"
METRICS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

metrics_init() {
    mkdir -p "$METRICS_DB_DIR"
    sqlite3 "$METRICS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS violations (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('critical', 'warning', 'info')),
    blocked BOOLEAN NOT NULL DEFAULT 0,
    ignored BOOLEAN NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    duration_seconds INTEGER,
    skills_used TEXT,
    agents_spawned TEXT,
    violations_blocked INTEGER DEFAULT 0,
    violations_warned INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_violations_project ON violations(project_hash, timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_hash, timestamp);

CREATE TABLE IF NOT EXISTS corrections (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('fixed', 'ignored', 'overridden')),
    context TEXT
);

CREATE INDEX IF NOT EXISTS idx_corrections_project ON corrections(project_hash, timestamp);
SQL

    # Migration v1.2.1: widen severity CHECK to include 'info'
    # SQLite CHECK constraints are immutable on existing tables.
    # If the old table exists without 'info', recreate it preserving data.
    local has_info
    has_info=$(sqlite3 "$METRICS_DB" "SELECT sql FROM sqlite_master WHERE name='violations';" 2>/dev/null)
    if [[ -n "$has_info" ]] && ! echo "$has_info" | grep -q "'info'"; then
        sqlite3 "$METRICS_DB" <<'MIGRATE'
ALTER TABLE violations RENAME TO violations_old;
CREATE TABLE violations (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('critical', 'warning', 'info')),
    blocked BOOLEAN NOT NULL DEFAULT 0,
    ignored BOOLEAN NOT NULL DEFAULT 0
);
INSERT INTO violations SELECT * FROM violations_old;
DROP TABLE violations_old;
CREATE INDEX IF NOT EXISTS idx_violations_project ON violations(project_hash, timestamp);
MIGRATE
    fi
}

metrics_project_hash() {
    echo -n "$PWD" | shasum -a 256 | cut -d' ' -f1
}

metrics_file_pattern() {
    local file="$1"
    local rel_path="${file#$PWD/}"
    echo "$rel_path" | sed -E 's/\/[^\/]+\.(php|ts|tsx)$/\/**\/*.\1/'
}

metrics_record_violation() {
    local rule="$1"
    local file_pattern="$2"
    local severity="$3"
    local blocked="${4:-0}"
    local ignored="${5:-0}"
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored) VALUES (?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$rule" "$file_pattern" "$severity" "$blocked" "$ignored"
}

metrics_record_session() {
    local duration="$1"
    local skills="$2"
    local agents="$3"
    local blocked="$4"
    local warned="$5"
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO sessions (project_hash, duration_seconds, skills_used, agents_spawned, violations_blocked, violations_warned) VALUES (?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$duration" "$skills" "$agents" "$blocked" "$warned"
}

metrics_violations_7d() {
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "SELECT rule, severity, COUNT(*) as count, SUM(blocked) as blocked, SUM(ignored) as ignored FROM violations WHERE project_hash=? AND timestamp > datetime('now','-7 days') GROUP BY rule, severity ORDER BY count DESC" \
        "$project_hash"
}

metrics_trend() {
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "SELECT date(timestamp) as day, COUNT(*) as violations, SUM(blocked) as blocked FROM violations WHERE project_hash=? AND timestamp > datetime('now','-30 days') GROUP BY day ORDER BY day DESC LIMIT 14" \
        "$project_hash"
}

metrics_record_correction() {
    local rule="$1"
    local file_pattern="$2"
    local action="$3"
    local context="${4:-}"
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO corrections (project_hash, rule, file_pattern, action, context) VALUES (?, ?, ?, ?, ?)" \
        "$project_hash" "$rule" "$file_pattern" "$action" "$context"
}

metrics_corrections_30d() {
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "SELECT rule, action, COUNT(*) as count FROM corrections WHERE project_hash=? AND timestamp > datetime('now','-30 days') GROUP BY rule, action ORDER BY count DESC" \
        "$project_hash"
}

# Correction learning summary for SessionStart injection
metrics_correction_trends() {
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
ph = sys.argv[2]
# Top fixed rules (7 days)
fixed = db.execute('''
    SELECT rule, COUNT(*) as c FROM corrections
    WHERE project_hash=? AND action='fixed' AND timestamp > datetime('now','-7 days')
    GROUP BY rule ORDER BY c DESC LIMIT 5
''', (ph,)).fetchall()
# Top still-violated rules (7 days)
violated = db.execute('''
    SELECT rule, COUNT(*) as c FROM violations
    WHERE project_hash=? AND blocked=1 AND timestamp > datetime('now','-7 days')
    GROUP BY rule ORDER BY c DESC LIMIT 5
''', (ph,)).fetchall()
parts = []
if fixed:
    parts.append('Recently fixed: ' + ', '.join(f'{r}({c}x)' for r,c in fixed))
if violated:
    parts.append('Recurring violations: ' + ', '.join(f'{r}({c}x)' for r,c in violated))
if parts:
    print(' | '.join(parts))
db.close()
" "$METRICS_DB" "$project_hash" 2>/dev/null || true
}
