#!/usr/bin/env bash
# =============================================================================
# Deptrac verdicts carry the craftsman layer rule, not a blanket tool code.
#
# The point is configurability. A project writing `LAYER001: warn` in its
# .craft-config.yml had no purchase whatsoever on deptrac's verdict, because
# that verdict arrived under DEPTRAC001. Installing the analyser silently
# revoked the machine owner's doctrine, which is the worst defect a rules
# engine can have: a setting that stops applying without saying so.
#
# The duplicate verdict disappearing is a consequence, not the goal. Once
# deptrac emits LAYER001-004, the supersession declared in packs/symfony/
# pack.yml has something to cover, so precedence_flush stops re-emitting the
# Level 1 regex finding on its own.
#
# The deptrac stub replays output captured verbatim from real deptrac 1.0.2,
# 2.0.4 and 4.7.1 runs, which produce byte-identical `github-actions` lines.
# The suite must not need PHP or a composer install to be meaningful, but a
# format invented here would only ever prove the parser matches the fixture.
#
# Every assertion is paired with a control on the same harness, so a green
# result cannot be confused with a fixture that never ran.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
setup_test_env
backup_home_bridges

TMPDIR_BASE="/tmp/craftsman-deptrac-$$"
PROJECT_DIR="$TMPDIR_BASE/project"
mkdir -p "$PROJECT_DIR"
# deptrac reports symlink-resolved absolute paths, and on macOS /tmp is a
# symlink to /private/tmp. The stub must speak the same dialect the real tool
# does or the test would validate a path shape that never occurs.
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd -P)
SRC_DIR="$PROJECT_DIR/src"
mkdir -p "$SRC_DIR/Domain" "$SRC_DIR/Application" "$SRC_DIR/Infrastructure" \
    "$SRC_DIR/Support" "$PROJECT_DIR/vendor/bin"

_ORIG_HOME="$HOME"
export HOME="$TMPDIR_BASE/home"
mkdir -p "$HOME/.claude"

cleanup() {
    cd "$ROOT_DIR" || true
    export HOME="$_ORIG_HOME"
    restore_home_bridges
    cleanup_test_env
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

echo "=== Deptrac layer mapping ==="

# --- Fixture project ----------------------------------------------------------
cat > "$PROJECT_DIR/composer.json" <<'JSON'
{
  "name": "craftsman/deptrac-fixture",
  "autoload": { "psr-4": { "App\\": "src/" } }
}
JSON

# Compliant on every other rule the PHP pack enforces, so a blocked exit can
# only come from the layer boundary under test.
cat > "$SRC_DIR/Domain/Order.php" <<'PHP'
<?php

declare(strict_types=1);

namespace App\Domain;

use App\Infrastructure\DoctrineOrderRepository;

final class Order
{
    private function __construct(private readonly DoctrineOrderRepository $repository)
    {
    }
}
PHP

cat > "$SRC_DIR/Support/Helper.php" <<'PHP'
<?php

declare(strict_types=1);

namespace App\Support;

final class Helper
{
    private function __construct()
    {
    }
}
PHP

# Same basename as the Domain file, in another layer. Matching deptrac output
# by basename attributes this file's verdict to the one being edited.
cat > "$SRC_DIR/Infrastructure/Order.php" <<'PHP'
<?php

declare(strict_types=1);

namespace App\Infrastructure;

final class Order
{
    private function __construct()
    {
    }
}
PHP

DOMAIN_FILE="$SRC_DIR/Domain/Order.php"
SUPPORT_FILE="$SRC_DIR/Support/Helper.php"

# Which wording reaches the output is how these tests tell the two levels
# apart. Asserting on the rule id alone cannot distinguish "deptrac reported
# it" from "the regex did", and after this change both report LAYER001.
#
# The Level 2/3 marker is deptrac's layer pair rather than the whole message:
# the blocking path prints the message to stderr as-is, while the warning path
# puts it through jq, where every backslash of a namespace is doubled. A marker
# carrying no backslash matches the same finding on both paths, which is what
# lets one assertion compare block against warn.
L23_LAYER001="(Domain on Infrastructure)"
L1_LAYER001="Domain imports Infrastructure - DDD layer violation"

DEPTRAC_STUB="$PROJECT_DIR/vendor/bin/deptrac"

# A stub that answers whatever it is asked cannot tell a working adapter from
# one asking for a formatter deptrac does not have, which is precisely the bug
# under repair: `compact` was never a deptrac formatter, so the adapter had
# never produced a verdict on any release. Refuse like the real tool does, with
# its own message, verbatim from deptrac 1.0.2, 2.0.4 and 4.7.1.
_stub_guards() {
    cat <<STUB
# CRAFTSMAN_TEST_DEPTRAC_SILENT models the analyser that ran and produced no
# verdict: a cold-start timeout, a crash, or a depfile that does not cover the
# boundary. No verdict is not a clean verdict.
[[ "\${CRAFTSMAN_TEST_DEPTRAC_SILENT:-no}" == "yes" ]] && exit 0
FORMATTER=""
for arg in "\$@"; do
    case "\$arg" in --formatter=*) FORMATTER="\${arg#--formatter=}" ;; esac
done
if [[ "\$FORMATTER" != "github-actions" ]]; then
    echo ""
    echo " [ERROR] Output formatter \$FORMATTER not found."
    echo "         Available formatters: [\"console\", \"github-actions\", \"junit\","
    echo "         \"table\", \"xml\", \"baseline\", \"json\", \"codeclimate\"]"
    exit 1
fi
STUB
}

