#!/usr/bin/env bash
# =============================================================================
# Merge metrics databases left behind by a plugin slug change.
#
# CLAUDE_PLUGIN_DATA carries the plugin slug, so an installation that predates
# the current slug (or ran once without the variable) accumulates one database
# per slug under ~/.claude/plugins/data/. metrics-db.sh only adopts the legacy
# file when the target does not exist yet, so once both are present the history
# stays split and every report reads a fraction of it.
#
# Rows are copied without their ids, letting the target reassign primary keys,
# and rows already present (same timestamp, project_hash and discriminant) are
# skipped, so re-running merges nothing twice.
#
# Usage:
#   scripts/consolidate-metrics.sh            # dry run, prints what would move
#   scripts/consolidate-metrics.sh --execute  # backs up the target, then merges
# =============================================================================
set -uo pipefail

DATA_ROOT="${HOME}/.claude/plugins/data"
EXECUTE=0
[[ "${1:-}" == "--execute" ]] && EXECUTE=1

# Candidates in order of authority. CLAUDE_PLUGIN_DATA wins when it points at a
# real database, but a test harness exporting it at a throwaway path must not
# make this script give up: fall through to the session bridge.
TARGET_DB=""
for candidate in \
    "${CLAUDE_PLUGIN_DATA:+${CLAUDE_PLUGIN_DATA}/metrics.db}" \
    "$([[ -f "${HOME}/.claude/craftsman-metrics-db-path" ]] && cat "${HOME}/.claude/craftsman-metrics-db-path")"
do
    [[ -n "$candidate" && -f "$candidate" ]] && { TARGET_DB="$candidate"; break; }
done

if [[ -z "$TARGET_DB" ]]; then
    echo "Cannot resolve the active database: set CLAUDE_PLUGIN_DATA or start a session first." >&2
    exit 1
fi

echo "Active database: $TARGET_DB"

# A source is any other metrics.db under the data root. Discovering them beats
# hardcoding known slugs: the next rename produces a directory nobody listed.
SOURCES=()
while IFS= read -r db; do
    [[ "$db" == "$TARGET_DB" ]] && continue
    SOURCES+=("$db")
done < <(find "$DATA_ROOT" -maxdepth 2 -name metrics.db 2>/dev/null | sort)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No other database found. Nothing to consolidate."
    exit 0
fi

# Escape a single quote for embedding into a single-quoted SQLite string
# literal, by doubling it. SOURCES comes from `find` under the user's own
# ~/.claude, not attacker-controlled input, but ATTACH takes a string literal
# rather than a bound parameter, so an unescaped quote in a path would still
# terminate the literal early and let the rest of the path run as SQL.
sql_quote() {
    local q="'"
    printf '%s' "${1//$q/$q$q}"
}

# Per table, the columns that identify a row well enough to detect a re-run.
# `id` is excluded everywhere: it is reassigned on insert.
merge_table() {
    local src_db="$1" table="$2" cols="$3" key="$4"
    local src_db_sql
    src_db_sql=$(sql_quote "$src_db")

    local pending
    pending=$(sqlite3 "$TARGET_DB" \
        "ATTACH '${src_db_sql}' AS src;
         SELECT COUNT(*) FROM src.${table} s
         WHERE NOT EXISTS (
             SELECT 1 FROM main.${table} m WHERE ${key}
         );" 2>/dev/null)

    [[ -z "$pending" ]] && pending=0
    echo "  ${table}: ${pending} row(s) to merge"

    [[ "$EXECUTE" -eq 0 || "$pending" -eq 0 ]] && return 0

    sqlite3 "$TARGET_DB" \
        "ATTACH '${src_db_sql}' AS src;
         INSERT INTO main.${table} (${cols})
         SELECT ${cols} FROM src.${table} s
         WHERE NOT EXISTS (
             SELECT 1 FROM main.${table} m WHERE ${key}
         );" 2>/dev/null
}

if [[ "$EXECUTE" -eq 1 ]]; then
    BACKUP="${TARGET_DB}.pre-consolidate.$(date +%Y%m%d%H%M%S)"
    cp "$TARGET_DB" "$BACKUP" || { echo "Backup failed, aborting." >&2; exit 1; }
    echo "Backup: $BACKUP"
else
    echo "[dry-run] no write, re-run with --execute"
fi

for src in "${SOURCES[@]}"; do
    echo ""
    echo "Source: $src"

    merge_table "$src" violations \
        "timestamp, project_hash, rule, file_pattern, severity, blocked, ignored" \
        "m.timestamp = s.timestamp AND m.project_hash = s.project_hash AND m.rule = s.rule AND m.file_pattern = s.file_pattern"

    merge_table "$src" corrections \
        "timestamp, project_hash, rule, file_pattern, action, context" \
        "m.timestamp = s.timestamp AND m.project_hash = s.project_hash AND m.rule = s.rule AND m.action = s.action"

    merge_table "$src" sessions \
        "timestamp, project_hash, duration_seconds, skills_used, agents_spawned, violations_blocked, violations_warned, writes_count" \
        "m.timestamp = s.timestamp AND m.project_hash = s.project_hash AND m.duration_seconds IS s.duration_seconds"
done

echo ""
if [[ "$EXECUTE" -eq 1 ]]; then
    echo "Consolidated. Totals now:"
    sqlite3 "$TARGET_DB" \
        "SELECT '  violations: ' || COUNT(*) FROM violations;
         SELECT '  corrections: ' || COUNT(*) FROM corrections;
         SELECT '  sessions: ' || COUNT(*) FROM sessions;"
    echo ""
    echo "Sources were left untouched. Remove them once the totals look right."
else
    echo "Dry run complete."
fi
