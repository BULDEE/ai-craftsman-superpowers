#!/usr/bin/env bash
# =============================================================================
# One PHP write, one verdict (CR-314).
#
# Measured on Grok 1.0.62 (2026-11-17, again on 4.18.0 on 2026-11-18):
# `<?php class Bad {}` was allowed before the write, with the PHP001 auto-fix
# in updated_input, and blocked after it on PHP002. PHP002 only looked for
# `class` at the start of a line, and the fix moves the code that shares the
# opening line below the declare, where the post-write found it. Two verdicts
# for one write: the model reads "allowed", then "BLOCKED" for code it never
# changed.
#
# Two parts: PHP002 sees a class declared after code on its line, and the
# pre-write judges the content as it will land, auto-fix applied, so a rule
# anchored on the line start (a project's own rule here) agrees with the
# post-write.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-php-one-verdict.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_PLUGIN_ROOT="$ROOT_DIR" CLAUDE_PLUGIN_DATA="$WORK/data"
export CRAFTSMAN_RUNTIME_HOME="$WORK/home"
export CLAUDE_PLUGIN_OPTION_stack="fullstack" CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDE_CODE_SESSION_ID CRAFTSMAN_SESSION_ID \
    GROK_SESSION_ID GROK_HOOK_EVENT GROK_PLUGIN_ROOT GROK_WORKSPACE_ROOT CRAFTSMAN_EXPORTED_GATE
PROJECT="$WORK/project"
mkdir -p "$HOME/.claude" "$CLAUDE_PLUGIN_DATA" "$PROJECT/src"
(cd "$PROJECT" && git init -q .)
TARGET="$PROJECT/src/Bad.php"

PRE_RC=0
PRE_OUT=""
LANDED=""
_pre() { # <content>: PRE_RC, PRE_OUT (stdout and stderr), LANDED (what the host writes)
    PRE_RC=0
    local payload
    payload=$(jq -n --arg f "$TARGET" --arg c "$1" --arg cwd "$PROJECT" \
        '{session_id: "s314", hook_event_name: "PreToolUse", tool_name: "Write", cwd: $cwd,
          tool_input: {file_path: $f, content: $c}}')
    PRE_OUT=$(cd "$PROJECT" && printf '%s' "$payload" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1) || PRE_RC=$?
    LANDED=$(printf '%s' "$PRE_OUT" | jq -rs '[.[] | objects | .hookSpecificOutput.updatedInput.content // empty][0] // empty' 2>/dev/null)
    [[ -n "$LANDED" ]] || LANDED="$1"
}

POST_RC=0
_post() { # lands LANDED on disk and runs the post-write on it: POST_RC
    POST_RC=0
    printf '%s\n' "$LANDED" > "$TARGET"
    (cd "$PROJECT" && jq -n --arg f "$TARGET" --arg cwd "$PROJECT" \
        '{session_id: "s314", hook_event_name: "PostToolUse", tool_name: "Write", cwd: $cwd, tool_input: {file_path: $f}}' \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1) || POST_RC=$?
    rm -f "$TARGET"
}

expect_refused() { # <label> <rule> <content>
    _pre "$3"
    if [[ "$PRE_RC" -eq 2 && "$PRE_OUT" == *"$2"* ]]; then
        log_pass "$1: refused before the write on $2"
    else
        log_fail "$1" "pre-write rc=$PRE_RC, $2 not named before the write: $(printf '%s' "$PRE_OUT" | head -c 300 | tr '\n' '|')"
    fi
}

expect_one_verdict() { # <label> <content>: allowed before, not blocked after
    _pre "$2"
    _post
    if [[ "$PRE_RC" -eq 0 && "$POST_RC" -eq 0 ]]; then
        log_pass "$1: allowed before the write and not blocked after it"
    else
        log_fail "$1" "pre-write rc=$PRE_RC, post-write rc=$POST_RC on what landed: $(printf '%s' "$LANDED" | tr '\n' '|')"
    fi
}

echo ""
echo "=== A class declared on the opening line is not final: refused before the write ==="
expect_refused "one line, no declare" "PHP002" '<?php class Bad {}'
expect_refused "body below, no declare" "PHP002" $'<?php class Bad\n{\n}'
expect_refused "one line, with declare" "PHP002" '<?php declare(strict_types=1); class Bad {}'
expect_refused "body below, with declare" "PHP002" $'<?php declare(strict_types=1); class Bad\n{\n}'
expect_refused "after a namespace on its line" "PHP002" $'<?php\n\ndeclare(strict_types=1);\n\nnamespace App; class Bad\n{\n}'

echo ""
echo "=== What PHP002 leaves alone, on the same line ==="
expect_one_verdict "final class on the opening line" '<?php final class Good {}'
expect_one_verdict "abstract class on the opening line" '<?php abstract class Base {}'
expect_one_verdict "interface on the opening line" '<?php interface Port {}'
expect_one_verdict "::class and an anonymous class" \
    $'<?php\n\ndeclare(strict_types=1);\n\nfinal class Good\n{\n    public function f(): object { $n = self::class; return new class {}; }\n}'

echo ""
echo "=== The pre-write judges the content as it lands, auto-fix applied ==="
# A project rule anchored on the line start: only the fixed content, where the
# `use` the opening line carried starts its own line, matches it.
cat > "$PROJECT/.craft-config.yml" <<'YAML'
version: "2.1"
strictness: strict
stack: fullstack
rules:
  CUSTOM314:
    pattern: "^use App\\\\Legacy"
    message: "No App\\Legacy import"
    severity: block
    languages: [php]
YAML
expect_refused "a line-start rule the fix exposes" "CUSTOM314" $'<?php use App\\Legacy\\Mailer;\n\nfinal class Good\n{\n}'
LANDED=$'<?php\n\ndeclare(strict_types=1);\n\nuse App\\Legacy\\Mailer;\n\nfinal class Good\n{\n}'
_post
assert_exit_code "control: the post-write blocks that content as the fix lands it" 2 "$POST_RC"
expect_one_verdict "the same file without the import is still auto-fixed" $'<?php\n\nfinal class Good\n{\n}'
rm -f "$PROJECT/.craft-config.yml"

test_summary