# Recorded deptrac output. The uncovered line is a ::warning on purpose: it is
# the shape that must not be read as a violation.
_stub_findings() {
    cat <<STUB
cat <<'LINES'
::error file=${SRC_DIR}/Domain/Order.php,line=11::App\\Domain\\Order must not depend on App\\Infrastructure\\DoctrineOrderRepository (Domain on Infrastructure)
::error file=${SRC_DIR}/Application/PlaceOrder.php,line=8::App\\Application\\PlaceOrder must not depend on App\\Presentation\\OrderController (Application on Presentation)
::error file=${SRC_DIR}/Support/Helper.php,line=4::App\\Support\\Helper must not depend on App\\Presentation\\OrderController (Support on Presentation)
::error file=${SRC_DIR}/Infrastructure/Order.php,line=6::App\\Infrastructure\\Order must not depend on App\\Presentation\\OrderController (Infrastructure on Presentation)
::warning file=${SRC_DIR}/Domain/Order.php,line=13::App\\Domain\\Order has uncovered dependency on App\\Free\\Loose (Domain)
LINES
exit 1
STUB
}

install_deptrac() {
    {
        printf '#!/usr/bin/env bash\n'
        _stub_guards
        _stub_findings
    } > "$DEPTRAC_STUB"
    chmod +x "$DEPTRAC_STUB"
}

remove_deptrac() {
    rm -f "$DEPTRAC_STUB"
}

write_home_config() {
    {
        echo "stack: fullstack"
        echo "trust_project_tools: true"
    } > "$HOME/.claude/.craft-config.yml"
}

write_project_rules() {
    if [[ -z "${1:-}" ]]; then
        rm -f "$PROJECT_DIR/.craft-config.yml"
        return 0
    fi
    printf 'rules:\n  %s\n' "$1" > "$PROJECT_DIR/.craft-config.yml"
}

hook_output() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1
}

hook_exit() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1
    echo $?
}

write_home_config
cd "$PROJECT_DIR" || exit 1

# =============================================================================
# Group A - the adapter itself, against the recorded deptrac output
# =============================================================================
echo ""
echo "--- A. The adapter maps a layer pair to the rule that describes it ---"

SA_BUDGET_FILE_SECONDS=15
SA_BUDGET_PROJECT_SECONDS=30
sa_timeout() { shift; "$@"; }
source "$ROOT_DIR/packs/symfony/static-analysis/phpstan.sh"

install_deptrac
PATH="$PROJECT_DIR/vendor/bin:$PATH"
ADAPTER_DOMAIN=$(pack_sa_php "$DOMAIN_FILE" 2>/dev/null)

if assert_produced_output "pack_sa_php" "$ADAPTER_DOMAIN"; then
    log_pass "control: the adapter produced a verdict for the Domain file"

    if echo "$ADAPTER_DOMAIN" | grep -q '^LAYER001:'; then
        log_pass "Domain on Infrastructure is emitted as LAYER001"
    else
        log_fail "the layer pair is not mapped" \
            "got '$(echo "$ADAPTER_DOMAIN" | tr '\n' ' ' | cut -c1-160)' - under a blanket DEPTRAC001 no project configuration can reach this verdict"
    fi

    if echo "$ADAPTER_DOMAIN" | grep -q 'DEPTRAC001'; then
        log_fail "a mapped pair still carries the tool code" \
            "LAYER001 and DEPTRAC001 both came out for one finding"
    else
        log_pass "the mapped finding does not also report under DEPTRAC001"
    fi

    if echo "$ADAPTER_DOMAIN" | grep -q 'uncovered dependency'; then
        log_fail "an uncovered dependency was read as a violation" \
            "deptrac reports those at ::warning level and only on request - they are not rule findings"
    else
        log_pass "a ::warning uncovered line is not read as a violation"
    fi

    if echo "$ADAPTER_DOMAIN" | grep -q 'Infrastructure on Presentation'; then
        log_fail "a verdict on another file was attributed to this one" \
            "src/Infrastructure/Order.php shares its basename with the file under analysis, so matching deptrac output by basename files its defect against the wrong file, now under a specific layer rule"
    else
        log_pass "a same-basename file in another layer keeps its own verdict"
    fi
