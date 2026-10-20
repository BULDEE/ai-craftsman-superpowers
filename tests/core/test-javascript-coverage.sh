#!/usr/bin/env bash
# =============================================================================
# CR-231: JavaScript gets the craftsman rules, native JS and jQuery included.
#
# Measured 2026-10-18: src/domain/order.js importing ../infrastructure/db was
# written with no rule at all (rc=0) while the same file as .ts was refused
# with LAYER001. Design: "50-Backlog/Design - CR-231 couverture JavaScript"
# (vault). Every case runs through the real pre-write gate; the parity cases
# also run through ci/craftsman-ci.sh.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-js-coverage-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-js-coverage.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT
mkdir -p "$WORK/src/domain" "$WORK/src/ui" "$WORK/src/infrastructure"
cd "$WORK" && git init -q . && printf '{"name":"fixture"}\n' > package.json

GATE_RC=0
GATE_OUT=""
_registry() {
    bash -c "cd '$WORK'; source '$ROOT_DIR/hooks/lib/config.sh'; source '$ROOT_DIR/hooks/lib/pack-loader.sh'; pack_loader_init >/dev/null 2>&1; $1" 2>/dev/null
}

# Results travel back through GATE_RC and GATE_OUT, read by the expect_* helpers.
# craftsman-ignore: WARN-SH001
_gate() {
    GATE_RC=0
    GATE_OUT=$(python3 -c '
import json, sys
print(json.dumps({"session_id": "s231", "hook_event_name": "PreToolUse", "tool_name": "Write", "cwd": sys.argv[3],
                  "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' \
        "$WORK/$1" "$2" "$WORK" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1) || GATE_RC=$?
}

expect_block() {
    local rule="$1" path="$2" content="$3"
    _gate "$path" "$content"
    if [[ "$GATE_RC" -eq 2 && "$GATE_OUT" == *"$rule"* ]]; then
        log_pass "$rule refuses $path"
    else
        log_fail "$rule on $path" "rc=$GATE_RC out=$(printf '%s' "$GATE_OUT" | tr '\n' ' ' | cut -c1-160)"
    fi
}

expect_pass() {
    local path="$1" content="$2"
    _gate "$path" "$content"
    if [[ "$GATE_RC" -eq 0 ]]; then
        log_pass "control: $path is written"
    else
        log_fail "control $path refused" "rc=$GATE_RC out=$(printf '%s' "$GATE_OUT" | tr '\n' ' ' | cut -c1-160)"
    fi
}

expect_absent() {
    local rule="$1" path="$2" content="$3"
    _gate "$path" "$content"
    if [[ "$GATE_OUT" != *"$rule"* ]]; then
        log_pass "$rule never fires on $path"
    else
        log_fail "$rule fired on $path" "$(printf '%s' "$GATE_OUT" | tr '\n' ' ' | cut -c1-160)"
    fi
}

expect_ci() {
    local rule="$1" path="$2" content="$3" found
    printf '%s\n' "$content" > "$WORK/$path"
    found=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" --format json "$path" 2>/dev/null \
        | python3 -c 'import json, sys; print(" ".join(v.get("rule", "") for v in json.load(sys.stdin).get("violations") or []))' 2>/dev/null)
    rm -f "$WORK/$path"
    if [[ " $found " == *" $rule "* ]]; then
        log_pass "parity: CI reports $rule on $path"
    else
        log_fail "CI parity $rule on $path" "ci=[$found]"
    fi
}

echo ""
echo "--- every JavaScript extension is a language ---"
RESOLVED=$(_registry 'for e in js jsx mjs cjs; do printf "%s " "$(lang_for_file x.$e)"; done')
if [[ "$RESOLVED" == "javascript javascript javascript javascript " ]]; then
    log_pass "js, jsx, mjs and cjs resolve to javascript"
else
    log_fail "extension resolution" "got [$RESOLVED]"
fi

echo ""
echo "--- LAYER001: the domain does not reach into infrastructure ---"
expect_block LAYER001 "src/domain/control.ts" "import { db } from '../infrastructure/db';"
expect_pass  "src/domain/order.js" "export const total = (lines) => lines.reduce((sum, line) => sum + line.amount, 0);"
expect_block LAYER001 "src/domain/order.js"  "import { db } from '../infrastructure/db';"
expect_block LAYER001 "src/domain/order.jsx" "import { db } from '../infrastructure/db';"
expect_block LAYER001 "src/domain/order.mjs" "const { db } = await import('../infrastructure/db.mjs');"
expect_block LAYER001 "src/domain/order.cjs" "const db = require('../infrastructure/db');"
expect_block LAYER001 "src/domain/order.ts"  "const db = require('../infrastructure/db');"

echo ""
echo "--- LAYER004, SEC002, SEC003 in JavaScript ---"
expect_block LAYER004 "src/domain/repository.js"  "import { Pool } from 'pg';"
expect_block LAYER004 "src/domain/repository.cjs" "const { Pool } = require('pg');"
expect_block SEC002 "src/ui/calc.js" "export const run = (formula) => eval(formula);"
expect_block SEC003 "src/infrastructure/users.js" 'export const find = (db, req) => db.query(`SELECT name FROM users WHERE id = ${req.query.id}`);'

echo ""
echo "--- SEC004: an HTML sink never takes an unescaped value ---"
expect_block SEC004 "src/ui/comment.js"  'el.innerHTML = `<p>${comment}</p>`;'
expect_block SEC004 "src/ui/comment.js"  "el.innerHTML = '<p>' + comment + '</p>';"
expect_block SEC004 "src/ui/comment.js"  "el.innerHTML = comment;"
expect_block SEC004 "src/ui/comment.js"  "el.outerHTML = comment;"
expect_block SEC004 "src/ui/comment.js"  "document.write(comment);"
expect_block SEC004 "src/ui/comment.js"  "el.insertAdjacentHTML('beforeend', comment);"
expect_block SEC004 "src/ui/legacy.js"   "\$('#comments').html(comment);"
expect_block SEC004 "src/ui/legacy.js"   "\$('#comments').append('<li>' + comment + '</li>');"
expect_block SEC004 "src/ui/Comment.jsx" "export const Comment = ({ body }) => <div dangerouslySetInnerHTML={{ __html: body }} />;"
expect_block SEC004 "src/ui/Comment.tsx" "export const Comment = ({ body }: { body: string }) => <div dangerouslySetInnerHTML={{ __html: body }} />;"
expect_block SEC004 "src/ui/comment.ts"  'el.innerHTML = `<p>${comment}</p>`;'
expect_pass "src/ui/loading.js"  "el.innerHTML = '<p>Loading</p>';"
expect_pass "src/ui/legacy.js"   "\$('#status').html('<b>ok</b>');"
expect_pass "src/ui/comment.js"  "el.innerHTML = DOMPurify.sanitize(comment);"
expect_pass "src/ui/Comment.jsx" "export const Comment = ({ body }) => <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(body) }} />;"

echo ""
echo "--- TypeScript-only rules stay out of JavaScript, secrets do not (CR-257) ---"
expect_absent TS001 "src/ui/schema.js" "const any = 1; export const schema = { field: any };"
expect_absent TS003 "src/ui/guard.js" "export const present = (user) => user !== null && !user.deleted;"
# Assembled at run time so the repository never holds a key-shaped literal
# (GitHub push protection refuses one, fake or not).
FAKE_KEY="sk_""live_51HxQ$(printf 'a%.0s' {1..24})"
expect_block SEC001 "src/ui/pay.ts" "const stripe = \"$FAKE_KEY\";"
expect_block SEC001 "src/ui/pay.js" "const stripe = \"$FAKE_KEY\";"

echo ""
echo "--- the agent cannot lower a JavaScript project's bar ---"
PROTECTED=$(_registry 'for l in typescript javascript; do lang_capability $l protected_configs | sort | tr "\n" " "; echo; done')
TS_LIST=$(printf '%s\n' "$PROTECTED" | sed -n 1p)
JS_LIST=$(printf '%s\n' "$PROTECTED" | sed -n 2p)
if [[ -n "$JS_LIST" && "$TS_LIST" == "$JS_LIST" ]]; then
    log_pass "javascript protects the same linter and dependency configs as typescript"
else
    log_fail "protected_configs drift" "ts=[$TS_LIST] js=[$JS_LIST]"
fi

echo ""
echo "--- hooks and CI agree ---"
expect_ci LAYER001 "src/domain/order.cjs" "const db = require('../infrastructure/db');"
expect_ci SEC004 "src/ui/legacy.js" "\$('#comments').html(comment);"

test_summary
