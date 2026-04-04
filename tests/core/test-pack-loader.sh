#!/usr/bin/env bash
# =============================================================================
# Pack Loader Tests
# Tests pack-loader.sh: discovery, stack filtering, wildcard, validator delegation
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"

# Fixture helper — creates a minimal pack in a temp packs dir
TEST_PACKS_DIR="/tmp/craftsman-pack-loader-tests-$$"
mkdir -p "$TEST_PACKS_DIR"

_make_pack() {
    local pack_name="$1"
    local stack_line="$2"         # e.g. '["symfony", "fullstack"]' or '["*"]'
    local scaffold_types="${3:-}"  # optional, e.g. 'entity'
    local validator_fn="${4:-}"    # optional bash function body

    local pack_dir="$TEST_PACKS_DIR/$pack_name"
    mkdir -p "$pack_dir"

    cat > "$pack_dir/pack.yml" <<YAML
name: ${pack_name}
version: "1.0.0"
description: "Test pack ${pack_name}"
compatibility:
  core: ">=2.4.0"
  stack: ${stack_line}

hooks:
  validators: ["hooks/validator.sh"]

commands:
  scaffold_types: [${scaffold_types}]
YAML

    mkdir -p "$pack_dir/hooks"
    if [[ -n "$validator_fn" ]]; then
        printf '%s\n' "#!/usr/bin/env bash" "$validator_fn" > "$pack_dir/hooks/validator.sh"
    else
        printf '%s\n' "#!/usr/bin/env bash" "# no-op validator" > "$pack_dir/hooks/validator.sh"
    fi
}

# =============================================================================
# 1. Pack discovery — matching stack is loaded
# =============================================================================
echo ""
echo "=== Pack Discovery ==="

_pack_reset
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
export CLAUDE_PLUGIN_OPTION_stack="symfony"

_make_pack "test-symfony" '["symfony", "fullstack"]' '"entity"'
pack_loader_init "$TEST_PACKS_DIR"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-symfony"; then
    log_pass "test-symfony pack discovered when stack=symfony"
else
    log_fail "Pack discovery" "test-symfony not found in loaded packs: '$loaded'"
fi

# =============================================================================
# 2. Stack compatibility filter — mismatched stack is skipped
# =============================================================================
echo ""
echo "=== Stack Compatibility Filter ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

_make_pack "test-react-only" '["react"]' '"component"'
pack_loader_init "$TEST_PACKS_DIR"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-react-only"; then
    log_fail "Stack filter" "test-react-only should NOT be loaded when stack=symfony, but was"
else
    log_pass "test-react-only skipped when stack=symfony (react-only pack filtered out)"
fi

# Symfony pack should still be there
if echo "$loaded" | grep -q "test-symfony"; then
    log_pass "test-symfony still loaded alongside filtered react pack"
else
    log_fail "test-symfony should still be loaded" "got: '$loaded'"
fi

# =============================================================================
# 3. Wildcard stack — loads for any stack
# =============================================================================
echo ""
echo "=== Wildcard Stack ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

_make_pack "test-wildcard" '["*"]'
pack_loader_init "$TEST_PACKS_DIR"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-wildcard"; then
    log_pass "Wildcard pack loaded when stack=symfony"
else
    log_fail "Wildcard pack" "test-wildcard not loaded: '$loaded'"
fi

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="react"
pack_loader_init "$TEST_PACKS_DIR"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-wildcard"; then
    log_pass "Wildcard pack loaded when stack=react"
else
    log_fail "Wildcard pack (react stack)" "test-wildcard not loaded: '$loaded'"
fi

# =============================================================================
# 4. Validator delegation — pack_run_validators calls sourced function
# =============================================================================
echo ""
echo "=== Validator Delegation ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

VALIDATOR_CALLED=""
_make_pack "test-validator" '["symfony"]' '' \
    'pack_validate_php() { export VALIDATOR_CALLED="yes:$1"; }'

pack_loader_init "$TEST_PACKS_DIR"
pack_run_validators "/some/file.php" "php"