fi

ADAPTER_SUPPORT=$(pack_sa_php "$SUPPORT_FILE" 2>/dev/null)

if echo "$ADAPTER_SUPPORT" | grep -q '^DEPTRAC001:'; then
    log_pass "a pair none of the four rules describes stays on DEPTRAC001"
else
    log_fail "an unmapped layer pair was filed under a layer rule" \
        "got '$(echo "$ADAPTER_SUPPORT" | tr '\n' ' ' | cut -c1-160)' - Support on Presentation is a real defect and a wrong label sends the developer to the wrong rule and the wrong knowledge page"
fi

# Each of the four, so a mapping that only ever answers LAYER001 cannot pass.
check_pair() {
    local depender="$1" dependent="$2" expected="$3" got
    got=$(_pack_sa_deptrac_rule \
        "App\\${depender}\\Thing must not depend on App\\${dependent}\\Other (${depender} on ${dependent})")
    if [[ "$got" == "$expected" ]]; then
        log_pass "${depender} on ${dependent} maps to ${expected}"
    else
        log_fail "${depender} on ${dependent} mapping" "expected $expected, got $got"
    fi
}

check_pair Domain Infrastructure LAYER001
check_pair Domain Presentation LAYER002
check_pair Application Presentation LAYER003
check_pair Domain Doctrine LAYER004
check_pair Support Presentation DEPTRAC001
check_pair Application Infrastructure DEPTRAC001

# =============================================================================
# Group B - THE point: a project's doctrine reaches the deptrac verdict
# =============================================================================
echo ""
echo "--- B. LAYER001 in .craft-config.yml governs the deptrac verdict ---"

install_deptrac
write_project_rules ""
BLOCKED_CODE=$(hook_exit "$DOMAIN_FILE")
BLOCKED_OUT=$(hook_output "$DOMAIN_FILE")

if [[ "$BLOCKED_CODE" == "2" ]] && echo "$BLOCKED_OUT" | grep -qF "$L23_LAYER001"; then
    log_pass "control: with no override the deptrac verdict blocks the write"

    write_project_rules "LAYER001: warn"
    WARN_CODE=$(hook_exit "$DOMAIN_FILE")
    WARN_OUT=$(hook_output "$DOMAIN_FILE")

    if [[ "$WARN_CODE" == "0" ]]; then
        log_pass "LAYER001: warn downgrades the deptrac verdict to a warning"
    else
        log_fail "project configuration has no purchase on the deptrac verdict" \
            "expected exit 0 with LAYER001: warn, got $WARN_CODE - this is the whole reason the mapping exists: under DEPTRAC001 the setting was silently ignored"
    fi

    if echo "$WARN_OUT" | grep -qF "$L23_LAYER001"; then
        log_pass "downgraded, the deptrac finding is still reported"
    else
        log_fail "the downgrade silenced the finding" \
            "warn must mean warn, not ignore"
    fi

    write_project_rules "LAYER001: ignore"
    IGNORED_OUT=$(hook_output "$DOMAIN_FILE")

    if echo "$IGNORED_OUT" | grep -qF "$L23_LAYER001"; then
        log_fail "LAYER001: ignore does not reach the deptrac verdict" \
            "the finding was reported anyway - severity resolution is being bypassed for Level 3 output"
    else
        log_pass "LAYER001: ignore silences the deptrac verdict"
    fi
else
    log_fail "control: the deptrac verdict does not block on a clean config" \
        "exit=$BLOCKED_CODE out='$(echo "$BLOCKED_OUT" | tr '\n' ' ' | cut -c1-200)' - every assertion in this group is undetermined, not green"
fi

write_project_rules ""

# =============================================================================
# Group C - the duplicate, and its return
# =============================================================================
echo ""
echo "--- C. One defect, one verdict, and the regex comes back without deptrac ---"

remove_deptrac
NO_TOOL=$(hook_output "$DOMAIN_FILE")

