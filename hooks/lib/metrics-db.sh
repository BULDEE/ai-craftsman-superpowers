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

# DDL and reads used to require the sqlite3 binary while DML went through
# python, so a host without the CLI (the Hermes image, before its Docker layer
# added one) got an empty file and "no such table" on every insert, swallowed.
# Both now fall back to the same parameterized helper the DML uses.
# CRAFTSMAN_NO_SQLITE_CLI=1 forces the fallback so a test can exercise it on a
# machine that has the binary.
_metrics_has_cli() {
    [[ -z "${CRAFTSMAN_NO_SQLITE_CLI:-}" ]] && command -v sqlite3 >/dev/null 2>&1
}

# stdin: SQL script (DDL and migrations, no bind parameters).
_metrics_sql() {
    if _metrics_has_cli; then
        sqlite3 "$METRICS_DB"
    else
        python3 "${METRICS_LIB_DIR}/metrics-query.py" --script "$METRICS_DB" "$(cat)"
    fi
}

# $1: one read statement. Prints rows the way the sqlite3 CLI does: columns
# joined with |, nothing at all on an empty result.
_metrics_sql_read() {
    if _metrics_has_cli; then
        sqlite3 "$METRICS_DB" "$1" 2>/dev/null
    else
        python3 "${METRICS_LIB_DIR}/metrics-query.py" --raw "$METRICS_DB" "$1" 2>/dev/null
    fi
}

_metrics_create_core_tables() {
    _metrics_sql <<'SQL'
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

# Every semantic verification, not only the ones that found something.
#
# The layer shelled out to a headless Haiku subprocess on every write and at
# every Stop, and recorded nothing at all: 19303 violations in five months and
# not one row from it. So "does Haiku catch what Level 1 misses" had no answer,
# and could not have one, in a plugin whose own doctrine is that a guardrail
# never seen red proves nothing.
#
# Findings go into `violations` with source='haiku', where they can be compared
# against Level 1 on the same file. This table holds the DENOMINATOR: a run
# that found nothing is the other half of any rate, and cost per finding cannot
# be computed from findings alone.
_metrics_create_haiku_runs_table() {
    _metrics_sql <<'SQL'
CREATE TABLE IF NOT EXISTS haiku_runs (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    hook TEXT NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN ('clean', 'findings', 'unavailable')),
    findings INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    file_pattern TEXT
);

CREATE INDEX IF NOT EXISTS idx_haiku_runs_project ON haiku_runs(project_hash, timestamp);
SQL
}

_metrics_create_corrections_table() {
    _metrics_sql <<'SQL'
CREATE TABLE IF NOT EXISTS corrections (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('fixed', 'ignored', 'overridden', 'scoped', 'open')),
    context TEXT
);

CREATE INDEX IF NOT EXISTS idx_corrections_project ON corrections(project_hash, timestamp);
SQL
}

# Two outcomes were unrecordable, and their absence is why the engine could not
# see its own failure. `scoped` is a rule relaxed for a path in .craft-rules.yml,
# which is the RIGHT answer for a rule wrong in context and was previously
# indistinguishable from giving up: 151 of PHP002's 153 suppressions came from
# entity directories one relaxation would have covered, and nothing could tell
# the difference. `open` is a verdict that reached the end of a session with no
# outcome at all, which is the actual shape of the problem: 12 rules fired 5624
# times in 30 days and produced no correction in either direction, so they read
# as healthy rules nobody had to fix.
# `source` arrives later, by ALTER, from _metrics_migrate_source_column.
# Rebuilding the table without asking would drop that column AND every value in
# it, and the later ALTER would silently re-add it empty. Rebuild what the table
# actually has, never what this file assumes it has.
_metrics_corrections_columns() {
    local column_list="id, timestamp, project_hash, rule, file_pattern, action, context"
    if _metrics_sql_read "PRAGMA table_info(corrections);" | grep -q '|source|'; then
        column_list="${column_list}, source"
    fi
    printf '%s' "$column_list"
}

# Named columns inside a transaction, mirroring the violations migration:
# SELECT * maps by position, so a drifted schema would shift every value one
# place instead of failing.
_metrics_corrections_rebuild_sql() {
    local column_list="$1" source_ddl="$2"
    cat <<MIGRATE
BEGIN IMMEDIATE;
ALTER TABLE corrections RENAME TO corrections_old;
CREATE TABLE corrections (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('fixed', 'ignored', 'overridden', 'scoped', 'open')),
    context TEXT${source_ddl}
);
INSERT INTO corrections (${column_list})
    SELECT ${column_list} FROM corrections_old;
DROP TABLE corrections_old;
CREATE INDEX IF NOT EXISTS idx_corrections_project ON corrections(project_hash, timestamp);
COMMIT;
MIGRATE
}

