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

_metrics_create_core_tables() {
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
    violations_warned INTEGER DEFAULT 0,
    writes_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_violations_project ON violations(project_hash, timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_hash, timestamp);
SQL
}

_metrics_create_corrections_table() {
    sqlite3 "$METRICS_DB" <<'SQL'
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
}

_metrics_migrate_severity_info() {
    local has_info
    has_info=$(sqlite3 "$METRICS_DB" "SELECT sql FROM sqlite_master WHERE name='violations';" 2>/dev/null)
    if [[ -n "$has_info" ]] && ! echo "$has_info" | grep -q "'info'"; then
        # Wrapped in a transaction, and copying named columns rather than
        # SELECT *, which maps by position: a schema that had drifted by one
        # column would have silently shifted every value one place. A failure
        # midway used to leave violations empty and violations_old orphaned,
        # with no backup to restore from.
        sqlite3 "$METRICS_DB" <<'MIGRATE'
BEGIN IMMEDIATE;
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
INSERT INTO violations (id, timestamp, project_hash, rule, file_pattern, severity, blocked, ignored)
    SELECT id, timestamp, project_hash, rule, file_pattern, severity, blocked, ignored FROM violations_old;
DROP TABLE violations_old;
CREATE INDEX IF NOT EXISTS idx_violations_project ON violations(project_hash, timestamp);
COMMIT;
MIGRATE
    fi
}

# Add writes_count to sessions tables created before the column existed.
# ALTER TABLE ADD COLUMN is idempotent-guarded via pragma inspection.
_metrics_migrate_writes_count() {
    local has_col
    has_col=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM pragma_table_info('sessions') WHERE name='writes_count';" 2>/dev/null)
    if [[ "$has_col" == "0" ]]; then
        sqlite3 "$METRICS_DB" "ALTER TABLE sessions ADD COLUMN writes_count INTEGER DEFAULT 0;" 2>/dev/null
    fi
}

# v4: when CLAUDE_PLUGIN_DATA points somewhere new, adopt the legacy DB by
# copy (never delete the original) so history survives the move (ADR-0023).
#
# Adopted at most once, recorded by a marker. The legacy path is also the
# fallback this file uses whenever CLAUDE_PLUGIN_DATA is unset, so it collects
# whatever runs outside the marketplace environment. Without the marker, every
# such run recreated the legacy database and the next init pulled it back in,
# which is how test fixtures kept reappearing in the real one after a cleanup.
_metrics_migrate_legacy_location() {
    local legacy_db="${HOME}/.claude/plugins/data/craftsman/metrics.db"
    local marker="${METRICS_DB_DIR}/.legacy-adopted"
    [[ "$METRICS_DB" == "$legacy_db" ]] && return 0
    [[ -f "$marker" ]] && return 0
    if [[ ! -f "$METRICS_DB" && -f "$legacy_db" ]]; then
        cp "$legacy_db" "$METRICS_DB" 2>/dev/null || true
    fi
    : > "$marker" 2>/dev/null || true
}

# Where a row came from. Four months of test fixtures were indistinguishable
# from real violations once written, so a cleanup meant guessing at file
# patterns instead of filtering a column. Harnesses set CRAFTSMAN_METRICS_SOURCE
# so the next such incident is a DELETE rather than an archaeology exercise.
metrics_source() {
    printf '%s' "${CRAFTSMAN_METRICS_SOURCE:-session}"
}

_metrics_migrate_source_column() {
    local table
    for table in violations corrections; do
        if ! sqlite3 "$METRICS_DB" "PRAGMA table_info(${table});" 2>/dev/null | grep -q '|source|'; then
            sqlite3 "$METRICS_DB" \
                "ALTER TABLE ${table} ADD COLUMN source TEXT NOT NULL DEFAULT 'session';" 2>/dev/null
        fi
    done
}

