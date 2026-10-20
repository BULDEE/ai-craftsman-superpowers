#!/usr/bin/env bash
# =============================================================================
# CR-257: SEC001 knows today's credential shapes, in every pack.
#
# Measured 2026-10-20: `const value = "sk-proj-..."` and an Anthropic key were
# written to a .ts file with no finding, while the repository's own secrets
# scanner already knew both prefixes. A .js or .py file got no SEC001 at all.
# The shapes now live in one list (hooks/lib/secret-patterns.sh); this test
# checks the list on its own, then each language through the real pre-write
# gate and ci/craftsman-ci.sh.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-secret-shapes-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE
mkdir -p "$CLAUDE_PLUGIN_DATA"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-secret-shapes.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT
mkdir -p "$WORK/src/ui" "$WORK/src/app" "$WORK/src/Infrastructure"
cd "$WORK" && git init -q . \
    && printf '{"name":"fixture"}\n' > package.json \
    && printf '{"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json \
    && printf '[project]\nname = "fixture"\n' > pyproject.toml

# Every key below is assembled at run time, so the repository never holds a
# key-shaped literal (GitHub push protection refuses one, fake or not).
BODY="a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8s9T0u1V2w3Y4y5Z6"
HEX="0f3a9c27b1d84e6a5c09f7e2d13b8a46"
ANTHROPIC="sk-""ant-api03-${BODY:0:40}"
OPENAI_PROJECT="sk-""proj-${BODY:0:40}"
OPENAI_SERVICE="sk-""svcacct-${BODY:0:40}"
OPENAI_LEGACY="sk-""${BODY:0:48}"
GITLAB="glp""at-${BODY:0:20}"
NPM="np""m_${BODY:0:36}"
SLACK_HOOK="https://hooks.sla""ck.com/services/T0A1B2C3D/B0A1B2C3D/${BODY:0:24}"
GITHUB_SERVER="gh""s_${BODY:0:36}"
STRIPE_RESTRICTED="rk_""live_${BODY:0:24}"
AWS_TEMPORARY="AS""IA7Q2W4E6R8T0Y1U3I"
STRIPE_LIVE="sk_""live_51HxQ${BODY:0:24}"

echo ""
echo "--- the shapes, one list for every pack ---"
_shape() {
    # shellcheck source=/dev/null
    (source "$ROOT_DIR/hooks/lib/secret-patterns.sh" 2>/dev/null && printf '1:%s\n' "$1" | secret_hits "${2:-}")
}
expect_shape() {
    local label="$1" line="$2" runtime="${3:-}"
    if [[ -n "$(_shape "$line" "$runtime")" ]]; then log_pass "shape: $label"; else log_fail "shape: $label" "silent on: $line"; fi
}
expect_no_shape() {
    local label="$1" line="$2" runtime="${3:-}"
    if [[ -z "$(_shape "$line" "$runtime")" && -f "$ROOT_DIR/hooks/lib/secret-patterns.sh" ]]; then
        log_pass "control: $label"
    else
        log_fail "control: $label" "flagged: $line"
    fi
}

expect_shape "Anthropic key"            "const value = \"$ANTHROPIC\";"
expect_shape "OpenAI project key"       "const value = \"$OPENAI_PROJECT\";"
expect_shape "OpenAI service key"       "const value = \"$OPENAI_SERVICE\";"
expect_shape "OpenAI legacy key"        "const value = \"$OPENAI_LEGACY\";"
expect_shape "GitLab token"             "const value = \"$GITLAB\";"
expect_shape "npm token"                "const value = \"$NPM\";"
expect_shape "Slack webhook"            "const value = \"$SLACK_HOOK\";"
expect_shape "GitHub server token"      "const value = \"$GITHUB_SERVER\";"
expect_shape "Stripe restricted key"    "const value = \"$STRIPE_RESTRICTED\";"
expect_shape "AWS temporary key id"     "const value = \"$AWS_TEMPORARY\";"
expect_shape "a *_KEY constant"         "const DATADOG_KEY = \"$HEX\";"
expect_shape "a typed *_TOKEN"          "API_TOKEN: str = \"${BODY:0:24}\""
expect_shape "a typed apiKey"           "const apiKey: string = \"${BODY:0:24}\";"
expect_shape "kept: Stripe live key"    "const value = \"$STRIPE_LIVE\";"
expect_shape "kept: private key block"  "-----BEGIN RSA PRIVATE KEY-----"
expect_shape "kept: named password"     "\$password = \"hunter2secret\";"
expect_shape "an issued key as an env fallback" "const value = process.env.KEY ?? \"$ANTHROPIC\";" 'process\.env'

