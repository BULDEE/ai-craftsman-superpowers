#!/usr/bin/env bash
# =============================================================================
# Dynamic-context invariants.
#
# Skills inject live context with Claude Code's !`command` syntax (ADR-0017).
# The harness expands every one of those patterns BEFORE the skill is loaded,
# and a pattern that exits non-zero aborts the whole invocation: the user's
# prompt is discarded and all they see is
#   Error: Shell command failed for pattern "!`...`"
#
# That is exactly what /craftsman:challenge did outside a git repository until
# 4.3.2: `git log --oneline -10 2>/dev/null` sent stderr to /dev/null but still
# exited 128, so the plugin was unusable on any non-versioned directory.
# A `2>/dev/null` silences the message, never the exit code.
#
# Invariant: every injected pattern exits 0 in a hostile-but-legal environment
# (no git repository, no metrics database, no generated codemap), so the skill
# degrades to a fallback string instead of taking the prompt down with it.
#
# The patterns are read-only reporting commands and are executed here for real,
# exactly as the harness would. Keep them that way: anything with a side effect
# does not belong in a !`...` injection in the first place.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-dynctx.XXXXXX")"
FAKE_HOME="$WORK/home"
NO_GIT="$WORK/not-a-repo"
mkdir -p "$FAKE_HOME/.claude" "$NO_GIT"
PREV_PWD="$PWD"

# /tmp itself must not sit inside a repository, otherwise "no git" is a lie and
# the suite would pass while the bug is still there.
if git -C "$NO_GIT" rev-parse --git-dir >/dev/null 2>&1; then
    log_fail "test fixture" "$NO_GIT is inside a git repository, cannot assert the no-git path"
    cd "$PREV_PWD"
    rm -rf "$WORK"
    test_summary
fi

echo "=== Injected !\`...\` patterns survive a directory without git ==="

FOUND=0
while IFS= read -r line; do
    file="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"

    while IFS= read -r raw; do
        [[ -z "$raw" ]] && continue
        cmd="${raw#\!\`}"
        cmd="${cmd%\`}"
        FOUND=$((FOUND + 1))

        # Run it the way the harness does: a plain shell, in the user's cwd.
        # HOME is faked so a missing codemap and a missing metrics database are
        # part of the test rather than an accident of the developer's machine.
        (cd "$NO_GIT" && HOME="$FAKE_HOME" bash -c "$cmd") >/dev/null 2>&1
        status=$?

        rel="${file#"$ROOT_DIR"/}"
        assert_exit_code "$rel:$lineno exits 0 without git" 0 "$status"
    done < <(grep -o '!`[^`]*`' <<< "$rest" || true)
done < <(grep -rn '!`[^`]*`' "$ROOT_DIR/skills" --include='SKILL.md' 2>/dev/null || true)

if [[ "$FOUND" -gt 0 ]]; then
    log_pass "found $FOUND injected pattern(s) to check"
else
    log_fail "pattern discovery" "no !\`...\` pattern found under skills/, the extractor is broken"
fi

cd "$PREV_PWD"
# =============================================================================
# craftsman-context: the explicit collector, for hosts that do not expand
# !`...` (audit CR-117, C7). Each source carries its status and the revision.
# =============================================================================
echo ""
echo "=== craftsman-context review ==="
CTX="$ROOT_DIR/bin/craftsman-context"
CTX_HOME="$WORK/ctx-home"; mkdir -p "$CTX_HOME/.claude"
# no git, no metrics: every source says so, exit 0
OUT=$(cd "$NO_GIT" && HOME="$CTX_HOME" CLAUDE_PLUGIN_DATA="$WORK/ctx-empty-data" bash "$CTX" review 2>&1); RC=$?
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q '^## Live Context (collected .*revision no-git' \
    && printf '%s' "$OUT" | grep -q '^### Changed hunks \[missing\]: not a git repository' \
    && printf '%s' "$OUT" | grep -q '^### Top violations (7 days) \[missing\]'; then
    log_pass "outside git with no metrics: revision no-git, hunks and history missing, violations missing, exit 0"
else
    log_fail "collector outside git" "rc=$RC $(printf '%s' "$OUT" | grep '^###' | tr '\n' '|')"