_metrics_migrate_correction_outcomes() {
    local existing_ddl column_list source_ddl=""
    existing_ddl=$(_metrics_sql_read "SELECT sql FROM sqlite_master WHERE name='corrections';")
    [[ -z "$existing_ddl" ]] && return 0
    echo "$existing_ddl" | grep -q "'scoped'" && return 0

    column_list=$(_metrics_corrections_columns)
    case "$column_list" in
        *source*) source_ddl=",
    source TEXT NOT NULL DEFAULT 'session'" ;;
    esac
    _metrics_sql <<< "$(_metrics_corrections_rebuild_sql "$column_list" "$source_ddl")"
}

_metrics_migrate_severity_info() {
    local has_info
    has_info=$(_metrics_sql_read "SELECT sql FROM sqlite_master WHERE name='violations';")
    if [[ -n "$has_info" ]] && ! echo "$has_info" | grep -q "'info'"; then
        # Wrapped in a transaction, and copying named columns rather than
        # SELECT *, which maps by position: a schema that had drifted by one
        # column would have silently shifted every value one place. A failure
        # midway used to leave violations empty and violations_old orphaned,
        # with no backup to restore from.
        _metrics_sql <<'MIGRATE'
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
    has_col=$(_metrics_sql_read "SELECT COUNT(*) FROM pragma_table_info('sessions') WHERE name='writes_count';")
    if [[ "$has_col" == "0" ]]; then
        _metrics_sql <<< "ALTER TABLE sessions ADD COLUMN writes_count INTEGER DEFAULT 0;" 2>/dev/null
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

    # Nothing to adopt is a settled answer, so it is recorded once.
    if [[ -f "$METRICS_DB" || ! -f "$legacy_db" ]]; then
        : > "$marker" 2>/dev/null || true
        return 0
    fi

    # A failed copy is not a settled answer. Writing the marker anyway meant a
    # full disk or a refused permission discarded the history for good, in
    # silence, and the adoption never retried.
    if cp "$legacy_db" "$METRICS_DB" 2>/dev/null; then
        : > "$marker" 2>/dev/null || true
        return 0
    fi
    echo "craftsman: could not adopt the previous metrics database, retrying next session" >&2
    return 0
}

# Where a row came from. Four months of test fixtures were indistinguishable
# from real violations once written, so a cleanup meant guessing at file
# patterns instead of filtering a column. Harnesses set CRAFTSMAN_METRICS_SOURCE
# so the next such incident is a DELETE rather than an archaeology exercise.
metrics_source() {
    printf '%s' "${CRAFTSMAN_METRICS_SOURCE:-session}"
}

# The exact file, beside the pattern, because they answer different questions.
#
# `file_pattern` is a DIRECTORY bucket: every .php under src/Domain/ maps to
# `src/Domain/**/*.php`, which is what a trend wants and is useless as a join
# key. "Did Level 1 see THIS file" was answered with it anyway, so a Haiku
# finding on Order.php counted as seen because Level 1 had fired on Customer.php
# next door, and the same query reported 100% novelty whenever the two layers
# spelled a path differently. Rows written before this column exists carry NULL,
# and every query that joins on it says so rather than treating NULL as a match.
_metrics_migrate_file_path_column() {
    local table
    for table in violations corrections; do
        if ! _metrics_sql_read "PRAGMA table_info(${table});" | grep -q '|file_path|'; then
            _metrics_sql <<< "ALTER TABLE ${table} ADD COLUMN file_path TEXT;" 2>/dev/null
        fi
    done
}

_metrics_migrate_source_column() {
    local table
    for table in violations corrections; do
        if ! _metrics_sql_read "PRAGMA table_info(${table});" | grep -q '|source|'; then
            _metrics_sql <<< "ALTER TABLE ${table} ADD COLUMN source TEXT NOT NULL DEFAULT 'session';" 2>/dev/null
        fi
    done
}

