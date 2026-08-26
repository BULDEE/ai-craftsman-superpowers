#!/bin/bash
# AI Craftsman Superpowers - Test Suite
# Run with: ./tests/run-tests.sh [--skill <name>] [--verbose]
# craftsman-ignore: SH002

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$ROOT_DIR"
SKILLS_DIR="$ROOT_DIR/skills"

# The suite drives the real hooks, and metrics-db.sh falls back to
# ~/.claude/plugins/data/craftsman whenever CLAUDE_PLUGIN_DATA is unset. Every
# unisolated run therefore recorded its own fixtures as production violations,
# and the correction-learning loop trained on them. Set here rather than per
# suite so a new suite is covered by default instead of by remembering.
CLAUDE_PLUGIN_DATA="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-tests.XXXXXX")"
export CLAUDE_PLUGIN_DATA
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT

# Belt and braces: a subtest that resolves its own database path anyway still
# tags its rows, so the next contamination is a DELETE and not a guess.
export CRAFTSMAN_METRICS_SOURCE="test"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Options
VERBOSE=false
SPECIFIC_SKILL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skill)
            SPECIFIC_SKILL="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--skill <name>] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --skill <name>  Test only specific skill"
            echo "  --verbose, -v   Show detailed output"
            echo "  --help, -h      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
    echo -e "  ${YELLOW}○${NC} $1 (skipped)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# run-tests.sh does not source test-helpers.sh, so it takes the shared helper
# directly. Same file, no second copy.
source "${ROOT_DIR}/hooks/lib/portable-timeout.sh"

run_with_timeout() {
    portable_timeout "$@"
}

# run_subtest "<label>" "<path to test script>"
#
# Every wrapper used to run its subtest with output discarded and, on failure,
# tell you to run the script yourself. For a failure that only happens in the
# suite, that advice cannot work: by the time you re-run it, whatever the other
# tests left behind is gone, the script passes on its own, and the failure
# reads as noise. The failing output is kept and printed here instead.
run_subtest() {
    local label="$1" script="$2"

    if [[ ! -f "$script" ]]; then
        log_skip "$label (${script#$ROOT_DIR/} not found)"
        return 0
    fi

    local out status=0
    out=$(mktemp)
    # A suite that hangs is worse than one that fails: nobody waits it out, so
    # it gets killed and the run reports nothing at all. tests/ci/test-ratchet-ci.sh
    # was observed spawning craftsman-ci.sh recursively and never returning.
    # 300s is well past the slowest honest subtest (craftsman-ci, ~75s).
    run_with_timeout "${SUBTEST_TIMEOUT:-300}" bash "$script" > "$out" 2>&1 || status=$?

    if [[ $status -eq 0 ]]; then
        log_pass "$label"
        rm -f "$out"
        return 0
    fi

    if [[ $status -eq 124 ]]; then
        log_fail "$label - ${script#$ROOT_DIR/} TIMED OUT after ${SUBTEST_TIMEOUT:-300}s"
        echo "    --- last 15 lines before the timeout ---"
        tail -15 "$out" | sed 's/^/    /'
        echo "    --- full output kept at: $out ---"
        return 1
    fi

    log_fail "$label - ${script#$ROOT_DIR/}"
    local total
    total=$(wc -l < "$out" | tr -d ' ')
    if [[ "$total" -gt 25 ]]; then
        echo "    --- failing assertions ---"
        grep -E "✗" "$out" | sed 's/^/    /' | head -20
        echo "    --- last 25 of $total lines ---"
    fi
    tail -25 "$out" | sed 's/^/    /'
    echo "    --- full output kept at: $out ---"
    return 1
}

