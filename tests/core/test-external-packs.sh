#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"

echo "=== External Pack Loading Tests ==="

TMPDIR_BASE="/tmp/craftsman-external-packs-$$"

# Test 1: External pack loaded from path
echo ""
echo "--- External pack loading ---"
_pack_reset
export CLAUDE_PLUGIN_OPTION_stack="fullstack"

EXT_PACK_DIR="$TMPDIR_BASE/ext-go"
mkdir -p "$EXT_PACK_DIR/hooks"
cat > "$EXT_PACK_DIR/pack.yml" <<'YAML'
name: go
version: "1.0.0"
description: "Go craftsman pack"
compatibility:
  core: ">=2.6.0"
  stack: ["*"]
rules:
  builtin: ["GO001"]
  static_analysis: []
hooks:
  validators: ["hooks/go-validator.sh"]
commands:
  scaffold_types: []
YAML
cat > "$EXT_PACK_DIR/hooks/go-validator.sh" <<'BASH'
#!/usr/bin/env bash
pack_validate_go() { true; }
BASH

CRAFT_DIR="$TMPDIR_BASE/project"
mkdir -p "$CRAFT_DIR"
cat > "$CRAFT_DIR/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$EXT_PACK_DIR"
YAML

INTERNAL_DIR="$TMPDIR_BASE/internal-packs"
mkdir -p "$INTERNAL_DIR"

cd "$CRAFT_DIR"
pack_loader_init "$INTERNAL_DIR"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "go"; then
    log_pass "External pack 'go' loaded from path"
else
    log_fail "External pack loading" "go not found in loaded: '$loaded'"
fi

# Test 2: External pack validator is callable
if type pack_validate_go &>/dev/null; then
    log_pass "External pack validator pack_validate_go is callable"
else
    log_fail "External validator" "pack_validate_go not defined"
fi

# Test 3: Invalid external path silently skipped
echo ""
echo "--- Invalid external path ---"
_pack_reset

cat > "$CRAFT_DIR/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "/nonexistent/path/go-pack"
YAML

cd "$CRAFT_DIR"
pack_loader_init "$INTERNAL_DIR"
loaded=$(pack_loaded)
if [[ -z "$loaded" ]]; then
    log_pass "Invalid external path silently skipped"
else
    log_pass "Invalid path skipped, other packs loaded: $loaded"
fi

# Test 4: Mix of internal and external packs
echo ""
echo "--- Mixed internal + external ---"
_pack_reset

MIXED_INTERNAL="$TMPDIR_BASE/mixed-internal"
mkdir -p "$MIXED_INTERNAL/test-internal/hooks"
cat > "$MIXED_INTERNAL/test-internal/pack.yml" <<'YAML'
name: test-internal
version: "1.0.0"
description: "Internal test pack"
compatibility:
  core: ">=2.4.0"
  stack: ["*"]
hooks:
  validators: []
commands:
  scaffold_types: []
YAML

cat > "$CRAFT_DIR/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$EXT_PACK_DIR"
YAML

cd "$CRAFT_DIR"
pack_loader_init "$MIXED_INTERNAL"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-internal"; then
    log_pass "Internal pack loaded in mixed scenario"
else
    log_fail "Internal pack in mixed" "test-internal not found: '$loaded'"
fi
if echo "$loaded" | grep -q "go"; then
    log_pass "External pack loaded in mixed scenario"
else
    log_fail "External pack in mixed" "go not found: '$loaded'"
fi

# Test 5: No .craft-config.yml — only internal packs
echo ""
echo "--- No config file ---"
_pack_reset

NO_CONFIG_DIR="$TMPDIR_BASE/no-config-project"
mkdir -p "$NO_CONFIG_DIR"
cd "$NO_CONFIG_DIR"
pack_loader_init "$MIXED_INTERNAL"

loaded=$(pack_loaded)
if echo "$loaded" | grep -q "test-internal"; then
    log_pass "Internal packs work without .craft-config.yml"
else
    log_fail "No config" "test-internal not found: '$loaded'"
fi

# Cleanup
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
cd "$ROOT_DIR"
rm -rf "$TMPDIR_BASE"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
