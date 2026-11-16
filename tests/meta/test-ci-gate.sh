#!/usr/bin/env bash
# =============================================================================
# The CI gate, read from the workflow that defines it.
#
# Branch protection reads one check, `CI Summary`. Every other job counts only
# through that summary's `needs`, so a job missing from it can go red on every
# run and nothing stops a merge. That happened to Python Floor (3.9): absent
# from the hand-written list, red from 2026-11-02 behind a green summary.
#
# Three properties, each proved against a fixture that must fail it:
#   - every job of ci.yml is in the summary's `needs`
#   - the summary runs `if: always()`: skipped after a failed need, it would
#     report nothing, and GitHub counts a skipped required check as passed
#   - the summary fails over `needs.*.result`, not over a list to keep in sync
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
SUMMARY_JOB="summary"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-ci-gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One reader for the three checks: no PyYAML on the floor this suite runs on,
# and the workflow keeps GitHub's two-space layout, which tests/meta/
# test-release.sh already reads the same way.
gate_facts() {
    python3 - "$1" "$2" <<'PY'
import re, sys
path, summary = sys.argv[1], sys.argv[2]
jobs, needs, body, current, in_jobs = [], [], [], None, False
for raw in open(path):
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    indent = len(line) - len(line.lstrip())
    if indent == 0:
        in_jobs, current = line.startswith("jobs:"), None
        continue
    if not in_jobs:
        continue
    if indent == 2 and line.rstrip().endswith(":"):
        current = line.strip()[:-1]
        jobs.append(current)
        continue
    if current != summary:
        continue
    body.append(line.strip())
    match = re.match(r"needs:\s*\[(.*)\]", line.strip())
    if indent == 4 and match:
        needs = [n.strip() for n in match.group(1).split(",") if n.strip()]
print("ungated " + " ".join(j for j in jobs if j != summary and j not in needs))
print("always " + str("if: always()" in body).lower())
print("generic " + str(any("contains(needs.*.result, 'failure')" in b for b in body)).lower())
PY
}

fact() {
    printf '%s\n' "$1" | sed -n "s/^$2 //p"
}

check_gate() {
    local label="$1" facts="$2"
    local ungated
    ungated="$(fact "$facts" ungated)"
    if [[ -z "$ungated" ]]; then
        log_pass "$label: every job is in the summary's needs"
    else
        log_fail "$label: every job is in the summary's needs" "not gated: $ungated"
    fi
    if [[ "$(fact "$facts" always)" == "true" ]]; then
        log_pass "$label: the summary runs if: always()"
    else
        log_fail "$label: the summary runs if: always()" "a failed need would skip it, and a skipped required check passes"
    fi
    if [[ "$(fact "$facts" generic)" == "true" ]]; then
        log_pass "$label: the summary fails over needs.*.result"
    else
        log_fail "$label: the summary fails over needs.*.result" "a hand-written list drifts from needs"
    fi
}

check_gate "ci.yml" "$(gate_facts "$WORKFLOW" "$SUMMARY_JOB")"

# --- Each check goes red on the shape it guards against ----------------------

cat > "$WORK/drifted.yml" <<'YAML'
jobs:
  tests:
    runs-on: ubuntu-24.04
  floor:
    runs-on: ubuntu-24.04
  summary:
    needs: [tests]
    runs-on: ubuntu-24.04
    steps:
      - name: Check
        run: |
          [[ "${{ needs.tests.result }}" == "failure" ]] && exit 1
YAML
drifted="$(gate_facts "$WORK/drifted.yml" "$SUMMARY_JOB")"
if [[ "$(fact "$drifted" ungated)" == "floor" ]]; then
    log_pass "needs check goes red on a job left out, and names it"
else
    log_fail "needs check goes red on a job left out, and names it" "got: $(fact "$drifted" ungated)"
fi
if [[ "$(fact "$drifted" always)" == "false" ]]; then
    log_pass "always check goes red on a summary without if: always()"
else
    log_fail "always check goes red on a summary without if: always()" "fixture passed"
fi
if [[ "$(fact "$drifted" generic)" == "false" ]]; then
    log_pass "generic check goes red on a hand-written result list"
else
    log_fail "generic check goes red on a hand-written result list" "fixture passed"
fi

test_summary