# Test: SKILL.md exists and has valid frontmatter
test_skill_structure() {
    local skill_dir="$1"
    local skill_name=$(basename "$skill_dir")

    echo ""
    log_info "Testing skill: $skill_name"

    local skill_file="$skill_dir/SKILL.md"

    # Test 1: SKILL.md exists
    if [[ -f "$skill_file" ]]; then
        log_pass "SKILL.md exists"
    else
        log_fail "SKILL.md missing"
        return 1
    fi

    # Test 2: Has YAML frontmatter
    if grep -m1 "^---$" "$skill_file" > /dev/null 2>&1; then
        log_pass "Has YAML frontmatter"
    else
        log_fail "Missing YAML frontmatter"
        return 1
    fi

    # Test 3: Has description field (skill name comes from the directory name)
    if grep -q "^description:" "$skill_file"; then
        log_pass "Has 'description' field"
    else
        log_fail "Missing 'description' field"
    fi

    # Test 4: Has effort field.
    # Values are Claude Code's own effort levels: the key is read from the
    # frontmatter and overrides the session effort level, so anything outside
    # this set is not a naming preference, it is an unrecognised value.
    #
    # There is no exemption. session-init used to have one, and the missing
    # field was the symptom rather than the special case: nothing invoked that
    # skill, so nobody ever had to give it a tier. A skill with no effort and
    # no outcome contract is a skill no one runs.
    if grep -q "^effort:" "$skill_file"; then
        local effort=$(grep "^effort:" "$skill_file" | head -1 | cut -d: -f2 | tr -d ' ')
        if [[ "$effort" =~ ^(low|medium|high|xhigh|max)$ ]]; then
            log_pass "Has valid 'effort' field: $effort"
        else
            log_fail "Invalid effort value: $effort (must be low|medium|high|xhigh|max)"
        fi
    else
        log_fail "Missing 'effort' field"
    fi

    # Test 4b: Declares a model tier.
    # Every skill picks the cheapest tier that can do its job, so a missing
    # 'model' is a regression: the skill would silently run on whatever the
    # session happens to be set to, which is the behaviour the tiering exists
    # to prevent. Aliases only - a pinned id would not follow model releases.
    if grep -q "^model:" "$skill_file"; then
        local model=$(grep "^model:" "$skill_file" | head -1 | cut -d: -f2 | tr -d ' ')
        if [[ "$model" =~ ^(haiku|sonnet|opus|best|fable)$ ]]; then
            log_pass "Has valid 'model' tier: $model"
        else
            log_fail "Invalid model tier: $model (must be haiku|sonnet|opus|best|fable)"
        fi
    else
        log_fail "Missing 'model' field (every skill declares its tier)"
    fi

    # Test 5: Outcome Contract (Outcome / Done when / Evidence)
    if grep -q "^## Outcome Contract" "$skill_file"; then
        local contract_ok=true
        for field in "Outcome" "Done when" "Evidence"; do
            grep -q "^- \*\*${field}\*\*:" "$skill_file" || contract_ok=false
        done
        if [[ "$contract_ok" == true ]]; then
            log_pass "Has complete Outcome Contract"
        else
            log_fail "Outcome Contract incomplete (needs Outcome, Done when, Evidence)"
        fi
    else
        log_fail "Missing '## Outcome Contract' section"
    fi

    # Test 6: context: fork requires an agent binding
    if grep -q "^context: fork" "$skill_file"; then
        if grep -q "^agent:" "$skill_file"; then
            log_pass "Forked skill declares an 'agent' binding"
        else
            log_fail "context: fork without 'agent' binding"
        fi
    fi

    # Test 7: Line count check
    local line_count=$(wc -l < "$skill_file")
    if [[ $line_count -lt 500 ]]; then
        log_pass "Under 500 lines ($line_count lines)"
    else
        log_warn "Over 500 lines ($line_count lines) - consider splitting"
    fi
}

# Test: Hooks are valid
test_hooks() {
    echo ""
    log_info "Testing hooks"

    local hooks_file="$PLUGIN_DIR/hooks/hooks.json"

    # Test 1: hooks.json exists
    if [[ -f "$hooks_file" ]]; then
        log_pass "hooks.json exists"
    else
        log_fail "hooks.json missing"
        return 1
    fi

    # Test 2: Valid JSON
    if python3 -c "import json; json.load(open('$hooks_file'))" 2>/dev/null; then
        log_pass "Valid JSON syntax"
    else
        log_fail "Invalid JSON syntax"
        return 1
    fi

    # Test 3: Hook scripts exist
    local scripts=("post-write-check.sh" "bias-detector.sh" "pre-write-check.sh" "session-metrics.sh" "session-start.sh" "file-changed.sh")
    for script in "${scripts[@]}"; do
        if [[ -f "$PLUGIN_DIR/hooks/$script" ]]; then
            log_pass "Script exists: $script"
            # Test 4: Script is executable
            if [[ -x "$PLUGIN_DIR/hooks/$script" ]]; then
                log_pass "Script executable: $script"
            else
                log_fail "Script not executable: $script"
            fi
        else
            log_fail "Script missing: $script"
        fi
    done
}

