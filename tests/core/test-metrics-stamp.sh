#!/usr/bin/env bash
# =============================================================================
# CR-278: a write pays one schema read, not the migrations.
#
# post-write-check.sh ran metrics_init on every Write: 14 sqlite3 probes
# (PRAGMA table_info, sqlite_master) to rediscover a schema SessionStart had
# already migrated. PRAGMA user_version now holds a stamp of metrics-db.sh;
# a matching stamp costs one read, a missing database, an older stamp or an
# edited library runs the migrations once. The witness is a sqlite3 on PATH
# that records its arguments: an exit 0 proves nothing about what ran.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-metrics-stamp.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/data" "$WORK/home" "$WORK/proj/src"
REAL_SQLITE=$(command -v sqlite3)
cat > "$WORK/bin/sqlite3" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\${*:2}" >> "$WORK/sqlite-calls.log"
exec "$REAL_SQLITE" "\$@"
SHIM
chmod +x "$WORK/bin/sqlite3"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR" CLAUDE_PLUGIN_DATA="$WORK/data" HOME="$WORK/home"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CRAFTSMAN_NO_SQLITE_CLI

_lib() { PATH="$WORK/bin:$PATH" bash -c "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; $1" 2>/dev/null; }
_probes() { grep -cE 'PRAGMA table_info|sqlite_master|pragma_table_info' "$WORK/sqlite-calls.log" 2>/dev/null || true; }

_lib metrics_init
DB=$(_lib 'printf %s "$METRICS_DB"')
STAMP=$(_lib '_metrics_schema_stamp')
STORED=$("$REAL_SQLITE" "$DB" "PRAGMA user_version;" 2>/dev/null)
if [[ -n "$STAMP" && "$STAMP" != 0 && "$STORED" == "$STAMP" ]]; then
    log_pass "metrics_init stamps the schema it migrated ($STAMP)"
else
    log_fail "schema stamp" "stamp=${STAMP:-none} stored=${STORED:-none}"
fi

rm -f "$WORK/sqlite-calls.log"
_lib metrics_init_once
CALLS=$(grep -c . "$WORK/sqlite-calls.log" 2>/dev/null || echo 0)
if [[ "$CALLS" -eq 1 && "$(_probes)" -eq 0 ]]; then
    log_pass "a current stamp costs one read and no schema probe"
else
    log_fail "stamped schema still probed" "calls=$CALLS probes=$(_probes): $(tr '\n' ';' < "$WORK/sqlite-calls.log" | cut -c1-200)"
fi

"$REAL_SQLITE" "$DB" "PRAGMA user_version = 7;" >/dev/null
rm -f "$WORK/sqlite-calls.log"
_lib metrics_init_once
if [[ "$(_probes)" -gt 0 && "$("$REAL_SQLITE" "$DB" "PRAGMA user_version;")" == "$STAMP" ]]; then
    log_pass "an older stamp runs the migrations once and restamps"
else
    log_fail "older stamp" "probes=$(_probes) stored=$("$REAL_SQLITE" "$DB" "PRAGMA user_version;")"
fi

rm -f "$DB"
_lib metrics_init_once
if [[ -n "$("$REAL_SQLITE" "$DB" "SELECT name FROM sqlite_master WHERE name='violations';" 2>/dev/null)" ]]; then
    log_pass "a database removed mid-session is recreated on the next write"
else
    log_fail "removed database" "no violations table"
fi

# The consumer: a real post-write on a stamped schema probes nothing.
printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > "$WORK/proj/src/run.sh"
( cd "$WORK/proj" && git init -q )
rm -f "$WORK/sqlite-calls.log"
printf '{"session_id":"s278","hook_event_name":"PostToolUse","tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' \
    "$WORK/proj" "$WORK/proj/src/run.sh" | ( cd "$WORK/proj" && PATH="$WORK/bin:$PATH" bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1 )
if [[ -s "$WORK/sqlite-calls.log" && "$(_probes)" -eq 0 ]]; then
    log_pass "post-write on a stamped schema runs no schema probe ($(grep -c . "$WORK/sqlite-calls.log") sqlite3 call(s))"
else
    log_fail "post-write probes the schema" "probes=$(_probes) calls=$(grep -c . "$WORK/sqlite-calls.log" 2>/dev/null || echo 0)"
fi

test_summary