if echo "$NO_TOOL" | grep -qF "$L1_LAYER001"; then
    log_pass "control: with no deptrac the Level 1 regex reports LAYER001"

    install_deptrac
    WITH_TOOL=$(hook_output "$DOMAIN_FILE")

    if echo "$WITH_TOOL" | grep -qF "$L23_LAYER001"; then
        log_pass "control: with deptrac installed its own verdict comes out"

        if echo "$WITH_TOOL" | grep -qF "$L1_LAYER001"; then
            log_fail "one defect still gets two verdicts" \
                "the Level 1 message is in the output beside deptrac's - the supersession declared in packs/symfony/pack.yml is not being honoured"
        else
            log_pass "the Level 1 finding is deferred once deptrac answers for LAYER001"
        fi
    else
        log_fail "control: deptrac produced no verdict through the hook" \
            "the deferral assertions are undetermined, not green"
    fi
else
    log_fail "control: the Level 1 layer regex does not fire on the fixture" \
        "got '$(echo "$NO_TOOL" | tr '\n' ' ' | cut -c1-200)' - group C is undetermined"
fi

install_deptrac
export CRAFTSMAN_TEST_DEPTRAC_SILENT=yes
SILENT=$(hook_output "$DOMAIN_FILE")
unset CRAFTSMAN_TEST_DEPTRAC_SILENT

if echo "$SILENT" | grep -qF "$L23_LAYER001"; then
    log_fail "control: the stub was supposed to stay silent" \
        "the flush assertion below would be meaningless"
elif echo "$SILENT" | grep -qF "$L1_LAYER001"; then
    log_pass "deptrac installed but silent: the held regex finding is flushed"
else
    log_fail "the defect vanished from both levels" \
        "deptrac produced no verdict and the Level 1 finding was not flushed - a cold-start timeout now deletes a layer violation in silence, which is strictly worse than reporting it twice"
fi

# =============================================================================
# Group D - the unmapped pair keeps blocking under its own code
# =============================================================================
echo ""
echo "--- D. A pair outside the four still reports, under DEPTRAC001 ---"

install_deptrac
SUPPORT_OUT=$(hook_output "$SUPPORT_FILE")

if echo "$SUPPORT_OUT" | grep -q 'DEPTRAC001'; then
    log_pass "an unmapped deptrac violation reaches the hook output as DEPTRAC001"
else
    log_fail "an unmapped deptrac violation was lost" \
        "got '$(echo "$SUPPORT_OUT" | tr '\n' ' ' | cut -c1-200)' - narrowing the codes must not narrow what is reported"
fi

# =============================================================================
# Group E - the manifest, and the compile-time refusal it has to survive
# =============================================================================
echo ""
echo "--- E. The supersession is declared in the pack manifest ---"

REGISTRY=$(python3 "$ROOT_DIR/hooks/lib/lang_registry.py" \
    "$ROOT_DIR/packs/symfony/pack.yml" 2>/dev/null)

if echo "$REGISTRY" | grep -q 'php	extensions'; then
    log_pass "control: the symfony manifest was indexed"

    CLAIM=$(echo "$REGISTRY" | grep '	supersedes	' | head -1)
    MISSING=""
    for rule in LAYER001 LAYER002 LAYER003 LAYER004; do
        echo "$CLAIM" | grep -q "$rule" || MISSING="${MISSING}${rule} "
    done

    if [[ -z "$MISSING" ]]; then
        log_pass "deptrac claims all four layer rules and survives the refusal"
    else
        log_fail "the supersession did not reach the registry" \
            "missing: ${MISSING}- lang_registry.py refuses a tool that would outrank its own verdicts, and a silently dropped claim leaves the duplicate in place"
    fi
else
    log_fail "control: lang_registry.py produced nothing for the symfony manifest" \
        "the claim assertion is undetermined, not green"
fi

# =============================================================================
# Group F - hook and CI resolve this the same way
# =============================================================================
echo ""
echo "--- F. The pipeline agrees with the hook ---"

install_deptrac
write_project_rules ""
CI_BLOCKED=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" src 2>&1)

if assert_produced_output "craftsman-ci" "$CI_BLOCKED"; then
    if echo "$CI_BLOCKED" | grep -q 'LAYER001'; then
        log_pass "control: CI reports LAYER001 for the deptrac verdict"

        if echo "$CI_BLOCKED" | grep -qF "$L1_LAYER001"; then
            log_fail "CI honours the deferral" \
                "CI emits the Level 1 verdict while the hook does not - green locally and red in the pipeline on a rule neither front-end decided differently"
        else
            log_pass "CI defers the Level 1 finding exactly as the hook does"
        fi
    else
        log_fail "control: CI reports no LAYER001 on the fixture" \
            "got '$(echo "$CI_BLOCKED" | tr '\n' ' ' | cut -c1-200)' - the parity assertion is undetermined"
    fi
fi

test_summary