# The DDL goes through the sqlite3 binary while the DML goes through python.
# Without sqlite3 no table was ever created, python then made an empty file,
# every INSERT raised "no such table", and each caller swallowed it: the
# healthcheck reported 0 rows, indistinguishable from a quiet week. The
# portability audit that added portable-timeout stopped at `timeout` and never
# asked which other binary the plugin assumes.
metrics_init() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "craftsman: sqlite3 not found, metrics are disabled for this session" >&2
        return 1
    fi
    mkdir -p "$METRICS_DB_DIR"
    _metrics_migrate_legacy_location
    _metrics_create_core_tables
    _metrics_create_corrections_table
    _metrics_migrate_severity_info
    _metrics_migrate_writes_count
    _metrics_migrate_source_column
}

# The identity of a project is its git toplevel, not the directory the session
# happened to start in. Hashing $PWD filed the same repository under a
# different project for every subdirectory worked from, quietly splitting one
# history into several and truncating every trend built on it.
_METRICS_PROJECT_ROOT=""
_METRICS_PROJECT_ROOT_FOR=""
_metrics_project_root() {
    # Keyed on $PWD rather than computed once: a hook is one process and would
    # not notice, but a long-lived shell that changes directory would keep
    # answering for the project it started in.
    if [[ "$_METRICS_PROJECT_ROOT_FOR" != "$PWD" ]]; then
        _METRICS_PROJECT_ROOT_FOR="$PWD"
        _METRICS_PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
    fi
    printf '%s' "$_METRICS_PROJECT_ROOT"
}

metrics_project_hash() {
    _metrics_project_root | tr -d '\n' | shasum -a 256 | cut -d' ' -f1
}

metrics_file_pattern() {
    local file="$1" project_root
    project_root=$(_metrics_project_root)
    # A prefix strip is not a containment check: an outside file silently kept
    # its absolute path, so the developer's home directory was recorded into a
    # database consolidate-metrics.sh is built to share. An outside file has no
    # project-relative meaning to record in the first place.
    if [[ "$file" != "$project_root"/* ]]; then
        printf '%s\n' "<outside-project>"
        return 0
    fi
    # Any extension, not just php|ts|tsx: the narrow list left every .py and
    # .sh violation carrying a full path through the branch above.
    echo "${file#"$project_root"/}" | sed -E 's/\/[^\/]+\.([A-Za-z0-9]+)$/\/**\/*.\1/'
}

# A rule id is an identifier. 21 rows hold source fragments such as
# "// Start...')" because the id was taken from whatever the caller passed,
# and a validator that mis-parses a line then writes that line into the
# column every trend groups by.
_metrics_rule_is_valid() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]{1,39}$ ]]
}

metrics_record_violation() {
    local rule="$1"
    local file_pattern="$2"
    local severity="$3"
    local blocked="${4:-0}"
    local ignored="${5:-0}"
    _metrics_rule_is_valid "$rule" || return 0
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored, source) VALUES (?, ?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$rule" "$file_pattern" "$severity" "$blocked" "$ignored" "$(metrics_source)"
    _metrics_tally_session "$blocked" "$ignored"
}

# One line per finding for THIS session, read at SessionEnd. It used to derive
# its counters by re-querying this table over a window of the session's own
# duration, which counts every other session's rows on the same project: 236
# sessions in one day reported 16236 warnings against 1353 actually recorded.
# It lives here rather than in the caller because the pack validators record
# straight through this function and would otherwise go uncounted.
_metrics_tally_session() {
    local blocked="$1" ignored="$2" kind="warned"
    [[ "$blocked" == "1" ]] && kind="blocked"
    [[ "$ignored" == "1" ]] && kind="ignored"
    echo "$kind" >> "${METRICS_DB_DIR}/session-violations" 2>/dev/null || true
}

metrics_record_session() {
    local duration="$1"
    local skills="$2"
    local agents="$3"
    local blocked="$4"
    local warned="$5"
    local writes="${6:-0}"
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO sessions (project_hash, duration_seconds, skills_used, agents_spawned, violations_blocked, violations_warned, writes_count) VALUES (?, ?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$duration" "$skills" "$agents" "$blocked" "$warned" "$writes"
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
        "INSERT INTO corrections (project_hash, rule, file_pattern, action, context, source) VALUES (?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$rule" "$file_pattern" "$action" "$context" "$(metrics_source)"
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
