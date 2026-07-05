#!/usr/bin/env bash
# Tests for the structural rules NEST001/LOC001/GOD001/PARAM001/CTRL001
# (brace-aware metrics + controller leak + warn-first severity routing).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Structural Rules Tests ==="

# Mock orchestrator helpers, then source the validators + structural bridge.
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="test"

source "$ROOT_DIR/hooks/lib/structural.sh"
source "$ROOT_DIR/packs/symfony/hooks/php-validator.sh"
source "$ROOT_DIR/packs/react/hooks/typescript-validator.sh"
source "$ROOT_DIR/hooks/lib/rules-engine.sh"

if ! command -v python3 >/dev/null 2>&1; then
    log_pass "python3 absent - structural checks fail-open (skipping detection asserts)"
else
    TMPD=$(mktemp -d)
    # PARAM001: method with > 3 params (constructor exempt)
    f_param="$TMPD/Param.php"
    cat > "$f_param" << 'PHP'
<?php
declare(strict_types=1);
final class Foo
{
    public function doIt(int $a, int $b, int $c, int $d): void {}
    public function __construct(int $a, int $b, int $c, int $d, int $e) {}
}
PHP
    VIOLATIONS=""; pack_validate_php "$f_param"
    echo -e "$VIOLATIONS" | grep -q "PARAM001:.*doIt" \
        && log_pass "PARAM001: flags 4-param method" \
        || log_fail "PARAM001: flags 4-param method" "got: $(echo -e "$VIOLATIONS")"
    echo -e "$VIOLATIONS" | grep -q "PARAM001:.*__construct" \
        && log_fail "PARAM001: constructor exempt" "constructor was flagged" \
        || log_pass "PARAM001: constructor exempt from param limit"

    # NEST001: 3 nested control blocks
    f_nest="$TMPD/Nest.php"
    cat > "$f_nest" << 'PHP'
<?php
declare(strict_types=1);
final class Foo
{
    public function deep(array $rows): void
    {
        foreach ($rows as $r) {
            if ($r) {
                while ($r > 0) {
                    $r--;
                }
            }
        }
    }
}
PHP
    VIOLATIONS=""; pack_validate_php "$f_nest"
    echo -e "$VIOLATIONS" | grep -q "NEST001" \
        && log_pass "NEST001: flags 3-deep nesting" \
        || log_fail "NEST001: flags 3-deep nesting" "got: $(echo -e "$VIOLATIONS")"

    # GOD001: class span > 300 lines
    f_god="$TMPD/Big.php"
    {
        echo "<?php"; echo "declare(strict_types=1);"; echo "final class Big"; echo "{"
        for i in $(seq 1 320); do echo "    private int \$p${i} = 0;"; done
        echo "}"
    } > "$f_god"
    VIOLATIONS=""; pack_validate_php "$f_god"
    echo -e "$VIOLATIONS" | grep -q "GOD001" \
        && log_pass "GOD001: flags 320-line class" \
        || log_fail "GOD001: flags 320-line class" "got: $(echo -e "$VIOLATIONS")"

    # CTRL001: persistence inside a Controller
    f_ctrl="$TMPD/FooController.php"
    cat > "$f_ctrl" << 'PHP'
<?php
declare(strict_types=1);
final class FooController
{
    public function save($em): void { $em->flush(); }
}
PHP
    VIOLATIONS=""; pack_validate_php "$f_ctrl"
    echo -e "$VIOLATIONS" | grep -q "CTRL001" \
        && log_pass "CTRL001: flags persistence in controller" \
        || log_fail "CTRL001: flags persistence in controller" "got: $(echo -e "$VIOLATIONS")"

    # Clean file: no structural noise
    f_clean="$TMPD/Clean.php"
    cat > "$f_clean" << 'PHP'
<?php
declare(strict_types=1);
final class Clean
{
    public function name(): string
    {
        return 'ok';
    }
}
PHP
    VIOLATIONS=""; pack_validate_php "$f_clean"
    structural_only=$(echo -e "$VIOLATIONS" | grep -E "NEST001|LOC001|GOD001|PARAM001|CTRL001" || true)
    [[ -z "$structural_only" ]] \
        && log_pass "Clean file: no structural false positives" \
        || log_fail "Clean file: no structural false positives" "got: $structural_only"

    rm -rf "$TMPD"
fi

# Severity routing: structural rules are advisory (warn) in strict mode
_RULES_STRICTNESS="strict"
for rule in NEST001 LOC001 GOD001 PARAM001 CTRL001; do
    sev=$(_rules_default_severity "$rule")
    [[ "$sev" == "warn" ]] \
        && log_pass "Severity: ${rule} is advisory (warn-first) under strict" \
        || log_fail "Severity: ${rule} warn-first" "got: $sev"
done

# PHP002 still blocks under strict (regression guard)
sev_block=$(_rules_default_severity "PHP002")
[[ "$sev_block" == "block" ]] \
    && log_pass "Severity: PHP002 still blocks under strict (regression)" \
    || log_fail "Severity: PHP002 still blocks" "got: $sev_block"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
