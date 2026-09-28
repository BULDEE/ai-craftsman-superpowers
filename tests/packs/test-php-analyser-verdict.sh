#!/usr/bin/env bash
# =============================================================================
# The PHP analysers give a verdict or say they gave none.
#
# ESLint, dependency-cruiser, errcheck and clippy report a crash or a stopped
# run as ANALYSER001 since 4.12.2 (CR-174). PHPStan and deptrac kept the old
# pattern: `|| true` flattened the status, an empty output returned early, and
# a fatal error or a run the budget stopped left the gate exactly as silent as
# a clean file (CR-212).
#
# Coverage is NOT declared on a clean deptrac run, on purpose. An exit 0 with
# nothing printed is also what a depfile that does not cover the boundary
# produces, and an analyser configured to ignore a rule ends with the regex
# reporting (CLAUDE.md, supersedes). tests/packs/test-deptrac-layers.sh group C
# holds that direction.
#
# The stubs read their behaviour from a mode file, so the hook and the
# pipeline run exactly the binary the adapter resolves. The slow mode execs
# its sleep: the budget stops the process it started, and a grandchild holding
# stdout open would measure the fallback timeout, not the adapter.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
setup_test_env
backup_home_bridges

TMPDIR_BASE="/tmp/craftsman-php-verdict-$$"
mkdir -p "$TMPDIR_BASE/project"
PROJECT_DIR=$(cd "$TMPDIR_BASE/project" && pwd -P)
SRC_DIR="$PROJECT_DIR/src"
BIN_DIR="$PROJECT_DIR/vendor/bin"
mkdir -p "$SRC_DIR/Domain" "$SRC_DIR/Presentation" "$BIN_DIR"

_ORIG_HOME="$HOME"
export HOME="$TMPDIR_BASE/home"
mkdir -p "$HOME/.claude"

trust_tools() {
    printf 'stack: fullstack\ntrust_project_tools: %s\n' "$1" > "$HOME/.claude/.craft-config.yml"
}

cleanup() {
    cd "$ROOT_DIR" || true
    export HOME="$_ORIG_HOME"
    restore_home_bridges
    cleanup_test_env
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

echo "=== PHP Level 2/3 verdicts ==="

cat > "$PROJECT_DIR/composer.json" <<'JSON'
{ "name": "craftsman/php-verdict-fixture", "autoload": { "psr-4": { "App\\": "src/" } } }
JSON

# Compliant on every Level 1 rule, so anything in the output came from an
# analyser.
cat > "$SRC_DIR/Domain/Ledger.php" <<'PHP'
<?php

declare(strict_types=1);

namespace App\Domain;

final class Ledger
{
    private function __construct()
    {
    }
}
PHP
LEDGER="$SRC_DIR/Domain/Ledger.php"

MODE_FILE="$PROJECT_DIR/.analyser-mode"
ARGV_LOG="$TMPDIR_BASE/argv.log"
: > "$ARGV_LOG"

cat > "$BIN_DIR/phpstan" <<STUB
#!/usr/bin/env bash
echo "phpstan \$*" >> "$ARGV_LOG"
case "\$(cat "$MODE_FILE" 2>/dev/null)" in
    phpstan-finding) printf '%s:9:Undefined variable: \$ghost\n' "\$2"; exit 1 ;;
    phpstan-crash) echo "PHP Fatal error:  Allowed memory size of 134217728 bytes exhausted" >&2; exit 255 ;;
    phpstan-slow) exec sleep 30 ;;
esac
exit 0
STUB

cat > "$BIN_DIR/deptrac" <<STUB
#!/usr/bin/env bash
echo "deptrac \$*" >> "$ARGV_LOG"
case "\$(cat "$MODE_FILE" 2>/dev/null)" in
    deptrac-elsewhere)
        echo "::error file=$SRC_DIR/Presentation/Page.php,line=4::App\\\\Presentation\\\\Page must not depend on App\\\\Support\\\\Clock (Presentation on Support)"
        exit 1 ;;
    deptrac-crash) echo ' [ERROR] The file "deptrac.yaml" does not exist.'; exit 1 ;;
    deptrac-slow) exec sleep 30 ;;
esac
exit 0
STUB
chmod +x "$BIN_DIR/phpstan" "$BIN_DIR/deptrac"

set_mode() { printf '%s\n' "$1" > "$MODE_FILE"; }

