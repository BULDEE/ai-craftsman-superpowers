#!/usr/bin/env bash
# =============================================================================
# The hook counts in the documents are the counts in hooks.json.
#
# SECURITY.md said "19 scripts, 13 events" against 17 and 12 actually wired,
# docs/reference/hooks.md said 13 too, and docs/getting-started/concepts.md
# said 13. A reader auditing what runs on their machine counts the entries and
# finds a discrepancy they cannot explain, in the one document where that is
# least acceptable.
#
# Counted from hooks.json, never from files on disk: hooks/design-panel.sh is a
# skill helper that no event wires, and the first version of this test counted
# it, enforcing a heading (18) that the table under it (17 rows) contradicted.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Hook inventory ==="

read -r EVENTS SCRIPTS <<< "$(python3 -c "
import json, re
data = json.load(open('$ROOT_DIR/hooks/hooks.json'))
hooks = data.get('hooks', data)
scripts = set()
for entries in hooks.values():
    for entry in entries:
        for hook in entry.get('hooks', []):
            scripts.update(re.findall(r'hooks/([A-Za-z0-9_.-]+\.sh)', hook.get('command', '')))
print(len(hooks), len(scripts))
" 2>/dev/null)"

if [[ "${EVENTS:-0}" -gt 0 && "${SCRIPTS:-0}" -gt 0 ]]; then
    log_pass "hooks.json wires ${SCRIPTS} scripts across ${EVENTS} events"
else
    log_fail "hooks.json could be read" "events=${EVENTS:-} scripts=${SCRIPTS:-}"
fi

# Every script hooks.json names exists, and the one file on disk it does not
# name is the skill helper, by name, so a new orphan is a finding.
missing=""
for script in $(python3 -c "
import json, re
data = json.load(open('$ROOT_DIR/hooks/hooks.json'))
hooks = data.get('hooks', data)
names = set()
for entries in hooks.values():
    for entry in entries:
        for hook in entry.get('hooks', []):
            names.update(re.findall(r'hooks/([A-Za-z0-9_.-]+\.sh)', hook.get('command', '')))
print(' '.join(sorted(names)))
"); do
    [[ -f "$ROOT_DIR/hooks/$script" ]] || missing="${missing}${script} "
done
if [[ -z "$missing" ]]; then
    log_pass "every script hooks.json names exists on disk"
else
    log_fail "every script hooks.json names exists on disk" "missing: $missing"
fi

orphans=""
for path in "$ROOT_DIR"/hooks/*.sh; do
    name="${path##*/}"
    grep -q "hooks/${name}" "$ROOT_DIR/hooks/hooks.json" || orphans="${orphans}${name} "
done
if [[ "${orphans% }" == "design-panel.sh" ]]; then
    log_pass "the only script no event wires is the design-panel skill helper"
else
    log_fail "the only script no event wires is the design-panel skill helper" \
        "unwired: '${orphans}'"
fi

# The documents. Each states the count in its own words, so each is matched in
# its own words, and the expected text is built from hooks.json rather than
# typed here a fourth time.
declare -a DOC_CHECKS=(
    "SECURITY.md|Hooks (${SCRIPTS} scripts, ${EVENTS} events)"
    "docs/getting-started/concepts.md|Hooks (${EVENTS} events)"
    "docs/reference/hooks.md|${EVENTS} hook events wired"
)
for check in "${DOC_CHECKS[@]}"; do
    doc="${check%%|*}"
    expected="${check#*|}"
    if grep -qF "$expected" "$ROOT_DIR/$doc" 2>/dev/null; then
        log_pass "$doc states the count hooks.json has"
    else
        log_fail "$doc states the count hooks.json has" \
            "expected '$expected', found: $(grep -oE 'Hooks \([0-9]+[^)]*\)|[0-9]+ hook events wired' "$ROOT_DIR/$doc" | head -1)"
    fi
done

# And nothing else states a different number in prose. A count repeated in
# four places drifts in four places.
stale=$(grep -rnoE "Hooks \([0-9]+ (scripts, [0-9]+ )?events\)|[0-9]+ hook events wired" \
    "$ROOT_DIR/docs" "$ROOT_DIR/README.md" "$ROOT_DIR/README.fr.md" "$ROOT_DIR/SECURITY.md" "$ROOT_DIR/CLAUDE.md" 2>/dev/null \
    | grep -vE "\(${SCRIPTS} scripts, ${EVENTS} events\)|\(${EVENTS} events\)|${EVENTS} hook events wired" || true)
if [[ -z "$stale" ]]; then
    log_pass "no document states a hook count hooks.json contradicts"
else
    log_fail "no document states a hook count hooks.json contradicts" "$stale"
fi

test_summary
