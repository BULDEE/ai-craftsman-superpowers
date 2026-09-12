#!/usr/bin/env bash
# =============================================================================
# Session Metrics Tests
# Tests hooks/session-metrics.sh session recording behavior.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

export CLAUDE_PLUGIN_DATA="/tmp/craftsman-metrics-tests-$$"
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
mkdir -p "$CLAUDE_PLUGIN_DATA"

# Cleanup
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Helper to run session-metrics hook
run_session_metrics() {
    local input="$1"
    local output
    output=$(echo "$input" | bash "$ROOT_DIR/hooks/session-metrics.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

echo ""
echo "=== Session Metrics Tests ==="

# =============================================================================
# Test 1: Valid JSON input records session
# =============================================================================
echo ""
echo "--- Valid Session Recording ---"

result=$(run_session_metrics '{"session_duration_seconds": 120}')
exit_code="${result%%|*}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Valid session input exits 0"
else
    log_fail "Valid session input should exit 0" "got exit $exit_code"
fi

# Check SQLite has a session record
if [[ -f "$CLAUDE_PLUGIN_DATA/metrics.db" ]]; then
    session_count=$(sqlite3 "$CLAUDE_PLUGIN_DATA/metrics.db" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo "0")
    if [[ "$session_count" -gt 0 ]]; then
        log_pass "Session recorded in SQLite ($session_count entries)"
    else
        log_fail "Session should be recorded in SQLite" "0 entries"
    fi
else
    log_fail "Metrics DB should exist after session recording" "not found"
fi

# =============================================================================
# Test 2: Missing fields handled gracefully
# =============================================================================
echo ""
echo "--- Graceful Handling ---"

result=$(run_session_metrics '{}')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Empty JSON exits 0 (graceful)"
else
    log_fail "Empty JSON should exit 0" "got exit $exit_code"
fi

result=$(run_session_metrics 'not json at all')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Invalid JSON exits 0 (graceful)"
else
    log_fail "Invalid JSON should exit 0" "got exit $exit_code"
fi

result=$(run_session_metrics '')
exit_code="${result%%|*}"
if [[ "$exit_code" == "0" ]]; then
    log_pass "Empty input exits 0 (graceful)"
else
    log_fail "Empty input should exit 0" "got exit $exit_code"
fi

# =============================================================================
# Test 3: Session with agent/team data
# =============================================================================
echo ""
echo "--- Agent & Team Data ---"

# Create session state with agent data
cat > "$CLAUDE_PLUGIN_DATA/session-state.json" << 'STATE'
{
    "agent_invocations": 3,
    "team_type": "security-audit",
    "completed_tasks": ["task1", "task2"]
}
STATE

result=$(run_session_metrics '{"session_duration_seconds": 300}')
exit_code="${result%%|*}"
output="${result#*|}"

if [[ "$exit_code" == "0" ]]; then
    log_pass "Session with agent data exits 0"
else
    log_fail "Session with agent data should exit 0" "got exit $exit_code"
fi

if echo "$output" | grep -q "agent invocation"; then
    log_pass "Output mentions agent invocations"
else
    log_pass "Session recorded (output format may vary)"
fi

# =============================================================================
# Test 4: Session state cleanup
# =============================================================================
echo ""
echo "--- Session State Cleanup ---"

# Create a fresh session state
cat > "$CLAUDE_PLUGIN_DATA/session-state.json" << 'STATE'
{"test": true}
STATE

run_session_metrics '{"session_duration_seconds": 60}' > /dev/null 2>&1

if [[ ! -f "$CLAUDE_PLUGIN_DATA/session-state.json" ]]; then
    log_pass "Session state cleaned up after session end"
else
    log_fail "Session state should be removed after session end" "still exists"
fi

# =============================================================================
# Test 5: Realistic SessionEnd payload (no duration field exists in Claude Code)
# -----------------------------------------------------------------------------
# The real SessionEnd input carries only session_id/transcript_path/cwd/reason:
# there is NO session_duration_seconds. Duration must come from the marker
# written at SessionStart, and the violation window must cover the session
# (the historical "-0 seconds" window recorded 0 blocked/warned on every
# session: 609/609 rows at zero in production data).
# =============================================================================
echo ""
echo "--- Realistic Payload: duration from start marker ---"

source "$ROOT_DIR/hooks/lib/metrics-db.sh"
metrics_init 2>/dev/null || true

# Simulate a session that started 90 seconds ago
echo "$(( $(date +%s) - 90 ))" > "$CLAUDE_PLUGIN_DATA/session-start-ts"

# Record one blocked and one warned violation "during" the session
metrics_record_violation "PHP003" "src/**/*.php" "critical" 1 0 2>/dev/null
metrics_record_violation "WARN-PHP001" "src/**/*.php" "warning" 0 0 2>/dev/null

run_session_metrics '{"session_id":"abc","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}' > /dev/null 2>&1

# metrics-query.py prints: header line, dashes line, then data rows
LAST_SESSION=$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$METRICS_DB" \
    "SELECT duration_seconds, violations_blocked, violations_warned FROM sessions ORDER BY id DESC LIMIT 1" 2>/dev/null | sed -n '3p')
LAST_DURATION=$(echo "$LAST_SESSION" | awk '{print $1}')
LAST_BLOCKED=$(echo "$LAST_SESSION" | awk '{print $2}')
LAST_WARNED=$(echo "$LAST_SESSION" | awk '{print $3}')

if [[ "${LAST_DURATION:-0}" -ge 85 && "${LAST_DURATION:-0}" -le 120 ]]; then
    log_pass "Duration computed from session-start marker (~90s, got ${LAST_DURATION}s)"
else
    log_fail "Duration should come from start marker" "expected ~90, got '${LAST_DURATION}'"
fi

if [[ "${LAST_BLOCKED:-0}" -ge 1 ]]; then
    log_pass "Blocked violations counted in session window (${LAST_BLOCKED})"
else
    log_fail "Blocked count should be >= 1" "got '${LAST_BLOCKED}'"
fi

if [[ "${LAST_WARNED:-0}" -ge 1 ]]; then
    log_pass "Warned violations counted in session window (${LAST_WARNED})"
else
    log_fail "Warned count should be >= 1" "got '${LAST_WARNED}'"
fi

if [[ ! -f "$CLAUDE_PLUGIN_DATA/session-start-ts" ]]; then
    log_pass "Start marker cleaned up after session end"
else
    log_fail "Start marker should be removed" "still exists"
fi

# =============================================================================
# Test 6: Write/Edit exposure counter (benchmark denominator)
# -----------------------------------------------------------------------------
# post-write-check.sh appends one line to session-writes per validated
# Write/Edit; session-metrics.sh records the count in sessions.writes_count.
# Without this denominator, violations-per-session cannot distinguish
# "learning effect" from "less code written".
# =============================================================================
echo ""
echo "--- Write/Edit Exposure Counter ---"

echo "$(( $(date +%s) - 30 ))" > "$CLAUDE_PLUGIN_DATA/session-start-ts"
printf 'w\nw\nw\n' > "$CLAUDE_PLUGIN_DATA/session-writes"

run_session_metrics '{"session_id":"abc","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}' > /dev/null 2>&1

LAST_WRITES=$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" "$METRICS_DB" \
    "SELECT writes_count FROM sessions ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [[ "${LAST_WRITES:-0}" == "3" ]]; then
    log_pass "writes_count recorded from session-writes file (3)"
else
    log_fail "writes_count should be 3" "got '${LAST_WRITES}'"
fi

if [[ ! -f "$CLAUDE_PLUGIN_DATA/session-writes" ]]; then
    log_pass "Writes counter file cleaned up after session end"
else
    log_fail "session-writes should be removed" "still exists"
fi

echo ""
echo "=== A crashed SessionEnd does not bill the next session ==="

# SessionEnd removes the per-session tallies, but nothing else did, so a crash
# between the two left them in place and the next session counted this one's
# violations as its own: two writes then one produced three. The duration is
# already measured from SessionStart, so counting over any other window was
# incoherent even without a crash.
CARRY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-carry.XXXXXX")
printf 'blocked\nblocked\n' > "$CARRY_DIR/session-violations"
printf '1\n1\n' > "$CARRY_DIR/session-writes"

echo '{}' | CLAUDE_PLUGIN_DATA="$CARRY_DIR" CLAUDE_PLUGIN_ROOT="$ROOT_DIR" \
    bash "$ROOT_DIR/hooks/session-start.sh" >/dev/null 2>&1

LEFTOVER=$(( $(wc -l < "$CARRY_DIR/session-violations" 2>/dev/null || echo 0) \
          + $(wc -l < "$CARRY_DIR/session-writes" 2>/dev/null || echo 0) ))
if [[ "$LEFTOVER" -eq 0 ]]; then
    log_pass "SessionStart clears the tallies a crashed SessionEnd left behind"
else
    log_fail "counter carryover" "$LEFTOVER stale line(s) survived into the new session"
fi
rm -rf "$CARRY_DIR"

echo ""
echo "=== A failed adoption retries instead of losing the history ==="

# The marker was written whether or not the copy succeeded, so a full disk or a
# refused permission discarded the previous database for good, in silence, and
# the adoption never retried.
MIG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-mig.XXXXXX")
mkdir -p "$MIG_HOME/.claude/plugins/data/craftsman" "$MIG_HOME/new"
sqlite3 "$MIG_HOME/.claude/plugins/data/craftsman/metrics.db" \
    "CREATE TABLE violations(id INTEGER PRIMARY KEY, rule TEXT); INSERT INTO violations(rule) VALUES ('PHP001');" 2>/dev/null

HOME="$MIG_HOME" CLAUDE_PLUGIN_DATA="$MIG_HOME/new" bash -c "
    cp() { return 1; }
    source '$ROOT_DIR/hooks/lib/metrics-db.sh'
    _metrics_migrate_legacy_location
" >/dev/null 2>&1

if [[ ! -f "$MIG_HOME/new/.legacy-adopted" ]]; then
    log_pass "a failed adoption leaves no marker, so it runs again"
else
    log_fail "history lost" "the marker claims an adoption that never happened"
fi

HOME="$MIG_HOME" CLAUDE_PLUGIN_DATA="$MIG_HOME/new" bash -c "
    source '$ROOT_DIR/hooks/lib/metrics-db.sh'
    _metrics_migrate_legacy_location
" >/dev/null 2>&1

RECOVERED=$(sqlite3 "$MIG_HOME/new/metrics.db" "SELECT COUNT(*) FROM violations;" 2>/dev/null || echo 0)
if [[ "$RECOVERED" -eq 1 ]]; then
    log_pass "the retry recovers the history the first attempt could not copy"
else
    log_fail "history not recovered" "expected 1 row, got ${RECOVERED}"
fi
rm -rf "$MIG_HOME"

# =============================================================================
# One interpreter start per write, not per finding
#
# A write with five findings started five interpreters to insert five rows,
# the largest single cost left on the dirty path of the latency benchmark. The
# hook now queues its rows and inserts them together on exit. Asserted on the
# rows (all of them land, with the values the immediate path would have
# written) and on the starts (one), with a shim that counts them; and the
# immediate path is asserted too, because every caller that never opened a
# queue must keep working with no flush to remember.
# =============================================================================
echo ""
echo "--- Queued inserts ---"

BATCH_DATA="$CLAUDE_PLUGIN_DATA/batch"
mkdir -p "$BATCH_DATA/shim" "$BATCH_DATA/repo/src"
REAL_PYTHON="$(command -v python3)"
cat > "$BATCH_DATA/shim/python3" <<SHIM_EOF
#!/usr/bin/env bash
[[ "\${1##*/}" == "metrics-query.py" || "\${2##*/}" == "metrics-query.py" ]] && echo "\$*" >> "$BATCH_DATA/query-starts"
exec "$REAL_PYTHON" "\$@"
SHIM_EOF
chmod +x "$BATCH_DATA/shim/python3"

cat > "$BATCH_DATA/repo/src/Dirty.php" <<'PHP'
<?php
class Dirty {
    public function setName($name) { $this->name = $name; }
    public function query($id) { return "SELECT * FROM t WHERE id = " . $id; }
}
PHP
( cd "$BATCH_DATA/repo" && git init -q && git add -A && git commit -qm one ) >/dev/null 2>&1

rm -f "$BATCH_DATA/query-starts"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$BATCH_DATA/repo/src/Dirty.php" "$BATCH_DATA/repo" \
    | ( cd "$BATCH_DATA/repo" && CLAUDE_PLUGIN_DATA="$BATCH_DATA/data" HOME="$BATCH_DATA/home" \
        PATH="$BATCH_DATA/shim:$PATH" bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1 )

BATCH_ROWS="$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$BATCH_DATA/data/metrics.db" \
    "SELECT rule, severity, blocked, file_path FROM violations ORDER BY rule" 2>/dev/null)"
BATCH_INSERTS="$(grep -c "INSERT INTO violations" "$BATCH_DATA/query-starts" 2>/dev/null || echo 0)"
if [[ "$BATCH_INSERTS" == "1" ]]; then
    log_pass "a write with five findings inserts them in one interpreter start"
else
    log_fail "a write with five findings inserts them in one interpreter start" \
        "${BATCH_INSERTS} insert start(s)"
fi
if [[ "$(printf '%s\n' "$BATCH_ROWS" | grep -c .)" == "5" ]]; then
    log_pass "and all five rows land"
else
    log_fail "and all five rows land" "$BATCH_ROWS"
fi
assert_contains "with the blocking verdict recorded" "$BATCH_ROWS" "PHP001|critical|1|src/Dirty.php"
assert_contains "and the advisory one" "$BATCH_ROWS" "PHP003|warning|0|src/Dirty.php"
if ls "$BATCH_DATA/data"/violations-queue.* >/dev/null 2>&1; then
    log_fail "the queue file does not outlive the hook" "$(ls "$BATCH_DATA/data"/violations-queue.*)"
else
    log_pass "the queue file does not outlive the hook"
fi

# A row that does not have the statement's shape is refused, not guessed at.
MALFORMED_DB="$BATCH_DATA/malformed.db"
python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --script "$MALFORMED_DB" \
    "CREATE TABLE violations (project_hash TEXT, rule TEXT, file_pattern TEXT, severity TEXT, blocked INTEGER, ignored INTEGER, source TEXT, file_path TEXT)"
MALFORMED_ERR="$(printf 'h\037PHP001\037src/**/*.php\037critical\0371\0370\037session\037src/A.php\nh\037PHP002\037broken\n' \
    | python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --batch "$MALFORMED_DB" \
        "INSERT INTO violations VALUES (?, ?, ?, ?, ?, ?, ?, ?)" 2>&1 >/dev/null)"
MALFORMED_ROWS="$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$MALFORMED_DB" "SELECT rule FROM violations" 2>/dev/null)"
if [[ "$MALFORMED_ROWS" == "PHP001" ]]; then
    log_pass "--batch inserts the well-formed row and refuses the malformed one"
else
    log_fail "--batch inserts the well-formed row and refuses the malformed one" "rows: $MALFORMED_ROWS"
fi
assert_contains "and says which line it refused" "$MALFORMED_ERR" "line 2 has 3 field(s), the statement binds 8"

# No queue opened: the immediate path, one start per row, as every other
# caller expects.
( PATH="$BATCH_DATA/shim:$PATH" bash -c "
    source '$ROOT_DIR/hooks/lib/metrics-db.sh'
    metrics_record_violation IMMEDIATE1 'src/**/*.php' critical 1 0
    metrics_record_violation IMMEDIATE2 'src/**/*.php' warning 0 0
" >/dev/null 2>&1 )
IMMEDIATE_ROWS="$(python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$METRICS_DB" \
    "SELECT rule FROM violations WHERE rule LIKE 'IMMEDIATE%' ORDER BY rule" 2>/dev/null | tr '\n' ' ')"
if [[ "$IMMEDIATE_ROWS" == "IMMEDIATE1 IMMEDIATE2 " ]]; then
    log_pass "a caller that opened no queue still inserts immediately"
else
    log_fail "a caller that opened no queue still inserts immediately" "rows: '$IMMEDIATE_ROWS'"
fi

test_summary