hook_output() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$LEDGER" \
        | CRAFTSMAN_SA_BUDGET_FILE=1 CRAFTSMAN_SA_BUDGET_PROJECT=1 \
            bash "$ROOT_DIR/hooks/post-write-check.sh" 2>/dev/null
}

ci_rules_and_exit() {
    local report status=0
    report=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" --format json src/Domain/Ledger.php 2>/dev/null) || status=$?
    printf '%s exit=%s' "$(printf '%s' "$report" | grep -oE '"rule":"[A-Z0-9-]+"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')" "$status"
}

trust_tools true
cd "$PROJECT_DIR" || exit 1

# =============================================================================
# Group A - controls: a verdict with findings and a clean verdict
# =============================================================================
echo ""
echo "--- A. Controls on the same harness ---"

set_mode clean
: > "$ARGV_LOG"
CLEAN_OUT=$(hook_output)
if grep -q '^phpstan ' "$ARGV_LOG" && grep -q '^deptrac ' "$ARGV_LOG"; then
    log_pass "control: the hook ran both stubs"
else
    log_fail "control: the hook ran both stubs" \
        "argv log: '$(tr '\n' ' ' < "$ARGV_LOG")' - every assertion below is undetermined, not green"
fi
if [[ -z "$CLEAN_OUT" ]]; then
    log_pass "two clean verdicts leave a compliant file silent"
else
    log_fail "two clean verdicts leave a compliant file silent" "got '$(echo "$CLEAN_OUT" | tr '\n' ' ' | cut -c1-200)'"
fi

set_mode phpstan-finding
FINDING_OUT=$(hook_output)
if echo "$FINDING_OUT" | grep -q 'PHPSTAN002'; then
    log_pass "control: a PHPStan finding reaches the hook output"
else
    log_fail "control: a PHPStan finding reaches the hook output" "got '$(echo "$FINDING_OUT" | tr '\n' ' ' | cut -c1-200)'"
fi
if echo "$FINDING_OUT" | grep -q 'ANALYSER001'; then
    log_fail "PHPStan's exit 1 with findings is a verdict, not a crash" \
        "ANALYSER001 came out beside PHPSTAN002 - every file with a finding would also read as unanalysed"
else
    log_pass "PHPStan's exit 1 with findings is a verdict, not a crash"
fi

set_mode deptrac-elsewhere
ELSEWHERE_OUT=$(hook_output)
if echo "$ELSEWHERE_OUT" | grep -q 'ANALYSER001\|Presentation on Support'; then
    log_fail "a deptrac verdict about other files is a verdict on this one" \
        "got '$(echo "$ELSEWHERE_OUT" | tr '\n' ' ' | cut -c1-200)' - exit 1 is how deptrac reports any violation in the project"
else
    log_pass "a deptrac verdict about other files is a verdict on this one"
fi

# =============================================================================
# Group B - no verdict is not a clean verdict
# =============================================================================
echo ""
echo "--- B. A crash or a stopped run is reported ---"

set_mode phpstan-crash
CRASH_OUT=$(hook_output)
if echo "$CRASH_OUT" | grep -q 'ANALYSER001' && echo "$CRASH_OUT" | grep -q 'phpstan'; then
    log_pass "a PHPStan fatal error reaches the hook output as ANALYSER001, naming the tool"
else
    log_fail "a PHPStan fatal error reaches the hook output as ANALYSER001, naming the tool" \
        "got '$(echo "$CRASH_OUT" | tr '\n' ' ' | cut -c1-200)' - exit 255 was flattened into a clean pass"
fi
if echo "$CRASH_OUT" | grep -q 'Allowed memory'; then
    log_fail "PHPStan's own stderr stays out of the hook output" "the fatal error text reached the model's context"
else
    log_pass "PHPStan's own stderr stays out of the hook output"
fi

CRASH_CI=$(ci_rules_and_exit)
if [[ "$CRASH_CI" == *ANALYSER001* && "$CRASH_CI" != *"exit=0" ]]; then
    log_pass "a PHPStan crash is not a green pipeline ($CRASH_CI)"
else
    log_fail "a PHPStan crash is not a green pipeline" "got '$CRASH_CI'"
fi

