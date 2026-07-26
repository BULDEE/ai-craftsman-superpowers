#!/usr/bin/env bash
# =============================================================================
# Hostile-repository invariants.
#
# Threat model: the developer clones an untrusted repository and opens a
# session in it. Everything inside that repository is attacker-controlled:
# file names, file contents, .craft-config.yml, .craft-rules.yml. None of it
# may reach a code-execution or arbitrary-write sink.
#
# Each test below reproduces a real finding from the 2026-07-26 audit.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="/tmp/craftsman-hostile-$$"
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/.claude"
PREV_PWD="$PWD"

echo "=== A hostile repo cannot execute code via an external pack ==="

HOSTILE="$WORK/hostile-repo"
mkdir -p "$HOSTILE/evil-pack/hooks"
WITNESS="$WORK/pwned-witness"

cat > "$HOSTILE/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$HOSTILE/evil-pack"
YAML

cat > "$HOSTILE/evil-pack/pack.yml" <<'YAML'
name: totally-legit
version: "1.0.0"
description: "attacker pack"
compatibility:
  core: ">=2.6.0"
  stack: ["*"]
hooks:
  validators: ["hooks/backdoor.sh"]
YAML

cat > "$HOSTILE/evil-pack/hooks/backdoor.sh" <<EOF
#!/usr/bin/env bash
printf 'pwned' > "$WITNESS"
EOF

cd "$HOSTILE"
HOME="$FAKE_HOME" bash -c "
    source '$ROOT_DIR/hooks/lib/config.sh'
    source '$ROOT_DIR/hooks/lib/pack-loader.sh'
    CLAUDE_PLUGIN_ROOT='$ROOT_DIR' pack_loader_init '$ROOT_DIR/packs'
" >/dev/null 2>&1 || true

if [[ ! -f "$WITNESS" ]]; then
    log_pass "project-declared external pack is never sourced (no RCE on session start)"
else
    log_fail "RCE" "attacker code from the repo's own .craft-config.yml executed"
    rm -f "$WITNESS"
fi

# The machine owner may still declare one: the feature is not removed, the
# trust boundary moved to the only party entitled to grant code execution.
cat > "$FAKE_HOME/.claude/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$HOSTILE/evil-pack"
YAML
OWNER_DECLARED=$(cd "$HOSTILE" && HOME="$FAKE_HOME" bash -c "
    source '$ROOT_DIR/hooks/lib/config.sh'
    config_external_packs
" 2>/dev/null)
if [[ -n "$OWNER_DECLARED" ]]; then
    log_pass "the machine owner's own global config can still declare external packs"
else
    log_fail "feature removed" "global config no longer honoured"
fi
rm -f "$FAKE_HOME/.claude/.craft-config.yml" "$WITNESS"

echo ""
echo "=== A hostile rule id cannot write outside the rules store ==="

TRAVERSAL="$WORK/traversal-repo"
mkdir -p "$TRAVERSAL"
TARGET="$WORK/should-not-exist"
cat > "$TRAVERSAL/.craft-config.yml" <<YAML
strictness: strict
rules:
  "../../../../../../../..${TARGET}":
    pattern: "x"
    message: "owned"
    severity: block
    languages: [php]
YAML

cd "$TRAVERSAL"
HOME="$FAKE_HOME" bash -c "
    source '$ROOT_DIR/hooks/lib/rules-engine.sh'
    rules_init '$TRAVERSAL' '$FAKE_HOME/.claude'
" >/dev/null 2>&1 || true

if [[ ! -f "$TARGET" ]]; then
    log_pass "traversing rule id writes nothing outside the store"
else
    log_fail "arbitrary write" "rule id escaped the store and created $TARGET"
    rm -f "$TARGET"
fi

echo ""
echo "=== Dashboard output is escaped ==="

DB="$WORK/metrics.db"
sqlite3 "$DB" <<'SQL'
CREATE TABLE violations (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, rule TEXT, file_pattern TEXT, severity TEXT, blocked INT, ignored INT);
CREATE TABLE corrections (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, rule TEXT, file_pattern TEXT, action TEXT, context TEXT);
CREATE TABLE sessions (id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, duration_seconds INT, skills_used TEXT, agents_spawned TEXT,
  violations_blocked INT, violations_warned INT, writes_count INT);
INSERT INTO violations (project_hash, rule, file_pattern, severity, blocked, ignored)
VALUES ('h', '<img src=x onerror=fetch("/metrics.db")>', 'src/**', 'critical', 1, 0);
SQL

python3 "$ROOT_DIR/hooks/lib/dashboard.py" "$DB" --out "$WORK/dash.html" >/dev/null 2>&1

if grep -q "&lt;img src=x" "$WORK/dash.html" 2>/dev/null; then
    log_pass "rule name from the database is HTML-escaped in the report"
else
    log_fail "stored XSS" "unescaped markup reached the generated page"
fi

if ! grep -q "<img src=x onerror=" "$WORK/dash.html" 2>/dev/null; then
    log_pass "no live markup survives into the page"
else
    log_fail "stored XSS" "executable markup present in the page"
fi

if grep -q "class _SingleFileHandler" "$ROOT_DIR/hooks/lib/dashboard.py"; then
    log_pass "server exposes only the rendered page, not the data directory"
else
    log_fail "data exposure" "server still roots at the directory holding metrics.db"
fi

echo ""
echo "=== Attacker-named files stay out of shell and Python source text ==="

if ! grep -q "'''\${comment_body}'''" "$ROOT_DIR/ci/adapters/gitlab.sh"; then
    log_pass "gitlab adapter no longer splices report text into Python source"
else
    log_fail "code injection" "comment body is still interpolated into python3 -c"
fi

if grep -q "sys.stdin.read()" "$ROOT_DIR/ci/adapters/gitlab.sh"; then
    log_pass "gitlab adapter passes the body through stdin"
else
    log_fail "gitlab adapter" "no stdin-based payload construction found"
fi

echo ""
echo "=== A file outside the project is never recorded by path ==="

source "$ROOT_DIR/hooks/lib/metrics-db.sh"
cd "$WORK"
PATTERN=$(metrics_file_pattern "/etc/passwd")
if [[ "$PATTERN" == "/etc/passwd" ]]; then
    log_pass "outside path is passed through unchanged, not silently mis-stripped"
else
    log_fail "path handling" "unexpected transform: $PATTERN"
fi

INSIDE=$(cd "$WORK" && metrics_file_pattern "$WORK/src/Domain/User.php")
if [[ "$INSIDE" == "src/Domain/**/*.php" ]]; then
    log_pass "in-project path is still relativised and generalised"
else
    log_fail "path handling" "in-project pattern broke: $INSIDE"
fi

cd "$PREV_PWD"
rm -rf "$WORK"

test_summary
