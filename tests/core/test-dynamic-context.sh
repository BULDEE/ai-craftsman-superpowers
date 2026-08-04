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
rm -rf "$WORK"

test_summary