# Test: Plugin manifest is valid
test_plugin_manifest() {
    echo ""
    log_info "Testing plugin manifest"

    local manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"

    # Test 1: plugin.json exists
    if [[ -f "$manifest" ]]; then
        log_pass "plugin.json exists"
    else
        log_fail "plugin.json missing"
        return 1
    fi

    # Test 2: Valid JSON
    if python3 -c "import json; json.load(open('$manifest'))" 2>/dev/null; then
        log_pass "Valid JSON syntax"
    else
        log_fail "Invalid JSON syntax"
        return 1
    fi

    # Test 3: Required fields
    local required_fields=("name" "description" "version")
    for field in "${required_fields[@]}"; do
        if python3 -c "import json; d=json.load(open('$manifest')); assert '$field' in d" 2>/dev/null; then
            log_pass "Has required field: $field"
        else
            log_fail "Missing required field: $field"
        fi
    done

    # Test 4: repository is a string (not object)
    if python3 -c "import json; d=json.load(open('$manifest')); assert isinstance(d.get('repository', ''), str)" 2>/dev/null; then
        log_pass "repository is string type"
    else
        log_fail "repository must be string, not object"
    fi
}

# Test: Knowledge base files exist
test_knowledge_base() {
    echo ""
    log_info "Testing knowledge base"

    local knowledge_dir="$PLUGIN_DIR/knowledge"

    # Test 1: Directory exists
    if [[ -d "$knowledge_dir" ]]; then
        log_pass "knowledge/ directory exists"
    else
        log_fail "knowledge/ directory missing"
        return 1
    fi

    # Test 2: Core files exist
    local core_files=("patterns.md" "principles.md")
    for file in "${core_files[@]}"; do
        if [[ -f "$knowledge_dir/$file" ]]; then
            log_pass "Core file exists: $file"
        else
            log_fail "Core file missing: $file"
        fi
    done

    # Test 3: Anti-patterns directory exists
    if [[ -d "$knowledge_dir/anti-patterns" ]]; then
        log_pass "anti-patterns/ directory exists"
        local anti_pattern_count=$(find "$knowledge_dir/anti-patterns" -name "*.md" | wc -l)
        log_pass "Found $anti_pattern_count anti-pattern files"
    else
        log_fail "anti-patterns/ directory missing"
    fi
}

# Test: Examples exist
test_examples() {
    echo ""
    log_info "Testing examples"

    local examples_dir="$ROOT_DIR/examples"

    # Test 1: Directory exists
    if [[ -d "$examples_dir" ]]; then
        log_pass "examples/ directory exists"
    else
        log_fail "examples/ directory missing"
        return 1
    fi

    # Test 2: Core skills have examples
    local core_skills=("design" "debug" "challenge" "plan" "git" "test")
    for skill in "${core_skills[@]}"; do
        if [[ -d "$examples_dir/$skill" ]]; then
            local example_count=$(find "$examples_dir/$skill" -name "*.md" | wc -l)
            if [[ $example_count -gt 0 ]]; then
                log_pass "Examples exist for $skill ($example_count files)"
            else
                log_fail "No examples for $skill"
            fi
        else
            log_fail "Missing examples directory: $skill"
        fi
    done
}

# Test: ADRs exist
test_adrs() {
    echo ""
    log_info "Testing ADRs"

    local adr_dir="$ROOT_DIR/docs/adr"

    # Test 1: Directory exists
    if [[ -d "$adr_dir" ]]; then
        log_pass "docs/adr/ directory exists"
    else
        log_fail "docs/adr/ directory missing"
        return 1
    fi

    # Test 2: Core ADRs exist
    local core_adrs=("0010-model-tiering.md" "0011-context-fork-strategy.md")
    for adr in "${core_adrs[@]}"; do
        if [[ -f "$adr_dir/$adr" ]]; then
            log_pass "ADR exists: $adr"
        else
            log_fail "ADR missing: $adr"
        fi
    done
}

# Test: Hook behavior (functional tests)
test_hook_behavior() {
    echo ""
    log_info "Testing hook behavior (functional)"

    run_subtest "Hook behavior tests pass" "$SCRIPT_DIR/core/test-hooks.sh" || true
}

test_agent_hooks() {
    echo ""
    log_info "Testing agent hook gates (functional)"

    run_subtest "Agent hook gate tests pass" "$SCRIPT_DIR/core/test-agent-hooks.sh" || true
}

