#!/usr/bin/env bash
# =============================================================================
# Instinct pipeline tests (ADR-0020) + context budget config tests (ADR-0021)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

INSTINCTS="$ROOT_DIR/hooks/lib/instincts.py"
TEST_DIR="/tmp/craftsman-instincts-test-$$"
DB="$TEST_DIR/metrics.db"
SKILLS_DIR="$TEST_DIR/learned"
PH="testhash"

mkdir -p "$TEST_DIR"

sqlite3 "$DB" <<'SQL'
CREATE TABLE corrections (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    project_hash TEXT NOT NULL,
    rule TEXT NOT NULL,
    file_pattern TEXT NOT NULL,
    action TEXT NOT NULL,
    context TEXT
);
INSERT INTO corrections (project_hash, rule, file_pattern, action, context) VALUES
  ('testhash', 'PHP001', 'src/A/**/*.php', 'fixed', 'added strict_types'),
  ('testhash', 'PHP001', 'src/B/**/*.php', 'fixed', 'added strict_types'),
  ('testhash', 'PHP001', 'src/C/**/*.php', 'fixed', 'added strict_types'),
  ('testhash', 'TS001',  'src/x/**/*.ts', 'fixed', 'removed any'),
  ('testhash', 'TS001',  'src/x/**/*.ts', 'fixed', 'removed any'),
  ('testhash', 'PHP005', 'src/A/**/*.php', 'ignored', 'setter kept');
SQL

echo "=== Instinct Candidate Extraction ==="

OUTPUT=$(python3 "$INSTINCTS" candidates "$DB" "$PH" 2>&1)
if echo "$OUTPUT" | grep -q "PHP001 \[candidate\]"; then
    log_pass "PHP001 promoted to candidate (3 corrections, 3 files)"
else
    log_fail "candidate extraction" "PHP001 missing: $OUTPUT"
fi

if ! echo "$OUTPUT" | grep -q "TS001"; then
    log_pass "TS001 not a candidate (only 1 distinct file)"
else
    log_fail "candidate threshold" "TS001 should not qualify: $OUTPUT"
fi

if ! echo "$OUTPUT" | grep -q "PHP005"; then
    log_pass "PHP005 not a candidate (action=ignored, not fixed)"
else
    log_fail "candidate action filter" "PHP005 should not qualify: $OUTPUT"
fi

COUNT=$(python3 "$INSTINCTS" pending-count "$DB" "$PH" 2>/dev/null)
if [[ "$COUNT" == "1" ]]; then
    log_pass "pending-count reports 1 candidate"
else
    log_fail "pending-count" "expected 1, got $COUNT"
fi

echo ""
echo "=== Approve Generates Learned Skill ==="

CAND_ID=$(sqlite3 "$DB" "SELECT id FROM instincts WHERE rule='PHP001';")
python3 "$INSTINCTS" approve "$DB" "$CAND_ID" "$SKILLS_DIR" >/dev/null 2>&1
SKILL_FILE="$SKILLS_DIR/learned-php001/SKILL.md"

if [[ -f "$SKILL_FILE" ]]; then
    log_pass "approve generates learned-php001/SKILL.md"
else
    log_fail "approve generation" "missing $SKILL_FILE"
fi

if grep -q "user-invocable: false" "$SKILL_FILE" 2>/dev/null; then
    log_pass "learned skill is user-invocable: false (background knowledge)"
else
    log_fail "learned skill frontmatter" "missing user-invocable: false"
fi

if grep -q "## Provenance" "$SKILL_FILE" 2>/dev/null && grep -q "3 recorded corrections" "$SKILL_FILE" 2>/dev/null; then
    log_pass "learned skill records provenance (corrections count)"
else
    log_fail "learned skill provenance" "missing provenance section"
fi

STATUS=$(sqlite3 "$DB" "SELECT status FROM instincts WHERE id=$CAND_ID;")
if [[ "$STATUS" == "approved" ]]; then
    log_pass "instinct marked approved after generation"
else
    log_fail "approve status" "expected approved, got $STATUS"
fi

echo ""
echo "=== Reject Is Sticky ==="

sqlite3 "$DB" "INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES
  ('testhash','TS002','src/a/**/*.ts','fixed'),
  ('testhash','TS002','src/b/**/*.ts','fixed'),
  ('testhash','TS002','src/c/**/*.ts','fixed');"
