#!/usr/bin/env bash
# =============================================================================
# Throwing an attempt away keeps what was there before the attempt.
#
# The Mikado discipline (knowledge/refactoring/mikado-method.md), the refactor
# and legacy skills and the legacy-surgeon agent prescribed `git reset --hard`
# to drop a failed attempt, and characterization-testing.md undid a deliberate
# break with `git checkout <file>`. All of them run in the user's checkout, and
# both commands also drop whatever the user had not committed before the
# attempt started (CR-176, M10: measured in a throwaway repository, the user's
# file came back as the last commit had it).
#
# Each documented sequence is read from its document and run, step by step in
# separate shells like separate tool calls, in a throwaway repository holding
# a user's uncommitted and untracked work. The work must survive; the attempt
# must be gone.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

MIKADO_DOCS=("$ROOT_DIR/knowledge/refactoring/mikado-method.md" "$ROOT_DIR/skills/refactor/SKILL.md")
CHARACTERIZATION_DOC="$ROOT_DIR/knowledge/legacy/characterization-testing.md"

# documented_block <file> <label>: the first ```bash block after the heading
# (`### label`) or bold lead (`**label**`) that names the step.
documented_block() {
    awk -v label="$2" '!found && (index($0, "# " label) || index($0, "**" label)) && /^(#|\*\*)/ {found=1; next}
        found && /^```bash/{code=1; next}
        code && /^```/{exit}
        code' "$1"
}

new_repository() {
    local repo
    repo=$(mktemp -d "${TMPDIR:-/tmp}/attempt-revert.XXXXXX") || return 1
    (
        cd "$repo" || exit 1
        git init -q .
        mkdir src
        printf 'user base\n' > src/user.txt
        printf 'target base\n' > src/target.txt
        printf 'doomed\n' > src/doomed.txt
        git add -A && git commit -q -m base
    ) >/dev/null 2>&1 || return 1
    printf '%s' "$repo"
}

# mikado_sentinel <doc>: "ok", or what the documented sequence destroyed.
mikado_sentinel() {
    local mark revert repo
    mark=$(documented_block "$1" "Mark the starting point")
    revert=$(documented_block "$1" "Throw the attempt away")
    [[ -n "$mark" && -n "$revert" ]] || { echo "no documented mark and throw-away sequence"; return 0; }
    repo=$(new_repository) || { echo "could not create the throwaway repository"; return 0; }
    (
        cd "$repo" || exit 1
        printf 'uncommitted user work\n' >> src/user.txt
        printf 'untracked user note\n' > NOTES.md
        bash -c "$mark" >/dev/null 2>&1 || { echo "the mark step failed"; exit 0; }
        printf 'attempt\n' >> src/target.txt
        printf 'attempt\n' >> src/user.txt
        printf 'attempt\n' > src/new.txt
        rm src/doomed.txt
        bash -c "$revert" >/dev/null 2>&1
        [[ "$(cat src/user.txt)" == $'user base\nuncommitted user work' ]] \
            || { echo "the user's uncommitted change was lost: '$(tr '\n' '|' < src/user.txt)'"; exit 0; }
        [[ "$(cat NOTES.md 2>/dev/null)" == 'untracked user note' ]] || { echo "the user's untracked file was lost"; exit 0; }
        [[ "$(cat src/target.txt)" == 'target base' ]] || { echo "the attempt on a tracked file survived"; exit 0; }
        [[ ! -e src/new.txt ]] || { echo "the file the attempt created survived"; exit 0; }
        [[ -f src/doomed.txt ]] || { echo "the file the attempt deleted was not restored"; exit 0; }
        echo ok
    )
    rm -rf "$repo"
}

echo ""
echo "=== A Mikado attempt is thrown away without the work that preceded it ==="

for doc in "${MIKADO_DOCS[@]}"; do
    rel="${doc#"$ROOT_DIR"/}"
    verdict=$(mikado_sentinel "$doc")
    if [[ "$verdict" == ok ]]; then
        log_pass "$rel: the documented revert drops the attempt and keeps the user's uncommitted and untracked work"
    else
        log_fail "$rel: documented revert" "$verdict"
    fi
done

echo ""
echo "=== A deliberate break is undone to the exact bytes it replaced ==="

# The block breaks src/checkout.js, runs the suite, and restores the file. A
# fake npm stands in for the suite: what is judged is the restore.
CHAR_BLOCK=$(documented_block "$CHARACTERIZATION_DOC" "Checking the Net Catches Change")
CHAR_REPO=$(new_repository)
CHAR_VERDICT=$(
    [[ -n "$CHAR_REPO" ]] && cd "$CHAR_REPO" || { echo "could not create the throwaway repository"; exit 0; }
    mkdir -p fakebin && printf '#!/bin/sh\nexit 1\n' > fakebin/npm && chmod +x fakebin/npm
    printf 'function total() { return total; }\n' > src/checkout.js
    git add src/checkout.js && git commit -q -m checkout
    printf '// uncommitted user work\n' >> src/checkout.js
    before=$(cat src/checkout.js)
    PATH="$CHAR_REPO/fakebin:$PATH" bash -c "$CHAR_BLOCK" >/dev/null 2>&1
    if [[ -z "$CHAR_BLOCK" ]]; then
        echo "no documented block"
    elif [[ "$(cat src/checkout.js)" != "$before" ]]; then
        echo "src/checkout.js is not what it was before the break: '$(tr '\n' '|' < src/checkout.js)'"
    elif [[ -n "$(find src -name '*.orig' -o -name '*.bak')" ]]; then
        echo "the restore left a backup file behind"
    else
        echo ok
    fi
)
rm -rf "$CHAR_REPO"
if [[ "$CHAR_VERDICT" == ok ]]; then
    log_pass "characterization-testing.md: the break is undone byte for byte, uncommitted work included"
else
    log_fail "characterization-testing.md: undo of the deliberate break" "$CHAR_VERDICT"
fi

echo ""
echo "=== No contract prescribes a revert that discards the user's work ==="

# skills/git/SKILL.md lists these commands as dangerous and gates them behind
# an explicit confirmation; everywhere else they are a prescription.
DESTRUCTIVE=$(grep -rnE 'git reset --hard|git clean -f|git checkout [^ -][^ ]*/|git checkout -- ' \
    "$ROOT_DIR/skills" "$ROOT_DIR/agents" "$ROOT_DIR/knowledge" "$ROOT_DIR/packs" 2>/dev/null \
    | grep -v "^$ROOT_DIR/skills/git/SKILL.md:" \
    | grep -viE '(never|not) `git reset --hard`' || true)
if [[ -z "$DESTRUCTIVE" ]]; then
    log_pass "no skill, agent or knowledge file prescribes a global reset or a checkout of a path as a revert"
else
    log_fail "destructive revert prescribed" "$(printf '%s' "$DESTRUCTIVE" | sed "s|$ROOT_DIR/||" | tr '\n' ' ')"
fi

test_summary