test_hostile_repo() {
    echo ""
    log_info "Testing hostile-repository invariants (functional)"

    run_subtest "Hostile-repository invariants hold" "$SCRIPT_DIR/core/test-hostile-repo.sh" || true
}

test_dynamic_context() {
    echo ""
    log_info "Testing injected !\`...\` context patterns (functional)"

    run_subtest "Dynamic-context patterns survive a non-git directory" "$SCRIPT_DIR/core/test-dynamic-context.sh" || true
}

test_ratchet() {
    echo ""
    log_info "Testing structural ratchet (functional)"

    run_subtest "Structural ratchet tests pass" "$SCRIPT_DIR/core/test-ratchet.sh" || true
}

test_design_panel() {
    echo ""
    log_info "Testing adversarial design panel (functional)"

    run_subtest "Design panel tests pass" "$SCRIPT_DIR/core/test-design-panel.sh" || true
}

test_okf_knowledge() {
    echo ""
    log_info "Testing OKF knowledge bundle (functional)"

    run_subtest "OKF knowledge bundle tests pass" "$SCRIPT_DIR/core/test-okf-knowledge.sh" || true
}

test_dashboard() {
    echo ""
    log_info "Testing metrics dashboard (functional)"

    run_subtest "Dashboard tests pass" "$SCRIPT_DIR/core/test-dashboard.sh" || true
}

test_tooling_detect() {
    echo ""
    log_info "Testing tooling detector (functional)"

    run_subtest "Tooling detector tests pass" "$SCRIPT_DIR/core/test-tooling-detect.sh" || true
}

test_verify_loop() {
    echo ""
    log_info "Testing deterministic verification loop (functional)"

    run_subtest "Verification loop tests pass" "$SCRIPT_DIR/core/test-verify-loop.sh" || true
}

test_observation() {
    echo ""
    log_info "Testing setup-by-observation generators (functional)"

    run_subtest "Observation generator tests pass" "$SCRIPT_DIR/core/test-observation.sh" || true
}

test_instincts() {
    echo ""
    log_info "Testing instinct pipeline and context budgets (functional)"

    run_subtest "Instinct pipeline tests pass" "$SCRIPT_DIR/core/test-instincts.sh" || true
}

test_config_protection() {
    echo ""
    log_info "Testing config-protection hook (functional)"

    run_subtest "Config-protection tests pass" "$SCRIPT_DIR/core/test-config-protection.sh" || true
}

test_security_invariants() {
    echo ""
    log_info "Testing security invariants (functional)"

    run_subtest "Security invariant tests pass" "$SCRIPT_DIR/core/test-security-invariants.sh" || true
}

# Test: Config resolution (unit tests)
test_config_resolution() {
    echo ""
    log_info "Testing config resolution (unit)"

    run_subtest "Config resolution tests pass" "$SCRIPT_DIR/core/test-config.sh" || true
}

# Test: Pack-specific test suites
# Test: template and manifest validation
#
# tests/templates/test-templates.sh existed, was documented in CLAUDE.md as a
# validation command, and was invoked by nothing. Four of its assertions had
# been red for long enough that the architecture they targeted no longer
# existed, and the suite reported green throughout. A test file that the runner
# does not call is not a test.
test_template_suite() {
    echo ""
    log_info "Testing templates and manifests"
    run_subtest "Template suite passes" "$SCRIPT_DIR/templates/test-templates.sh" || true
}

test_pack_suites() {
    echo ""
    log_info "Testing pack suites"

    local packs_dir="$SCRIPT_DIR/packs"
    if [[ ! -d "$packs_dir" ]]; then
        log_skip "Pack tests (tests/packs/ not found)"
        return
    fi

    for test_file in "$packs_dir"/test-*.sh; do
        [[ -f "$test_file" ]] || continue
        local name=$(basename "$test_file")
        run_subtest "Pack suite passes: $name" "$test_file" || true
    done
}

# Test: craftsman-ci CLI (functional tests)
test_craftsman_ci() {
    echo ""
    log_info "Testing craftsman-ci CLI (functional)"

    run_subtest "craftsman-ci CLI tests pass" "$SCRIPT_DIR/ci/test-craftsman-ci.sh" || true
}

# Test: Bias detector (functional tests)
test_bias_detector() {
    echo ""
    log_info "Testing bias detector (functional)"

    run_subtest "Bias detector tests pass" "$SCRIPT_DIR/core/test-bias-detector.sh" || true
}

