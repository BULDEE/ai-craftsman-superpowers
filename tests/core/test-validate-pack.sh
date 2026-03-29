#!/usr/bin/env bash
# =============================================================================
# test-validate-pack.sh — Tests for scripts/validate-pack.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
VALIDATE_SCRIPT="${ROOT_DIR}/scripts/validate-pack.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1: $2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Temp directory — cleaned up on exit
TEST_TMP="$(mktemp -d /tmp/craftsman_validate_pack_XXXXXX)"
trap 'rm -rf "$TEST_TMP"' EXIT

# =============================================================================
# Helper: create a minimal valid pack in a given directory
# =============================================================================
make_valid_pack() {
    local dir="$1"
    mkdir -p "${dir}/hooks" "${dir}/agents"
    cat > "${dir}/pack.yml" << 'YAML'
name: test-valid
version: "1.0.0"
description: "A valid test pack"
compatibility:
  core: ">=2.5.0"
  stack: ["*"]
rules:
  builtin: ["TEST001"]
  static_analysis: []
hooks:
  validators: ["hooks/test-validator.sh"]
commands:
  scaffold_types: []
agents: ["agents/test-agent.md"]
knowledge: ["knowledge/"]
YAML
    # Create referenced validator
    printf '#!/usr/bin/env bash\npack_validate_test() { true; }\n' > "${dir}/hooks/test-validator.sh"
    chmod +x "${dir}/hooks/test-validator.sh"
    # Create referenced agent (with allowedTools)
    printf -- '---\nname: test-agent\nmodel: sonnet\nallowedTools: [Read, Glob, Grep, Bash]\n---\n# Test Agent\n' \
        > "${dir}/agents/test-agent.md"
}

# =============================================================================
# 1. Valid pack passes (exit 0)
# =============================================================================
echo ""
echo "=== 1. Valid pack passes ==="

PACK1="${TEST_TMP}/pack-valid"
make_valid_pack "$PACK1"