if [[ "${VALIDATOR_CALLED:-}" == "yes:/some/file.php" ]]; then
    log_pass "pack_run_validators delegated to pack_validate_php with correct file arg"
else
    log_fail "Validator delegation" "VALIDATOR_CALLED='${VALIDATOR_CALLED:-}', expected 'yes:/some/file.php'"
fi

# Verify no call for unknown lang
VALIDATOR_CALLED=""
pack_run_validators "/some/file.rb" "ruby"
if [[ -z "${VALIDATOR_CALLED:-}" ]]; then
    log_pass "pack_run_validators is a no-op for unknown lang (ruby)"
else
    log_fail "Unknown lang should be no-op" "VALIDATOR_CALLED='${VALIDATOR_CALLED}'"
fi

# =============================================================================
# 5. pack_list_scaffold_types — returns pack_name:type per loaded pack
# =============================================================================
echo ""
echo "=== Scaffold Types ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

_make_pack "test-scaffold" '["symfony"]' '"entity", "usecase"'
pack_loader_init "$TEST_PACKS_DIR"

types=$(pack_list_scaffold_types)
if echo "$types" | grep -q "test-scaffold:entity"; then
    log_pass "Scaffold type 'entity' listed as test-scaffold:entity"
else
    log_fail "Scaffold types" "entity not found in: '$types'"
fi
if echo "$types" | grep -q "test-scaffold:usecase"; then
    log_pass "Scaffold type 'usecase' listed as test-scaffold:usecase"
else
    log_fail "Scaffold types" "usecase not found in: '$types'"
fi

# =============================================================================
# 6. pack_sync_symlinks — creates and cleans symlinks
# =============================================================================
echo ""
echo "=== Symlink Sync ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

SYMLINK_ROOT="/tmp/craftsman-symlink-test-$$"
mkdir -p "$SYMLINK_ROOT/agents" "$SYMLINK_ROOT/commands"

SYMLINK_PACK_DIR="$TEST_PACKS_DIR/test-symlink"
mkdir -p "$SYMLINK_PACK_DIR/agents" "$SYMLINK_PACK_DIR/commands"
cat > "$SYMLINK_PACK_DIR/pack.yml" <<YAML
name: test-symlink
version: "1.0.0"
description: "Symlink test pack"
compatibility:
  core: ">=2.4.0"
  stack: ["symfony"]
hooks:
  validators: []
commands:
  scaffold_types: []
YAML
touch "$SYMLINK_PACK_DIR/agents/my-agent.md"
touch "$SYMLINK_PACK_DIR/commands/my-command.md"

# Create a stale symlink that should be cleaned
ln -sf "/nonexistent/stale.md" "$SYMLINK_ROOT/agents/stale-agent.md"

CLAUDE_PLUGIN_ROOT="$SYMLINK_ROOT" pack_loader_init "$TEST_PACKS_DIR"
CLAUDE_PLUGIN_ROOT="$SYMLINK_ROOT" pack_sync_symlinks

if [[ -L "$SYMLINK_ROOT/agents/my-agent.md" ]]; then
    log_pass "Symlink created for pack agent: my-agent.md"
else
    log_fail "Symlink creation" "agents/my-agent.md symlink missing"
fi

if [[ -L "$SYMLINK_ROOT/commands/my-command.md" ]]; then
    log_pass "Symlink created for pack command: my-command.md"
else
    log_fail "Symlink creation" "commands/my-command.md symlink missing"
fi

if [[ ! -e "$SYMLINK_ROOT/agents/stale-agent.md" ]]; then
    log_pass "Stale symlink cleaned by pack_sync_symlinks"
else
    log_fail "Stale symlink cleanup" "stale-agent.md still present"
fi

rm -rf "$SYMLINK_ROOT"

# =============================================================================
# 7. _pack_reset — clears all state
# =============================================================================
echo ""
echo "=== State Reset ==="

export CLAUDE_PLUGIN_OPTION_stack="symfony"
pack_loader_init "$TEST_PACKS_DIR"
_pack_reset

