#!/usr/bin/env bash
# =============================================================================
# Metrics consolidation must never report a clean run over a dropped source.
#
# The script used to discard sqlite's stderr on both statements, so a locked or
# drifted source database read as "0 rows to merge" and the run exited 0 having
# merged nothing. The failure count that fixes that was first held in a shell
# variable, which is silently lost whenever the function that increments it
# runs in a subshell. Both properties are asserted here.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

CONSOLIDATE="$ROOT_DIR/scripts/consolidate-metrics.sh"

SCHEMA="CREATE TABLE violations (id INTEGER PRIMARY KEY, timestamp TEXT, project_hash TEXT,
  rule TEXT, file_pattern TEXT, severity TEXT, blocked INT, ignored INT);
CREATE TABLE corrections (id INTEGER PRIMARY KEY, timestamp TEXT, project_hash TEXT,
  rule TEXT, file_pattern TEXT, action TEXT, context TEXT);
CREATE TABLE sessions (id INTEGER PRIMARY KEY, timestamp TEXT, project_hash TEXT,
  duration_seconds INT, skills_used TEXT, agents_spawned TEXT,
  violations_blocked INT, violations_warned INT, writes_count INT);"

new_home() {
    local home
    home=$(mktemp -d)
    mkdir -p "$home/.claude/plugins/data/target"
    sqlite3 "$home/.claude/plugins/data/target/metrics.db" "$SCHEMA"
    printf '%s' "$home"
}

add_source() {
    local home="$1" name="$2"
    mkdir -p "$home/.claude/plugins/data/$name"
    sqlite3 "$home/.claude/plugins/data/$name/metrics.db" "$SCHEMA
INSERT INTO violations (timestamp, project_hash, rule, file_pattern, severity, blocked, ignored)
VALUES ('t-$name', 'h', 'PHP001', 'src/**', 'critical', 1, 0);"
}

run_consolidate() {
    local home="$1"
    HOME="$home" CLAUDE_PLUGIN_DATA="$home/.claude/plugins/data/target" \
        bash "$CONSOLIDATE" --execute
}

echo ""
echo "=== A healthy source is merged and the run succeeds ==="

HOME_OK=$(new_home)
add_source "$HOME_OK" "src1"
OUT_OK=$(run_consolidate "$HOME_OK" 2>&1)
CODE_OK=$?

if [[ $CODE_OK -eq 0 ]]; then
    log_pass "exits 0 when every source merges"
else
    log_fail "healthy consolidation failed" "exit $CODE_OK: $OUT_OK"
fi

MERGED=$(sqlite3 "$HOME_OK/.claude/plugins/data/target/metrics.db" \
    "SELECT COUNT(*) FROM violations;" 2>/dev/null)
if [[ "$MERGED" == "1" ]]; then
    log_pass "the source row actually landed in the target"
else
    log_fail "nothing merged" "target holds '$MERGED' rows, expected 1"
fi
rm -rf "$HOME_OK"

echo ""
echo "=== An unreadable source fails loudly instead of reading as empty ==="

HOME_BAD=$(new_home)
add_source "$HOME_BAD" "src1"
mkdir -p "$HOME_BAD/.claude/plugins/data/src2"
printf 'this is not a database' > "$HOME_BAD/.claude/plugins/data/src2/metrics.db"

OUT_BAD=$(run_consolidate "$HOME_BAD" 2>&1)
CODE_BAD=$?

if [[ $CODE_BAD -ne 0 ]]; then
    log_pass "exits non-zero when a source cannot be read"
else
    log_fail "silent data loss" "reported success over an unreadable source"
fi

if printf '%s' "$OUT_BAD" | grep -q "NOT MERGED"; then
    log_pass "names the tables it did not merge"
else
    log_fail "no diagnostic" "$OUT_BAD"
fi

if printf '%s' "$OUT_BAD" | grep -q "INCOMPLETE"; then
    log_pass "says the consolidation is incomplete"
else
    log_fail "no summary" "$OUT_BAD"
fi

if printf '%s' "$OUT_BAD" | grep -q "Do not delete any source"; then
    log_pass "tells the operator not to delete the sources"
else
    log_fail "no guard rail" "$OUT_BAD"
fi

# The counter-test for the diagnostic: the healthy source in the same run must
# still have been merged, or "it failed" is satisfied by a script that gave up.
MERGED_BAD=$(sqlite3 "$HOME_BAD/.claude/plugins/data/target/metrics.db" \
    "SELECT COUNT(*) FROM violations;" 2>/dev/null)
if [[ "$MERGED_BAD" == "1" ]]; then
    log_pass "the readable source in the same run was still merged"
else
    log_fail "gave up too early" "target holds '$MERGED_BAD' rows, expected 1"
fi
rm -rf "$HOME_BAD"

echo ""
echo "=== The failure count survives a subshell ==="

# This is the property, not the implementation: whoever restructures
# merge_table later may well put it behind $( ), a pipeline, or a
# `while read` loop. A counter kept in a shell variable would be lost there
# and the script would exit 0 over a dropped source, which is exactly the bug
# the count exists to prevent.
SUBSHELL_PROBE=$(mktemp)
cat > "$SUBSHELL_PROBE" <<'PROBE'
set -uo pipefail
MERGE_ERROR_LOG=$(mktemp)
merge_error_count() {
    [[ -s "$MERGE_ERROR_LOG" ]] || { printf '0'; return 0; }
    wc -l < "$MERGE_ERROR_LOG" | tr -d ' '
}
merge_failed() {
    printf '%s\t%s\n' "$1" "$2" >> "$MERGE_ERROR_LOG"
}

# Three shapes that all lose a shell variable's increment.
result=$(merge_failed violations "in a command substitution")
merge_failed corrections "in a pipeline" | cat
printf 'sessions\n' | while read -r t; do merge_failed "$t" "in a while-read loop"; done

merge_error_count
rm -f "$MERGE_ERROR_LOG"
PROBE

COUNT=$(bash "$SUBSHELL_PROBE" 2>/dev/null)
rm -f "$SUBSHELL_PROBE"

if [[ "$COUNT" == "3" ]]; then
    log_pass "three failures recorded from three subshell shapes"
else
    log_fail "count lost in a subshell" "expected 3, got '$COUNT'"
fi

# And the script under test must be using that shape, not a bare variable.
if grep -q "MERGE_ERROR_LOG" "$CONSOLIDATE" \
   && ! grep -qE 'MERGE_ERRORS=\$\(\(' "$CONSOLIDATE"; then
    log_pass "consolidate-metrics.sh records failures to a file, not a counter variable"
else
    log_fail "fragile counter" \
        "the script increments a shell variable, which a subshell would discard"
fi

test_summary
