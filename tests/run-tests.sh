#!/bin/bash
# AI Craftsman Superpowers - Test Suite
# Run with: ./tests/run-tests.sh [--skill <name>] [--verbose]

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

    # Test 3: Has name field
    if grep -q "^name:" "$skill_file"; then
        log_pass "Has 'name' field"
    else
        log_fail "Missing 'name' field"
    fi

    # Test 4: Has description field
    if grep -q "^description:" "$skill_file"; then
        log_pass "Has 'description' field"
    else
        log_fail "Missing 'description' field"
    fi

    # Test 5: Has model field (new requirement)
    if grep -q "^model:" "$skill_file"; then
        local model=$(grep "^model:" "$skill_file" | head -1 | cut -d: -f2 | tr -d ' ')
        if [[ "$model" =~ ^(haiku|sonnet|opus)$ ]]; then
            log_pass "Has valid 'model' field: $model"
        else
            log_fail "Invalid model value: $model (must be haiku|sonnet|opus)"
        fi
    else
        # session-init is allowed to not have model
        if [[ "$skill_name" == "session-init" ]]; then
            log_skip "'model' field (session-init exempt)"
        else
            log_fail "Missing 'model' field"
        fi
    fi

    # Test 6: Has allowed-tools field
    if grep -q "^allowed-tools:" "$skill_file"; then
        log_pass "Has 'allowed-tools' field"
    else
        log_warn "Missing 'allowed-tools' field (not required but recommended)"
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
    local scripts=("post-write-check.sh" "bias-detector.sh")
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
    local core_adrs=("001-model-tiering.md" "002-context-fork-strategy.md")
    for adr in "${core_adrs[@]}"; do
        if [[ -f "$adr_dir/$adr" ]]; then
            log_pass "ADR exists: $adr"
        else
            log_fail "ADR missing: $adr"
        fi
    done
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
