#!/usr/bin/env bash
# =============================================================================
# CR-226: the PHP001 auto-fix never writes a file PHP refuses to compile.
#
# Measured 2026-10-18 on Claude Code 2.1.294: a Write whose first line is
# `<?php echo 1;` came back with declare(strict_types=1) inserted AFTER that
# line, and PHP rejects it ("strict_types declaration must be the very first
# statement"). The judge is PHP itself (`php -l`) when it is installed; the
# structural assertion holds on hosts without it.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-php001-autofix-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-php001-autofix.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT
mkdir -p "$WORK/src"
cd "$WORK" && git init -q .

GATE_RC=0
FIXED=""
_gate() {
    local out
    GATE_RC=0
    out=$(python3 -c '
import json, sys
print(json.dumps({"session_id": "s226", "hook_event_name": "PreToolUse", "tool_name": "Write", "cwd": sys.argv[3],
                  "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' \
        "$WORK/src/Order.php" "$1" "$WORK" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>/dev/null) || GATE_RC=$?
    FIXED=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.content // empty' 2>/dev/null)
}

_php_accepts() {
    command -v php >/dev/null 2>&1 || return 0
    printf '%s\n' "$1" > "$WORK/lint.php"
    php -l "$WORK/lint.php" >/dev/null 2>&1
}

expect_fixed() {
    local label="$1" content="$2" kept="$3"
    _gate "$content"
    if [[ "$GATE_RC" -eq 0 && "$FIXED" == "<?php"$'\n\n'"declare(strict_types=1);"* && "$FIXED" == *"$kept"* ]] \
        && _php_accepts "$FIXED"; then
        log_pass "$label: declare(strict_types=1) is the first statement and the code is kept"
    else
        log_fail "$label" "rc=$GATE_RC fixed=$(printf '%s' "$FIXED" | tr '\n' '|')"
    fi
}

echo ""
echo "--- PHP001 auto-fix (pre-write) ---"
command -v php >/dev/null 2>&1 || echo "  (php not on PATH: structural assertions only)"

expect_fixed "opening tag alone" $'<?php\n\nfinal class Order\n{\n}' "final class Order"
expect_fixed "code on the opening line" $'<?php echo 1;' "echo 1;"
expect_fixed "namespace on the opening line" $'<?php namespace App\\Domain;\n\nfinal class Order\n{\n}' $'namespace App\\Domain;\n\nfinal class Order'

_gate $'<?phpx\n\nfinal class Order\n{\n}'
if [[ "$GATE_RC" -eq 2 && -z "$FIXED" ]]; then
    log_pass "no opening tag (<?phpx): no rewrite, PHP001 refuses"
else
    log_fail "malformed opening tag" "rc=$GATE_RC fixed=$(printf '%s' "$FIXED" | tr '\n' '|')"
fi

test_summary