# Test: Correction learning (functional tests)
test_correction_learning() {
    echo ""
    log_info "Testing correction learning (functional)"

    run_subtest "Correction learning tests pass" "$SCRIPT_DIR/core/test-correction-learning.sh" || true
}

# Test: Session metrics (functional tests)
test_session_metrics() {
    echo ""
    log_info "Testing session metrics (functional)"

    run_subtest "Session metrics tests pass" "$SCRIPT_DIR/core/test-session-metrics.sh" || true
    run_subtest "Metrics consolidation tests pass" "$SCRIPT_DIR/core/test-consolidate-metrics.sh" || true
    run_subtest "Runner integrity tests pass" "$SCRIPT_DIR/core/test-runner-integrity.sh" || true
    run_subtest "Circuit breaker and cache tests pass" "$SCRIPT_DIR/core/test-circuit-breaker.sh" || true
    run_subtest "External pack gating tests pass" "$SCRIPT_DIR/core/test-external-packs.sh" || true
    run_subtest "Language registry tests pass" "$SCRIPT_DIR/core/test-lang-registry.sh" || true
    run_subtest "Level precedence tests pass" "$SCRIPT_DIR/core/test-precedence.sh" || true
    run_subtest "Gate independence tests pass" "$SCRIPT_DIR/core/test-gate-independence.sh" || true
    run_subtest "Healthcheck tests pass" "$SCRIPT_DIR/core/test-healthcheck.sh" || true
    run_subtest "LSP policy tests pass" "$SCRIPT_DIR/core/test-lsp-policy.sh" || true
    run_subtest "Pack loader tests pass" "$SCRIPT_DIR/core/test-pack-loader.sh" || true
    run_subtest "Routing table tests pass" "$SCRIPT_DIR/core/test-routing-table.sh" || true
    run_subtest "Rules engine tests pass" "$SCRIPT_DIR/core/test-rules-engine.sh" || true
    run_subtest "Session start tests pass" "$SCRIPT_DIR/core/test-session-start.sh" || true
    run_subtest "Pack validation tests pass" "$SCRIPT_DIR/core/test-validate-pack.sh" || true
    run_subtest "CI adapter tests pass" "$SCRIPT_DIR/ci/test-adapters.sh" || true
    run_subtest "CI adapter delivery tests pass" "$SCRIPT_DIR/ci/test-adapter-delivery.sh" || true
    run_subtest "Hermes pre_verify adapter tests pass" "$SCRIPT_DIR/adapters/test-hermes-pre-verify.sh" || true
    run_subtest "Host adapter parity tests pass" "$SCRIPT_DIR/adapters/test-parity.sh" || true
    run_subtest "Doctrine export tests pass" "$SCRIPT_DIR/ci/test-doctrine-export.sh" || true
    run_subtest "Rule registry tests pass" "$SCRIPT_DIR/ci/test-rule-registry.sh" || true
    run_subtest "Ratchet CI parity tests pass" "$SCRIPT_DIR/ci/test-ratchet-ci.sh" || true
    run_subtest "Turn budget delivery tests pass" "$SCRIPT_DIR/core/test-turn-budget.sh" || true

    run_subtest "Suite isolation audit" "$SCRIPT_DIR/core/test-suite-isolation.sh" || true

    echo ""
    log_info "Testing session state library (unit)"

    run_subtest "Session state library tests pass" "$SCRIPT_DIR/core/test-session-state-lib.sh" || true
}

# Test: Knowledge base integrity (files, stubs, em-dash, wiki-links)
test_knowledge_integrity() {
    echo ""
    log_info "Testing knowledge base integrity"

    run_subtest "Knowledge base integrity tests pass" "$SCRIPT_DIR/core/test-knowledge-integrity.sh" || true
}

# Test: Workflow command (content validation)
test_workflow_command() {
    echo ""
    log_info "Testing workflow command (content)"

    run_subtest "Workflow command tests pass" "$SCRIPT_DIR/core/test-workflow-command.sh" || true
}

# Test: Nothing points at a skill it cannot start
test_invocation_policy() {
    echo ""
    log_info "Testing skill invocation policy (agents, workflow claims)"

    run_subtest "Invocation policy tests pass" "$SCRIPT_DIR/core/test-invocation-policy.sh" || true
}

# Test: Team templates reference agents that exist
test_team_templates() {
    echo ""
    log_info "Testing team templates (agent resolution)"

    run_subtest "Team template tests pass" "$SCRIPT_DIR/core/test-team-templates.sh" || true
}