output=$(bash "$VALIDATE_SCRIPT" "$PACK1" 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_pass "Valid pack exits 0"
else
    log_fail "Valid pack exits 0" "got exit code ${exit_code}"
fi

if echo "$output" | grep -q "0 errors"; then
    log_pass "Valid pack reports 0 errors"
else
    log_fail "Valid pack reports 0 errors" "output: ${output}"
fi

# =============================================================================
# 2. Missing pack.yml fails (exit 2)
# =============================================================================
echo ""
echo "=== 2. Missing pack.yml fails ==="

PACK2="${TEST_TMP}/pack-no-yml"
mkdir -p "$PACK2"

exit_code=0
bash "$VALIDATE_SCRIPT" "$PACK2" >/dev/null 2>&1 || exit_code=$?

if [[ $exit_code -eq 2 ]]; then
    log_pass "Missing pack.yml exits 2"
else
    log_fail "Missing pack.yml exits 2" "got exit code ${exit_code}"
fi

# =============================================================================
# 3. Missing referenced validator file fails (exit 2) and error mentions filename
# =============================================================================
echo ""
echo "=== 3. Missing referenced validator fails ==="

PACK3="${TEST_TMP}/pack-missing-validator"
make_valid_pack "$PACK3"
# Remove the validator that is referenced in pack.yml
rm -f "${PACK3}/hooks/test-validator.sh"

output=$(bash "$VALIDATE_SCRIPT" "$PACK3" 2>&1)
exit_code=$?

if [[ $exit_code -eq 2 ]]; then
    log_pass "Missing validator exits 2"
else
    log_fail "Missing validator exits 2" "got exit code ${exit_code}"
fi

if echo "$output" | grep -q "test-validator.sh"; then
    log_pass "Error message mentions the missing filename"
else
    log_fail "Error message mentions the missing filename" "output: ${output}"
fi

# =============================================================================
# 4. Missing required 'name' field fails (exit 2)
# =============================================================================
echo ""
echo "=== 4. Missing required field 'name' fails ==="

PACK4="${TEST_TMP}/pack-no-name"
make_valid_pack "$PACK4"
# Remove the name field (macOS-compatible sed -i '')
sed -i '' '/^name:/d' "${PACK4}/pack.yml"

exit_code=0
bash "$VALIDATE_SCRIPT" "$PACK4" >/dev/null 2>&1 || exit_code=$?

if [[ $exit_code -eq 2 ]]; then
    log_pass "Missing 'name' field exits 2"
else
    log_fail "Missing 'name' field exits 2" "got exit code ${exit_code}"
fi

# =============================================================================
# 5. Agent without allowedTools produces warning
# =============================================================================
echo ""
echo "=== 5. Agent missing allowedTools produces warning ==="

PACK5="${TEST_TMP}/pack-agent-no-tools"
make_valid_pack "$PACK5"
# Overwrite agent file without allowedTools
printf -- '---\nname: test-agent\nmodel: sonnet\n---\n# Test Agent\n' \
    > "${PACK5}/agents/test-agent.md"

output=$(bash "$VALIDATE_SCRIPT" "$PACK5" 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_pass "Pack with agent missing allowedTools still exits 0 (warning only)"
else
    log_fail "Pack with agent missing allowedTools still exits 0" "got exit code ${exit_code}"
fi

if echo "$output" | grep -qi "WARN.*allowedTools\|allowedTools.*WARN\|missing allowedTools"; then
    log_pass "Warning produced for agent missing allowedTools"
else
    log_fail "Warning produced for agent missing allowedTools" "output: ${output}"
fi

# =============================================================================
# 6. exit 1 in validator detected in output
# =============================================================================
echo ""
echo "=== 6. exit 1 in validator script is detected ==="

PACK6="${TEST_TMP}/pack-exit1-validator"
make_valid_pack "$PACK6"
# Overwrite validator with an exit 1
printf '#!/usr/bin/env bash\nif true; then\n  exit 1\nfi\n' > "${PACK6}/hooks/test-validator.sh"
chmod +x "${PACK6}/hooks/test-validator.sh"

output=$(bash "$VALIDATE_SCRIPT" "$PACK6" 2>&1)
exit_code=$?

if [[ $exit_code -eq 2 ]]; then
    log_pass "exit 1 in validator causes validation to fail"
else
    log_fail "exit 1 in validator causes validation to fail" "got exit code ${exit_code}"
fi

if echo "$output" | grep -qi "exit 1"; then
    log_pass "Output mentions 'exit 1' issue"
else
    log_fail "Output mentions 'exit 1' issue" "output: ${output}"
fi

# =============================================================================
# 7. All 3 built-in packs pass validation
# =============================================================================
echo ""
echo "=== 7. Built-in packs pass validation ==="

PACKS_ROOT="${ROOT_DIR}/packs"
for pack_name in symfony react ai-ml; do
    pack_dir="${PACKS_ROOT}/${pack_name}"
    exit_code=0
    bash "$VALIDATE_SCRIPT" "$pack_dir" >/dev/null 2>&1 || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Built-in pack '${pack_name}' passes validation (exit 0)"
    else
        log_fail "Built-in pack '${pack_name}' passes validation" "got exit code ${exit_code}"
    fi
done

# =============================================================================
# 8. Rule ID collision detection with --check-collisions
# =============================================================================
echo ""
echo "=== 8. Rule ID collision detection ==="

# Create two packs that share a rule ID
COLL_DIR="${TEST_TMP}/collision-packs"
PACK_A="${COLL_DIR}/pack-a"
PACK_B="${COLL_DIR}/pack-b"
mkdir -p "${PACK_A}/agents" "${PACK_B}/agents"

cat > "${PACK_A}/pack.yml" << 'YAML'
name: pack-a
version: "1.0.0"
description: "Pack A"
compatibility:
  stack: ["*"]
rules:
  builtin: ["SHARED001", "UNIQUE_A001"]
hooks:
  validators: []
agents: []
YAML

cat > "${PACK_B}/pack.yml" << 'YAML'
name: pack-b
version: "1.0.0"
description: "Pack B"
compatibility:
  stack: ["*"]
rules:
  builtin: ["SHARED001", "UNIQUE_B001"]
hooks:
  validators: []
agents: []
YAML

# Pack A should detect collision with Pack B's SHARED001
output=$(bash "$VALIDATE_SCRIPT" "$PACK_A" --check-collisions "$COLL_DIR" 2>&1)
exit_code=$?

if [[ $exit_code -eq 2 ]]; then
    log_pass "Collision detection causes exit 2"
else
    log_fail "Collision detection causes exit 2" "got exit code ${exit_code}"
fi

if echo "$output" | grep -q "SHARED001"; then
    log_pass "Collision output mentions the colliding rule ID 'SHARED001'"
else
    log_fail "Collision output mentions the colliding rule ID 'SHARED001'" "output: ${output}"
fi

if echo "$output" | grep -q "pack-b"; then
    log_pass "Collision output mentions the other pack name 'pack-b'"
else
    log_fail "Collision output mentions the other pack name 'pack-b'" "output: ${output}"
fi

# Unique rule should NOT be flagged
if echo "$output" | grep -q "UNIQUE_A001"; then
    log_fail "Non-colliding rule UNIQUE_A001 incorrectly flagged" "output: ${output}"
else
    log_pass "Non-colliding rule UNIQUE_A001 not flagged"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo "============================================="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 2
fi
exit 0
