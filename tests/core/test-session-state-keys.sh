#!/usr/bin/env bash
# =============================================================================
# Every session-state key a hook reads is a key some hook writes.
#
# Four keys were read and never written: `design_used` (so the design-pass
# exemption in bias-detector.sh could never fire, and the README row claiming
# the plugin blocks a design decision described a branch nothing reached),
# `writes_count` (so task-completed-verify.sh saw no writes and let every task
# through), `team_type` and `completed_tasks` (so sessions.skills_used held []
# on every row ever written).
#
# A read with no writer is not a missing feature: it is a guard that reports
# the safe answer forever, and nothing fails while it does.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Session state keys ==="

ORPHANS=$(python3 - "$ROOT_DIR" <<'PY'
import os, re, sys

root = sys.argv[1]
read_keys, written_keys = {}, set()

# Writers: the CLI verbs that mutate the file, plus the keys session_state.py
# assigns directly.
lib = open(os.path.join(root, 'hooks/lib/session_state.py'), encoding='utf-8').read()
written_keys.update(re.findall(r"state\[['\"]([a-z_]+)['\"]\]\s*=", lib))
written_keys.update(re.findall(r"state\.setdefault\(['\"]([a-z_]+)['\"]", lib))

def scan(path, text):
    for verb in ('increment', 'append', 'merge', 'set', 'list-upsert', 'list-remove'):
        for key in re.findall(r'session_state\.py"?\s+%s\s+"[^"]*"\s+([a-z_]+)' % verb, text):
            written_keys.add(key)
    for verb in ('check-flag', 'read'):
        for key in re.findall(r'session_state\.py"?\s+%s\s+"[^"]*"\s+([a-z_]+)' % verb, text):
            read_keys.setdefault(key, path)

for folder in ('hooks', 'skills', 'ci'):
    base = os.path.join(root, folder)
    for dirpath, _, names in os.walk(base):
        for name in names:
            if not name.endswith(('.sh', '.py', '.md')):
                continue
            path = os.path.join(dirpath, name)
            try:
                scan(os.path.relpath(path, root), open(path, encoding='utf-8').read())
            except (OSError, UnicodeDecodeError):
                continue

# Keys the read-side handlers of session_state.py pull out of the state.
for key in re.findall(r"state\.get\(['\"]([a-z_]+)['\"]", lib):
    read_keys.setdefault(key, 'hooks/lib/session_state.py')

for key in sorted(set(read_keys) - written_keys):
    print("%s (read by %s)" % (key, read_keys[key]))
PY
)

if [[ -z "$ORPHANS" ]]; then
    log_pass "every session-state key read by a hook has a writer"
else
    log_fail "every session-state key read by a hook has a writer" "orphans: $ORPHANS"
fi

# -----------------------------------------------------------------------------
# design_used is set by the prompt that starts a design pass
# -----------------------------------------------------------------------------
# bias-detector.sh is the only UserPromptSubmit hook, so it is where the plugin
# learns that a design pass was asked for. It read the flag and nothing set it.
WORK=$(mktemp -d)
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"
STATE="$WORK/data/session-state.json"

run_bias() {
    echo "{\"prompt\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}" \
        | bash "$ROOT_DIR/hooks/bias-detector.sh" 2>/dev/null
}

run_bias "/craftsman:design a Subscription aggregate" >/dev/null
if [[ -f "$STATE" ]] && python3 "$ROOT_DIR/hooks/lib/session_state.py" check-flag "$STATE" design_used | grep -q true; then
    log_pass "a /craftsman:design prompt sets design_used"
else
    log_fail "a /craftsman:design prompt sets design_used" \
        "state=$(cat "$STATE" 2>/dev/null | head -c 200)"
fi

# And the flag is what silences the domain-modeling warning, which is the
# branch that had never run.
after=$(run_bias "create the Invoice entity with its value objects")
if echo "$after" | grep -qi 'design'; then
    log_fail "the domain-modeling warning is silent once a design pass ran" \
        "still warned: $(echo "$after" | head -c 200)"
else
    log_pass "the domain-modeling warning is silent once a design pass ran"
fi

# -----------------------------------------------------------------------------
# A hook that warns is not advertised as one that blocks
# -----------------------------------------------------------------------------
# bias-detector.sh ends on `exit 0` and emits warnings only, which its own file
# says on the line above that exit. The README comparison table said "Blocks a
# design decision made without a design pass", in the column that sells the
# plugin against a linter.
if grep -q 'Always exit 0 (warning only, never block)' "$ROOT_DIR/hooks/bias-detector.sh"; then
    blocking_claim=$(grep -nE '^\| (Blocks|Bloque) .*(design|architecture)' "$ROOT_DIR/README.md" "$ROOT_DIR/README.fr.md" || true)
    if [[ -z "$blocking_claim" ]]; then
        log_pass "no README row says the design-pass check blocks, because it warns"
    else
        log_fail "no README row says the design-pass check blocks, because it warns" "$blocking_claim"
    fi
else
    log_pass "bias-detector.sh no longer declares itself warning-only"
fi

rm -rf "$WORK"
unset CLAUDE_PLUGIN_DATA

test_summary