set_mode phpstan-slow
started=$SECONDS
SLOW_OUT=$(hook_output)
elapsed=$(( SECONDS - started ))
if echo "$SLOW_OUT" | grep -q 'ANALYSER001' && [[ $elapsed -lt 15 ]]; then
    log_pass "a PHPStan run stopped by the budget is reported (${elapsed}s against 1s)"
else
    log_fail "a PHPStan run stopped by the budget is reported" \
        "${elapsed}s, got '$(echo "$SLOW_OUT" | tr '\n' ' ' | cut -c1-200)'"
fi

set_mode deptrac-crash
DEPTRAC_CRASH_OUT=$(hook_output)
if echo "$DEPTRAC_CRASH_OUT" | grep -q 'ANALYSER001' && echo "$DEPTRAC_CRASH_OUT" | grep -q 'deptrac'; then
    log_pass "a deptrac run that printed no finding line and exited 1 is reported as ANALYSER001"
else
    log_fail "a deptrac run that printed no finding line and exited 1 is reported as ANALYSER001" \
        "got '$(echo "$DEPTRAC_CRASH_OUT" | tr '\n' ' ' | cut -c1-200)' - a missing depfile read as a clean architecture"
fi
if echo "$DEPTRAC_CRASH_OUT" | grep -q 'does not exist'; then
    log_fail "deptrac's own output stays out of the hook output" "its error text reached the model's context"
else
    log_pass "deptrac's own output stays out of the hook output"
fi

set_mode deptrac-slow
started=$SECONDS
DEPTRAC_SLOW_OUT=$(hook_output)
elapsed=$(( SECONDS - started ))
if echo "$DEPTRAC_SLOW_OUT" | grep -q 'ANALYSER001' && [[ $elapsed -lt 15 ]]; then
    log_pass "a deptrac run stopped by the budget is reported (${elapsed}s against 1s)"
else
    log_fail "a deptrac run stopped by the budget is reported" \
        "${elapsed}s, got '$(echo "$DEPTRAC_SLOW_OUT" | tr '\n' ' ' | cut -c1-200)'"
fi

# =============================================================================
# Group C - consent comes first
# =============================================================================
echo ""
echo "--- C. Untrusted, nothing of the project's runs and nothing is reported ---"

trust_tools false
set_mode phpstan-crash
: > "$ARGV_LOG"
UNTRUSTED_OUT=$(hook_output)
if [[ ! -s "$ARGV_LOG" ]] && ! echo "$UNTRUSTED_OUT" | grep -q 'ANALYSER001'; then
    log_pass "untrusted, the project's analysers never run and nothing is reported for them"
else
    log_fail "untrusted, the project's analysers never run and nothing is reported for them" \
        "argv log: '$(tr '\n' ' ' < "$ARGV_LOG")', output: '$(echo "$UNTRUSTED_OUT" | tr '\n' ' ' | cut -c1-160)'"
fi
trust_tools true

# =============================================================================
# Group D - no pinned config, no run
#
# When mktemp failed, the adapter ran PHPStan bare, and a bare PHPStan
# auto-discovers the repository's phpstan.neon, whose bootstrapFiles run PHP.
# =============================================================================
echo ""
echo "--- D. Without its pinned config PHPStan does not run ---"

set_mode clean
: > "$ARGV_LOG"
UNPINNED=$(
    SA_BUDGET_FILE_SECONDS=15
    sa_timeout() { shift; "$@"; }
    source "$ROOT_DIR/hooks/lib/static-analysis.sh" >/dev/null 2>&1
    source "$ROOT_DIR/packs/symfony/static-analysis/phpstan.sh"
    # A function, not an unwritable TMPDIR: BSD mktemp falls back to the
    # per-user directory when TMPDIR does not exist, so that never fails.
    mktemp() { return 1; }
    _pack_sa_phpstan "$LEDGER"
)
if grep -q '^phpstan ' "$ARGV_LOG"; then
    log_fail "PHPStan never runs without its pinned config" \
        "argv: '$(tr '\n' ' ' < "$ARGV_LOG")' - the repository's phpstan.neon was free to load"
elif echo "$UNPINNED" | grep -q 'ANALYSER001'; then
    log_pass "PHPStan never runs without its pinned config, and says it gave no verdict"
else
    log_fail "PHPStan never runs without its pinned config, and says it gave no verdict" \
        "it did not run and reported nothing: got '$UNPINNED'"
fi

test_summary
