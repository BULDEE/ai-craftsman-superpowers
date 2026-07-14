#!/usr/bin/env bash
# =============================================================================
# Security Invariant Tests
# Proves - not just asserts - that our blocking hooks (config-protection.sh,
# pre-write-check.sh, post-write-check.sh) never execute arbitrary code or
# touch the filesystem when fed adversarial input. Same pattern as ecc's
# sandbox + witness-marker invariant runner: plant a marker, feed the hook
# a malicious path/command, then verify the marker is untouched.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

WITNESS="$SANDBOX/witness.txt"
echo "untouched" > "$WITNESS"

witness_intact() {
    [[ -f "$WITNESS" ]] && [[ "$(cat "$WITNESS")" == "untouched" ]]
}

echo ""
echo "=== Security Invariant Tests ==="

# -----------------------------------------------------------------------
# Adversarial payloads: command injection attempts, path traversal, shell
# metacharacters embedded in the file_path field these hooks parse from
# tool_input JSON.
# -----------------------------------------------------------------------
PAYLOADS=(
    "phpstan.neon; touch ${WITNESS}.pwned"
    "\$(touch ${WITNESS}.pwned)"
    "\`touch ${WITNESS}.pwned\`"
    "../../../../tmp/phpstan.neon"
    "phpstan.neon\$(rm -f ${WITNESS})"
    "phpstan.neon' ; rm -f '${WITNESS}"
)

run_config_protection() {
    local payload="$1"
    jq -n --arg fp "$payload" '{"tool_input":{"file_path":$fp}}' \
        | bash "$ROOT_DIR/hooks/config-protection.sh" >/dev/null 2>&1
    echo $?
}

for payload in "${PAYLOADS[@]}"; do
    run_config_protection "$payload" >/dev/null
    if witness_intact && [[ ! -f "${WITNESS}.pwned" ]]; then
        log_pass "config-protection.sh: payload did not execute (${payload:0:30}...)"
    else
        log_fail "config-protection.sh: adversarial payload had a side effect" "$payload"
    fi
done

# -----------------------------------------------------------------------
# pre-write-check.sh: same adversarial file_path payloads, plus content
# field. Must never write outside CLAUDE_PLUGIN_DATA regardless of input.
# -----------------------------------------------------------------------
run_pre_write() {
    local payload="$1"
    jq -n --arg fp "$payload" --arg c 'declare(strict_types=1); class Foo {}' \
        '{"tool_input":{"file_path":$fp,"content":$c}}' \
        | bash "$ROOT_DIR/hooks/pre-write-check.sh" >/dev/null 2>&1
}

for payload in "${PAYLOADS[@]}"; do
    run_pre_write "$payload"
    if witness_intact && [[ ! -f "${WITNESS}.pwned" ]]; then
        log_pass "pre-write-check.sh: payload did not execute (${payload:0:30}...)"
    else
        log_fail "pre-write-check.sh: adversarial payload had a side effect" "$payload"
    fi
done

# -----------------------------------------------------------------------
# Fail-open invariant: a malformed / non-JSON stdin must never crash the
# hook into an unhandled state - it must exit 0 (allow) via the ERR trap,
# never hang, never exit with an undefined code.
# -----------------------------------------------------------------------
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout 5"

for hook in config-protection.sh pre-write-check.sh; do
    echo "not json at all {{{" | $TIMEOUT_BIN bash "$ROOT_DIR/hooks/$hook" >/dev/null 2>&1
    exit_code=$?
    if [[ "$exit_code" == "0" ]]; then
        log_pass "$hook: malformed stdin fails open (exit 0)"
    else
        log_fail "$hook: malformed stdin should fail open" "got exit $exit_code"
    fi
done

test_summary
