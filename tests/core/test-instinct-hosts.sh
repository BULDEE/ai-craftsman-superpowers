#!/usr/bin/env bash
# =============================================================================
# A learned skill lands where THIS host reads skills (ADR-0020, ADR-0031).
#
# Claude Code reads .claude/skills, Codex .agents/skills, Grok .grok/skills:
# hooks/host-capabilities.json says so. instinct_skills.py kept a list of its
# own with the first two only, so on Grok `approve` refused the one directory
# Grok reads, and /craftsman:metrics left the model to guess the directory per
# host. The destinations now come from the matrix, and a command given no
# directory writes to the current host's.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

INSTINCTS="$ROOT_DIR/hooks/lib/instincts.py"
REVIEW_PY="$ROOT_DIR/hooks/lib/instincts_review.py"
MATRIX="$ROOT_DIR/hooks/host-capabilities.json"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-instinct-hosts.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME"

# One project with a candidate per host under test, so each approval has
# its own row to turn approved.
new_db() {
    local db="$1"
    sqlite3 "$db" "
CREATE TABLE corrections(id INTEGER PRIMARY KEY, timestamp TEXT DEFAULT (datetime('now')),
  project_hash TEXT, rule TEXT, file_pattern TEXT, file_path TEXT, action TEXT, context TEXT);
INSERT INTO corrections (project_hash, rule, file_pattern, file_path, action, context) VALUES
  ('p1','TS003','src/a/**/*.ts','src/a/a.ts','fixed','null handled'),
  ('p1','TS003','src/b/**/*.ts','src/b/b.ts','fixed','null handled'),
  ('p1','TS003','src/c/**/*.ts','src/c/c.ts','fixed','null handled');"
    python3 "$INSTINCTS" candidates "$db" p1 >/dev/null 2>&1
}

# Runs from a project directory, as the metrics skill does, on a given host.
on_host() {
    local host="$1" project="$2"; shift 2
    (cd "$project" && HOME="$FAKE_HOME" CRAFTSMAN_SESSION_HOST="$host" "$@")
}

echo "=== Every project skills directory the matrix declares is accepted ==="
while IFS=$'\t' read -r host dir; do
    project="$WORK/accept-$host"; mkdir -p "$project"; new_db "$project/m.db"
    out=$(on_host "$host" "$project" python3 "$INSTINCTS" approve "$project/m.db" 1 "$project/$dir" 2>&1); rc=$?
    if [[ $rc -eq 0 && -f "$project/$dir/learned-ts003/SKILL.md" ]]; then
        log_pass "$host: approve into $dir is written"
    else
        log_fail "$host: approve into $dir is written" "rc=$rc $out"
    fi
done < <(jq -r '.hosts | to_entries[] | select(.value.skills_dir) | "\(.key)\t\(.value.skills_dir)"' "$MATRIX")

echo ""
echo "=== With no directory given, the current host's is used ==="
for host in claude-code codex grok; do
    dir=$(jq -r --arg h "$host" '.hosts[$h].skills_dir' "$MATRIX")
    project="$WORK/default-$host"; mkdir -p "$project"; new_db "$project/m.db"
    queue=$(on_host "$host" "$project" python3 "$REVIEW_PY" "$project/m.db" p1 2>&1)
    shown=$(printf '%s' "$queue" | python3 -c 'import json,sys; print(json.load(sys.stdin)["candidates"][0]["skill_path"])' 2>&1)
    out=$(on_host "$host" "$project" python3 "$INSTINCTS" approve "$project/m.db" 1 2>&1); rc=$?
    written="$project/$dir/learned-ts003/SKILL.md"
    if [[ $rc -eq 0 && -f "$written" && "$shown" -ef "$written" ]]; then
        log_pass "$host: review shows and approve writes $dir/learned-ts003/SKILL.md"
    else
        log_fail "$host: review shows and approve writes $dir" "rc=$rc shown=$shown out=$out"
    fi
done

echo ""
echo "=== A directory no host reads is still refused ==="
project="$WORK/refuse"; mkdir -p "$project"; new_db "$project/m.db"
out=$(on_host claude-code "$project" python3 "$INSTINCTS" approve "$project/m.db" 1 "$project/skills" 2>&1); rc=$?
if [[ $rc -ne 0 && ! -e "$project/skills" ]]; then
    log_pass "approve refuses a directory no host loads"
else
    log_fail "approve refuses a directory no host loads" "rc=$rc $out"
fi
out=$(on_host claude-code "$project" python3 "$REVIEW_PY" "$project/m.db" p1 "$project/skills" 2>&1); rc=$?
if [[ $rc -ne 0 ]]; then
    log_pass "review refuses to preview a destination approve would refuse"
else
    log_fail "review refuses a destination approve would refuse" "$out"
fi

echo ""
echo "=== Global promotion goes where the host keeps user skills, or nowhere ==="
global_db() {
    local db="$1"
    new_db "$db"
    sqlite3 "$db" "INSERT INTO instincts (project_hash, rule, pattern_summary, occurrences, distinct_files, confidence, status)
                   VALUES ('p2', 'TS003', 'null handled', 4, 4, 0.5, 'approved');
                   UPDATE instincts SET status = 'approved' WHERE project_hash = 'p1';"
}
for host in claude-code codex; do
    user_dir=$(jq -r --arg h "$host" '.hosts[$h].user_skills_dir // empty' "$MATRIX")
    project="$WORK/global-$host"; mkdir -p "$project"; global_db "$project/m.db"
    out=$(on_host "$host" "$project" python3 "$INSTINCTS" promote "$project/m.db" TS003 2>&1); rc=$?
    written="$FAKE_HOME/${user_dir#\~/}/learned-global-ts003/SKILL.md"
    if [[ -n "$user_dir" && $rc -eq 0 && -f "$written" ]]; then
        log_pass "$host: promote with no directory writes ${user_dir}/learned-global-ts003"
    else
        log_fail "$host: promote writes the host's user skills" "user_dir=$user_dir rc=$rc $out"
    fi
done
project="$WORK/global-grok"; mkdir -p "$project"; global_db "$project/m.db"
out=$(on_host grok "$project" python3 "$INSTINCTS" promote "$project/m.db" TS003 2>&1); rc=$?
if [[ $rc -ne 0 && "$out" == *"grok"* && -z "$(find "$FAKE_HOME" -path '*learned-global-ts003*' -newer "$project/m.db" 2>/dev/null)" ]]; then
    log_pass "grok: promote refuses, naming the host, while no user skills directory is measured"
else
    log_fail "grok: promote refuses while no user directory is measured" "rc=$rc $out"
fi

echo ""
echo "=== The metrics skill leaves the directory to the helper ==="
# The skill used to spell `"$PWD/.claude/skills"` with a note for Codex and
# none for Grok, so the model picked the directory per host. A command line
# that names a host directory again is that guess coming back.
hardcoded() { grep -nE 'instincts (approve|review|promote)[^`]*\.(claude|agents|grok)/skills' "$1"; }
if ! hardcoded "$ROOT_DIR/skills/metrics/SKILL.md" >/dev/null; then
    log_pass "no instincts command in the metrics skill names a host's skills directory"
else
    log_fail "the metrics skill names a host directory" "$(hardcoded "$ROOT_DIR/skills/metrics/SKILL.md")"
fi
printf 'bash x instincts approve <id> "$PWD/.claude/skills"\n' > "$WORK/guessing.md"
if hardcoded "$WORK/guessing.md" >/dev/null; then
    log_pass "and the check catches a command that does"
else
    log_fail "the hardcoded-directory check can fail" "it did not match the fixture"
fi

test_summary