python3 "$INSTINCTS" candidates "$DB" "$PH" >/dev/null 2>&1
TS2_ID=$(sqlite3 "$DB" "SELECT id FROM instincts WHERE rule='TS002';")
python3 "$INSTINCTS" reject "$DB" "$TS2_ID" >/dev/null 2>&1

OUTPUT=$(python3 "$INSTINCTS" candidates "$DB" "$PH" 2>&1)
if ! echo "$OUTPUT" | grep -q "TS002"; then
    log_pass "rejected instinct not re-proposed without new evidence"
else
    log_fail "reject stickiness" "TS002 re-proposed: $OUTPUT"
fi

sqlite3 "$DB" "INSERT INTO corrections (project_hash, rule, file_pattern, action) VALUES
  ('testhash','TS002','src/d/**/*.ts','fixed'),
  ('testhash','TS002','src/e/**/*.ts','fixed'),
  ('testhash','TS002','src/f/**/*.ts','fixed');"
OUTPUT=$(python3 "$INSTINCTS" candidates "$DB" "$PH" 2>&1)
if echo "$OUTPUT" | grep -q "TS002 \[candidate\]"; then
    log_pass "rejected instinct revived after 3+ new corrections"
else
    log_fail "reject revival" "TS002 should be re-proposed: $OUTPUT"
fi

echo ""
echo "=== Context Budget Config (ADR-0021) ==="

source "$ROOT_DIR/hooks/lib/config.sh"

CONFIG_DIR="$TEST_DIR/project"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/.craft-config.yml" <<'YAML'
v: 4
strictness: strict
context_budget:
  session_start_max_chars: 2500
  max_learned_skills: 3
hooks:
  disabled: [bias-detector, agent-sentry-context]
YAML

PREV_PWD="$PWD"
cd "$CONFIG_DIR"

if [[ "$(config_session_start_max_chars)" == "2500" ]]; then
    log_pass "config_session_start_max_chars reads nested value (2500)"
else
    log_fail "session_start_max_chars" "got $(config_session_start_max_chars)"
fi

if [[ "$(config_max_learned_skills)" == "3" ]]; then
    log_pass "config_max_learned_skills reads nested value (3)"
else
    log_fail "max_learned_skills" "got $(config_max_learned_skills)"
fi

DISABLED=$(config_hooks_disabled_csv)
if [[ "$DISABLED" == "bias-detector,agent-sentry-context" ]]; then
    log_pass "config_hooks_disabled_csv parses inline list"
else
    log_fail "hooks_disabled" "got '$DISABLED'"
fi

source "$ROOT_DIR/hooks/lib/hook-profile.sh"
if ! hook_profile_should_run "bias-detector" "always"; then
    log_pass "hook_profile_should_run honors hooks.disabled from config"
else
    log_fail "kill switch" "bias-detector should be disabled via yaml"
fi

if hook_profile_should_run "post-write-check" "always"; then
    log_pass "non-disabled hook still runs"
else
    log_fail "kill switch scope" "post-write-check wrongly disabled"
fi

cd "$PREV_PWD"

# Defaults without config
DEFAULT_DIR="$TEST_DIR/empty"
mkdir -p "$DEFAULT_DIR"
cd "$DEFAULT_DIR"
_ORIG_HOME="$HOME"
export HOME="$TEST_DIR/fakehome"
mkdir -p "$HOME/.claude"
if [[ "$(config_session_start_max_chars)" == "4000" && "$(config_max_learned_skills)" == "6" ]]; then
    log_pass "budget defaults apply without config (4000/6)"
else
    log_fail "budget defaults" "got $(config_session_start_max_chars)/$(config_max_learned_skills)"
fi
export HOME="$_ORIG_HOME"
cd "$PREV_PWD"

# Schema file is valid JSON
if jq -e '.properties.context_budget' "$ROOT_DIR/schemas/craft-config.schema.json" >/dev/null 2>&1; then
    log_pass "craft-config.schema.json valid and covers context_budget"
else
    log_fail "config schema" "invalid JSON or missing context_budget"
fi

rm -rf "$TEST_DIR"

test_summary