loaded=$(pack_loaded)
if [[ -z "$loaded" ]]; then
    log_pass "_pack_reset clears loaded pack list"
else
    log_fail "_pack_reset" "loaded packs not empty after reset: '$loaded'"
fi

types=$(pack_list_scaffold_types)
if [[ -z "$types" ]]; then
    log_pass "_pack_reset clears scaffold types"
else
    log_fail "_pack_reset" "scaffold types not empty after reset: '$types'"
fi

# =============================================================================
# 8. Integration: Symlink creation for agents and commands
# =============================================================================
echo ""
echo "=== Integration: Symlink Creation ==="

_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="symfony"

INTEG_ROOT="/tmp/craftsman-integ-symlink-$$"
mkdir -p "$INTEG_ROOT/packs/test-pack/agents" "$INTEG_ROOT/packs/test-pack/commands"
mkdir -p "$INTEG_ROOT/agents" "$INTEG_ROOT/commands"

cat > "$INTEG_ROOT/packs/test-pack/pack.yml" <<'YAML'
name: test-pack
version: "1.0.0"
description: "Test pack"
compatibility:
  core: ">=2.4.0"
  stack: ["symfony", "fullstack"]
hooks:
  validators: []
agents: ["agents/test-agent.md"]
commands: []
YAML
echo -e "---\nname: test-agent\n---" > "$INTEG_ROOT/packs/test-pack/agents/test-agent.md"
echo -e "---\ndescription: test\n---" > "$INTEG_ROOT/packs/test-pack/commands/test-cmd.md"

CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_loader_init "$INTEG_ROOT/packs"
CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_sync_symlinks

if [[ -L "$INTEG_ROOT/agents/test-agent.md" ]]; then
    log_pass "Integration: agent symlink created in agents/"
else
    log_fail "Integration: agent symlink creation" "agents/test-agent.md symlink missing"
fi

if [[ -L "$INTEG_ROOT/commands/test-cmd.md" ]]; then
    log_pass "Integration: command symlink created in commands/"
else
    log_fail "Integration: command symlink creation" "commands/test-cmd.md symlink missing"
fi

# =============================================================================
# 9. Integration: Stale symlink cleanup
# =============================================================================
echo ""
echo "=== Integration: Stale Symlink Cleanup ==="

ln -sf "/nonexistent/old-agent.md" "$INTEG_ROOT/agents/old-agent.md"

_pack_reset
CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_loader_init "$INTEG_ROOT/packs"
CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_sync_symlinks

if [[ ! -L "$INTEG_ROOT/agents/old-agent.md" && ! -e "$INTEG_ROOT/agents/old-agent.md" ]]; then
    log_pass "Integration: stale symlink removed by pack_sync_symlinks"
else
    log_fail "Integration: stale symlink cleanup" "old-agent.md still present"
fi

if [[ -L "$INTEG_ROOT/agents/test-agent.md" ]]; then
    log_pass "Integration: valid symlink preserved after stale cleanup"
else
    log_fail "Integration: valid symlink preserved" "test-agent.md missing after stale cleanup"
fi

# =============================================================================
# 10. Integration: Real files not deleted by cleanup
# =============================================================================
echo ""
echo "=== Integration: Real Files Not Deleted ==="

echo "real file content" > "$INTEG_ROOT/agents/real-agent.md"

_pack_reset
CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_loader_init "$INTEG_ROOT/packs"
CLAUDE_PLUGIN_ROOT="$INTEG_ROOT" pack_sync_symlinks

if [[ -f "$INTEG_ROOT/agents/real-agent.md" && ! -L "$INTEG_ROOT/agents/real-agent.md" ]]; then
    log_pass "Integration: real file preserved (not deleted by symlink cleanup)"
else
    log_fail "Integration: real file preservation" "real-agent.md was deleted or turned into symlink"
fi

rm -rf "$INTEG_ROOT"

# =============================================================================
# Cleanup
# =============================================================================
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
rm -rf "$TEST_PACKS_DIR"

test_summary