expect_no_shape "an id that ends in sk-"    "const taskId = \"task-${BODY:0:40}\";"
expect_no_shape "a CSS class"               "<div className=\"sk-loading-skeleton-wrapper-container\" />"
expect_no_shape "a storage key"             "const STORAGE_KEY = \"craftsman.cockpit.theme\";"
expect_no_shape "a short storage key"       "const LOCAL_STORAGE_KEY = \"app-preferences-v2\";"
expect_no_shape "a time zone"               "timezone = \"Asia/Kolkata\""
expect_no_shape "a lowercase region id"     "region = \"asiapacificsoutheast1\""
expect_no_shape "an npm config name"        "const name = \"npm_config_registry\";"
expect_no_shape "a documented key"          "const value = \"sk-""proj-YOUR_KEY_HERE_${BODY:0:20}\";"
expect_no_shape "Slack's own example"       "url = \"https://hooks.sla""ck.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX\""
expect_no_shape "a named value beside a runtime read" "api_token = \"fallback1234567\" if DEBUG else os.environ[\"API_TOKEN\"]" 'os\.environ'

echo ""
echo "--- one list: no pack keeps a copy of the issuer prefixes ---"
COPIES=$(grep -lE 'sk_live|github_pat_|AKIA' "$ROOT_DIR"/packs/*/hooks/*.sh 2>/dev/null)
if [[ -z "$COPIES" ]]; then
    log_pass "the issuer prefixes live in hooks/lib/secret-patterns.sh only"
else
    log_fail "a pack keeps its own prefix list" "$(printf '%s' "$COPIES" | tr '\n' ' ')"
fi

GATE_RC=0
GATE_OUT=""
# Results travel back through GATE_RC and GATE_OUT, read by the expect_* helpers.
# craftsman-ignore: WARN-SH001
_gate() {
    GATE_RC=0
    GATE_OUT=$(python3 -c '
import json, sys
print(json.dumps({"session_id": "s257", "hook_event_name": "PreToolUse", "tool_name": "Write", "cwd": sys.argv[3],
                  "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' \
        "$WORK/$1" "$2" "$WORK" | bash "$ROOT_DIR/hooks/pre-write-check.sh" 2>&1) || GATE_RC=$?
}

expect_block() {
    local path="$1" content="$2"
    _gate "$path" "$content"
    if [[ "$GATE_RC" -eq 2 && "$GATE_OUT" == *SEC001* ]]; then
        log_pass "SEC001 refuses $path"
    else
        log_fail "SEC001 on $path" "rc=$GATE_RC out=$(printf '%s' "$GATE_OUT" | tr '\n' ' ' | cut -c1-160)"
    fi
}

expect_absent() {
    local path="$1" content="$2"
    _gate "$path" "$content"
    if [[ "$GATE_OUT" != *SEC001* ]]; then
        log_pass "control: no SEC001 on $path"
    else
        log_fail "SEC001 fired on $path" "$(printf '%s' "$GATE_OUT" | tr '\n' ' ' | cut -c1-160)"
    fi
}

expect_ci() {
    local path="$1" content="$2" found
    printf '%s\n' "$content" > "$WORK/$path"
    found=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" --format json "$path" 2>/dev/null \
        | python3 -c 'import json, sys; print(" ".join(v.get("rule", "") for v in json.load(sys.stdin).get("violations") or []))' 2>/dev/null)
    rm -f "$WORK/$path"
    if [[ " $found " == *" SEC001 "* ]]; then
        log_pass "parity: CI reports SEC001 on $path"
    else
        log_fail "CI parity SEC001 on $path" "ci=[$found]"
    fi
}

TS_LINE="export const client = \"$ANTHROPIC\";"
PHP_FILE=$(printf '<?php\n\ndeclare(strict_types=1);\n\nfinal class Billing\n{\n    private const CLIENT = '"'"'%s'"'"';\n}\n' "$OPENAI_PROJECT")
PY_LINE="client_value = \"$ANTHROPIC\""

echo ""
echo "--- every language, through the real gate ---"
# Known-good control: a shape SEC001 caught before CR-257, so a silent gate
# below means the shapes, not the wiring.
expect_block "src/ui/pay.ts" "const stripe = \"$STRIPE_LIVE\";"
expect_block "src/ui/client.ts" "$TS_LINE"
expect_block "src/ui/client.js" "$TS_LINE"
expect_block "src/Infrastructure/Billing.php" "$PHP_FILE"
expect_block "src/app/client.py" "$PY_LINE"
expect_absent "src/app/settings.py" 'api_token = "fallback1234567" if DEBUG else os.environ["API_TOKEN"]'
expect_absent "src/ui/settings.js" 'export const client = process.env.ANTHROPIC_API_KEY;'

echo ""
echo "--- hooks and CI agree ---"
expect_ci "src/ui/client.ts" "$TS_LINE"
expect_ci "src/ui/client.js" "$TS_LINE"
expect_ci "src/Infrastructure/Billing.php" "$PHP_FILE"
expect_ci "src/app/client.py" "$PY_LINE"

test_summary