# Everything now routes through _metrics_sql, so a missing CLI degrades to
# the python fallback instead of an empty file and swallowed inserts.
metrics_init() {
    if ! _metrics_has_cli; then
        echo "craftsman: sqlite3 CLI not found, metrics use the python fallback" >&2
    fi
    mkdir -p "$METRICS_DB_DIR"
    _metrics_migrate_legacy_location
    _metrics_create_core_tables
    _metrics_create_corrections_table
    _metrics_create_haiku_runs_table
    _metrics_migrate_severity_info
    _metrics_migrate_writes_count
    _metrics_migrate_correction_outcomes
    _metrics_migrate_source_column
    _metrics_migrate_file_path_column
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
    local file="$1" project_root directory
    project_root=$(_metrics_project_root)
    # Both sides in the same form before comparing. `git rev-parse
    # --show-toplevel` answers with the PHYSICAL path, and a session started
    # through a symlinked directory (/tmp on macOS is /private/tmp, and a
    # worktree under a symlinked home is the everyday case) hands this function
    # the logical one: the prefix test then failed for files that are plainly
    # inside the project, and every one of them was filed under
    # <outside-project>, which is the column every trend groups by.
    if [[ "$file" == /* && "$file" != "$project_root"/* ]]; then
        directory="${file%/*}"
        if [[ -d "$directory" ]]; then
            directory=$(cd "$directory" 2>/dev/null && pwd -P) || directory=""
            [[ -n "$directory" ]] && file="${directory}/${file##*/}"
        fi
    fi
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

# The project-relative path of a file, or empty when it is not inside the
# project. Physical on both sides before comparing, for the same reason
# metrics_file_pattern resolves: `git rev-parse --show-toplevel` answers with
# the physical path, and a session started through a symlinked directory hands
# this the logical one.
metrics_relative_path() {
    local file="$1" project_root directory
    [[ -z "$file" ]] && return 0
    project_root=$(_metrics_project_root)
    if [[ "$file" != /* ]]; then
        file="$PWD/$file"
    fi
    directory="${file%/*}"
    if [[ -d "$directory" ]]; then
        directory=$(cd "$directory" 2>/dev/null && pwd -P) || directory=""
        [[ -n "$directory" ]] && file="${directory}/${file##*/}"
    fi
    # Containment, not a prefix strip: a verdict naming
    # `../../../../.ssh/config` must not write a path outside the project into
    # a database consolidate-metrics.sh shares between machines.
    [[ "$file" == "$project_root"/* ]] || return 0
    printf '%s' "${file#"$project_root"/}"
}

# One interpreter start per WRITE, not per finding.
#
# A front-end that reports several findings on one file opens a queue with
# `metrics_violations_queue_open` and closes it with
# `metrics_violations_queue_flush`; between the two, every row is appended to
# a file and inserted together in one python3 start. Measured on a write with
# five findings: five interpreter starts of ~40ms each, the largest single
# cost left on that path (tests/perf/test-hook-latency.sh, the "3 violations"
# row). A caller that never opened a queue inserts immediately, exactly as
# before, so a validator, a gate or a test that records one row keeps working
# with no flush to remember.
#
# Rows are delimited by the unit separator (0x1f) and newline, both of which a
# rule id, a severity and a project-relative path cannot carry: the rule id is
# validated, the hook refuses a path with a newline, and 0x1f is not a
# character anyone types into a file name. metrics-query.py --batch refuses a
# row with the wrong shape rather than guessing where a field ended.
_METRICS_VIOLATIONS_QUEUE=""
_METRICS_PROJECT_HASH=""

metrics_violations_queue_open() {
    _METRICS_VIOLATIONS_QUEUE="${METRICS_DB_DIR}/violations-queue.$$"
    : > "$_METRICS_VIOLATIONS_QUEUE" 2>/dev/null || _METRICS_VIOLATIONS_QUEUE=""
}

metrics_violations_queue_flush() {
    local queue="$_METRICS_VIOLATIONS_QUEUE"
    _METRICS_VIOLATIONS_QUEUE=""
    [[ -n "$queue" && -s "$queue" ]] || { rm -f "$queue" 2>/dev/null; return 0; }
    python3 "${METRICS_LIB_DIR}/metrics-query.py" --batch "$METRICS_DB" \
        "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored, source, file_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)" \
        < "$queue"
    rm -f "$queue" 2>/dev/null || true
}

metrics_record_violation() {
    local rule="$1"
    local file_pattern="$2"
    local severity="$3"
    local blocked="${4:-0}"
    local ignored="${5:-0}"
    local file="${6:-}"
    _metrics_rule_is_valid "$rule" || return 0
    # The hash is a property of the project, not of the finding: four forks
    # (root, tr, shasum, cut) once per hook rather than once per row.
    [[ -n "$_METRICS_PROJECT_HASH" ]] || _METRICS_PROJECT_HASH=$(metrics_project_hash)
    local relative
    relative=$(metrics_relative_path "$file")
    if [[ -n "$_METRICS_VIOLATIONS_QUEUE" ]]; then
        printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
            "$_METRICS_PROJECT_HASH" "$rule" "$file_pattern" "$severity" "$blocked" "$ignored" "$(metrics_source)" "$relative" \
            >> "$_METRICS_VIOLATIONS_QUEUE"
    else
        python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
            "INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored, source, file_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)" \
            "$_METRICS_PROJECT_HASH" "$rule" "$file_pattern" "$severity" "$blocked" "$ignored" "$(metrics_source)" "$relative"
    fi
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

# metrics_record_haiku_run <hook> <verdict> <findings> <duration_ms> [file]
metrics_record_haiku_run() {
    local hook="$1" verdict="$2" findings="${3:-0}" duration_ms="${4:-0}" file="${5:-}"
    case "$verdict" in
        clean|findings|unavailable) ;;
        *)
            # Loud, not silent. A verdict this function does not know is a
            # caller bug, and returning 0 with no row written is the exact
            # "recorded nothing while reporting success" shape this whole
            # feature exists to remove.
            echo "craftsman: metrics_record_haiku_run refused an unknown verdict '${verdict}'" >&2
            return 0
            ;;
    esac
    [[ "$findings" =~ ^[0-9]+$ ]] || findings=0
    [[ "$duration_ms" =~ ^[0-9]+$ ]] || duration_ms=0
    local project_hash pattern=""
    project_hash=$(metrics_project_hash)
    [[ -n "$file" ]] && pattern=$(metrics_file_pattern "$file")
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO haiku_runs (project_hash, hook, verdict, findings, duration_ms, file_pattern) VALUES (?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$hook" "$verdict" "$findings" "$duration_ms" "$pattern"
}

# The rules this layer last recorded for one file, from its most recent run.
#
# The layer has to close its own loop. The correction learning loop cannot do
# it: it keys on the DIRECTORY bucket and treats "absent from this write's
# findings" as fixed, so a HAIKU rule fed into it would be marked fixed by the
# next write to any file in the same directory, whether or not anything was
# fixed. A rate built that way would read 100% forever. The verifier runs again
# on the same file, so the honest comparison is against its own previous
# verdict.
metrics_haiku_previous_rules() {
    local file="$1"
    local project_hash relative
    project_hash=$(metrics_project_hash)
    relative=$(metrics_relative_path "$file")
    [[ -z "$relative" ]] && return 0
    python3 "${METRICS_LIB_DIR}/metrics-query.py" --raw "$METRICS_DB" \
        "SELECT DISTINCT rule FROM violations
         WHERE project_hash=? AND source='haiku' AND file_path=?
           AND timestamp=(SELECT MAX(timestamp) FROM violations
                          WHERE project_hash=? AND source='haiku' AND file_path=?)" \
        "$project_hash" "$relative" "$project_hash" "$relative" 2>/dev/null || true
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
    local file="${5:-}"
    local project_hash relative
    project_hash=$(metrics_project_hash)
    relative=$(metrics_relative_path "$file")
    python3 "${METRICS_LIB_DIR}/metrics-query.py" "$METRICS_DB" \
        "INSERT INTO corrections (project_hash, rule, file_pattern, action, context, source, file_path) VALUES (?, ?, ?, ?, ?, ?, ?)" \
        "$project_hash" "$rule" "$file_pattern" "$action" "$context" "$(metrics_source)" "$relative"
}

# The three numbers the semantic layer has to earn its place with.
#
# Written as one query script rather than as rows for a model to add up: this
# decides whether a paid layer stays on by default, and a decision that opens
# or closes a gate cannot depend on arithmetic done in prose.
#
#   1. share of Haiku findings with no Level 1 finding on the same file
#      pattern in the window. Only that share justifies a second layer.
#   2. the fixed rate of Haiku findings, comparable to Level 1's own.
#   3. Haiku seconds spent per accepted finding.
metrics_haiku_report() {
    local days="${1:-30}"
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/haiku_report.py" "$METRICS_DB" "$project_hash" "$days"
}

# Acceptance per rule, fixed / (fixed + ignored), and the share of violations
# with no recorded outcome (#44). A script, not rows for a model to add up:
# it proposes relaxing a gate.
metrics_acceptance_report() {
    local days="${1:-90}"
    shift 2>/dev/null || true
    local project_hash
    project_hash=$(metrics_project_hash)
    python3 "${METRICS_LIB_DIR}/acceptance_report.py" "$METRICS_DB" "$project_hash" "$days" "$@"
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

# Machine-wide variant of metrics_correction_trends: same shape, no project
# filter. The Hermes gateway process does not live in any workspace, so a
# project-scoped query from its cwd returns nothing; habits are per machine
# anyway (ADR-0029 inject).
metrics_correction_trends_global() {
    python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
fixed = db.execute('SELECT rule, COUNT(*) as c FROM corrections '
    \"WHERE action='fixed' AND timestamp > datetime('now','-7 days') \"
    'GROUP BY rule ORDER BY c DESC LIMIT 5').fetchall()
violated = db.execute('SELECT rule, COUNT(*) as c FROM violations '
    \"WHERE blocked=1 AND timestamp > datetime('now','-7 days') \"
    'GROUP BY rule ORDER BY c DESC LIMIT 5').fetchall()
parts = []
if fixed:
    parts.append('Recently fixed: ' + ', '.join(f'{r}({c}x)' for r, c in fixed))
if violated:
    parts.append('Recurring violations: ' + ', '.join(f'{r}({c}x)' for r, c in violated))
if parts:
    print(' | '.join(parts))
db.close()
" "$METRICS_DB" 2>/dev/null || true
}