fi
# a repository with a change: hunks available, revision named
CTX_REPO="$WORK/ctx-repo"; mkdir -p "$CTX_REPO/src"
( cd "$CTX_REPO" && git init -q . && printf 'a\n' > src/a.ts && git add -A && git commit -qm base && printf 'b\n' >> src/a.ts )
SHA=$(cd "$CTX_REPO" && git rev-parse --short HEAD)
OUT=$(cd "$CTX_REPO" && HOME="$CTX_HOME" CLAUDE_PLUGIN_DATA="$WORK/ctx-empty-data" bash "$CTX" review 2>&1); RC=$?
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q "revision $SHA (working tree dirty)" \
    && printf '%s' "$OUT" | grep -q '^### Changed hunks \[available\]' && printf '%s' "$OUT" | grep -q '^+b$' \
    && printf '%s' "$OUT" | grep -q '^### Recent commits \[available\]'; then
    log_pass "in a dirty repository: the revision and the dirty flag are named, the hunk is delivered"
else
    log_fail "collector in a repo" "rc=$RC $(printf '%s' "$OUT" | grep '^##' | tr '\n' '|')"
fi
# a clean repository: empty is empty, not missing
( cd "$CTX_REPO" && git checkout -q -- . )
OUT=$(cd "$CTX_REPO" && HOME="$CTX_HOME" CLAUDE_PLUGIN_DATA="$WORK/ctx-empty-data" bash "$CTX" review 2>&1)
if printf '%s' "$OUT" | grep -q '^### Changed hunks \[empty\]'; then
    log_pass "a clean repository reports its hunks as empty, not missing"
else
    log_fail "collector clean repo" "$(printf '%s' "$OUT" | grep '^### Changed' )"
fi
# a diff longer than the 400-line window is still available (the producer is
# drained; head closed the pipe and pipefail read SIGPIPE as failed, review F3)
( cd "$CTX_REPO" && for i in $(seq 1 3000); do echo "line $i"; done > src/big.ts && git add src/big.ts && git commit -qm big && for i in $(seq 1 3000); do echo "changed $i"; done > src/big.ts )
OUT=$(cd "$CTX_REPO" && HOME="$CTX_HOME" CLAUDE_PLUGIN_DATA="$WORK/ctx-empty-data" bash "$CTX" review 2>&1)
if printf '%s' "$OUT" | grep -q '^### Changed hunks \[available\]' && [[ "$(printf '%s' "$OUT" | grep -c '^[-+]changed\|^[-+]line')" -le 400 ]]; then
    log_pass "a 6000-line diff is delivered as available and truncated to the window, not read as failed"
else
    log_fail "large diff" "$(printf '%s' "$OUT" | grep '^### Changed')"
fi
( cd "$CTX_REPO" && git checkout -q -- . )
# a broken helper is failed, not silently absent
CTX_COPY="$WORK/ctx-plugin"; mkdir -p "$CTX_COPY/bin" "$CTX_COPY/hooks/lib"
cp "$CTX" "$CTX_COPY/bin/craftsman-context"; printf 'import sys\nsys.exit(3)\n' > "$CTX_COPY/hooks/lib/codemap.py"
OUT=$(cd "$CTX_REPO" && HOME="$CTX_HOME" CLAUDE_PLUGIN_DATA="$WORK/ctx-empty-data" bash "$CTX_COPY/bin/craftsman-context" review 2>&1); RC=$?
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -qE '^### Codemap \[(failed|empty)\]'; then
    log_pass "a codemap helper that exits non-zero is reported failed or empty, and the collector still exits 0"
else
    log_fail "collector broken helper" "rc=$RC $(printf '%s' "$OUT" | grep '^### Codemap')"
fi
# the helper is this installation's, not ~/.claude's
if grep -q 'PLUGIN_ROOT/hooks/lib/codemap.py' "$CTX" && ! grep -q 'craftsman-codemap.sh' "$CTX"; then
    log_pass "the collector resolves codemap.py from its own installation, never from the ~/.claude wrapper"
else
    log_fail "collector helper resolution" "reads ~/.claude"
fi
# the skill tells every host to run it before reviewing
if grep -q 'craftsman-context review' "$ROOT_DIR/skills/challenge/SKILL.md"; then
    log_pass "the challenge skill names craftsman-context review as its first step"
else
    log_fail "challenge skill" "does not name the collector"
fi

rm -rf "$WORK"

test_summary