# Test: Legacy command (content validation)
test_legacy_command() {
    echo ""
    log_info "Testing legacy command (content)"

    run_subtest "Legacy command tests pass" "$SCRIPT_DIR/core/test-legacy-command.sh" || true
}

# Test: Hotspot analysis tool (functional)
test_hotspot_analysis() {
    echo ""
    log_info "Testing hotspot analysis tool (functional)"

    run_subtest "Hotspot analysis tests pass" "$SCRIPT_DIR/core/test-hotspot-analysis.sh" || true
}

# Test: Quick setup (content validation)
test_quick_setup() {
    echo ""
    log_info "Testing quick setup mode (content)"

    run_subtest "Quick setup tests pass" "$SCRIPT_DIR/core/test-quick-setup.sh" || true
}

# Test: Dog-fooding (plugin validates its own code)
test_dogfood() {
    echo ""
    log_info "Testing dog-fooding (self-validation)"

    run_subtest "Dog-fooding tests pass" "$SCRIPT_DIR/core/test-dogfood.sh" || true
}

# Main test runner
main() {
    echo "=================================================="
    echo " AI Craftsman Superpowers - Test Suite"
    echo "=================================================="
    echo ""
    echo "Root directory: $ROOT_DIR"
    echo "Plugin directory: $PLUGIN_DIR"
    echo ""

    # Run tests
    if [[ -n "$SPECIFIC_SKILL" ]]; then
        # Test specific skill only (handles namespace/subskill notation like "craftsman/session-init")
        local skill_path="$SKILLS_DIR/$SPECIFIC_SKILL"
        if [[ -d "$skill_path" ]]; then
            # Check if this is a namespace
            local has_subskills=false
            for subdir in "$skill_path"/*; do
                if [[ -d "$subdir" ]] && [[ -f "$subdir/SKILL.md" ]]; then
                    has_subskills=true
                    break
                fi
            done

            if [[ "$has_subskills" == true ]]; then
                log_info "Namespace: $SPECIFIC_SKILL"
                for subdir in "$skill_path"/*; do
                    if [[ -d "$subdir" ]]; then
                        test_skill_structure "$subdir"
                    fi
                done
            else
                test_skill_structure "$skill_path"
            fi
        else
            log_error "Skill not found: $SPECIFIC_SKILL"
            exit 1
        fi
    else
        # Test all skills (handling namespaces)
        for skill_dir in "$SKILLS_DIR"/*; do
            if [[ -d "$skill_dir" ]]; then
                # Check if this is a namespace (contains subdirectories with SKILL.md)
                has_subskills=false
                for subdir in "$skill_dir"/*; do
                    if [[ -d "$subdir" ]] && [[ -f "$subdir/SKILL.md" ]]; then
                        has_subskills=true
                        break
                    fi
                done

                if [[ "$has_subskills" == true ]]; then
                    # This is a namespace - validate sub-skills
                    namespace_name=$(basename "$skill_dir")
                    echo ""
                    log_info "Namespace: $namespace_name"
                    for subdir in "$skill_dir"/*; do
                        if [[ -d "$subdir" ]]; then
                            test_skill_structure "$subdir"
                        fi
                    done
                else
                    # This is a direct skill
                    test_skill_structure "$skill_dir"
                fi
            fi
        done

        # Test other components
        test_hooks
        test_plugin_manifest
        test_knowledge_base
        test_examples
        test_adrs

        test_hook_behavior
        test_agent_hooks
        test_hostile_repo
        test_dynamic_context
        test_ratchet
        test_design_panel
        test_okf_knowledge
        test_dashboard
        test_tooling_detect
        test_verify_loop
        test_observation
        test_instincts
        test_config_protection
        test_security_invariants
        test_config_resolution
        test_bias_detector
        test_correction_learning
        test_session_metrics
        test_knowledge_integrity
        test_template_suite
        test_pack_suites
        test_craftsman_ci
        test_workflow_command
        test_legacy_command
        test_invocation_policy
        test_team_templates
        test_hotspot_analysis
        test_quick_setup
        test_dogfood
    fi

    # Summary
    echo ""
    echo "=================================================="
    echo " Test Summary"
    echo "=================================================="
    echo -e " ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e " ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e " ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo "=================================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        log_error "Some tests failed!"
        exit 1
    else
        echo ""
        log_info "All tests passed!"
        exit 0
    fi
}

main
