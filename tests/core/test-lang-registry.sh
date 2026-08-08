#!/usr/bin/env bash
# =============================================================================
# Language registry tests - the file-to-validator routing must come from the
# loaded packs, never from a literal in the engine.
#
# Every assertion here is paired with a known-good control that exercises the
# same harness on a language the engine already knows. Without the control, a
# red result cannot be told apart from a broken fixture, and a green one cannot
# be told apart from a test that never ran the tool.
#
# These are expected to FAIL until the registry lands. That is the point: a
# guard never seen red proves nothing.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
setup_test_env
backup_home_bridges

TMPDIR_BASE="/tmp/craftsman-lang-registry-$$"
PROJECT_DIR="$TMPDIR_BASE/project/src"
mkdir -p "$PROJECT_DIR"

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

# hook_exit <file> - run post-write-check against a path, return its exit code
hook_exit() {
    local target="$1"
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1
    echo $?
}

# hook_output <file> - run post-write-check against a path, return its stdout
hook_output() {
    local target="$1"
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>/dev/null
}

echo "=== Language Registry Tests ==="

# --- Fixtures -----------------------------------------------------------------
# A deliberately non-compliant PHP file: no strict_types, non-final class with a
# public setter. It is the control subject, so it must stay in breach of a rule
# the engine blocks on today.
cat > "$PROJECT_DIR/Dirty.php" <<'PHP'
<?php

class Dirty
{
    public $name;

    public function setName($name)
    {
        $this->name = $name;
    }
}
PHP

# Clean PHP: present only to make FILES_DISCOVERED non-zero, so the CI parity
# test reproduces the dangerous case (a mixed repository) rather than the benign
# one where the "no source file was found" guard already speaks up.
cat > "$PROJECT_DIR/Clean.php" <<'PHP'
<?php

declare(strict_types=1);

final class Clean
{
    private function __construct(private readonly string $name)
    {
    }

    public static function create(string $name): self
    {
        return new self($name);
    }
}
PHP

cat > "$PROJECT_DIR/bad.py" <<'PY'
def collect(items=[]):
    try:
        return items
    except:
        return None
PY

cat > "$PROJECT_DIR/bad.sh" <<'SH'
#!/usr/bin/env bash
echo "no safety options set"
SH

cat > "$PROJECT_DIR/service.go" <<'GO'
package main

func main() {
	panic("deliberately in breach of GO001")
}
GO

# --- External pack declaring a language ---------------------------------------
EXT_PACK_DIR="$TMPDIR_BASE/ext-go"
mkdir -p "$EXT_PACK_DIR/hooks"
cat > "$EXT_PACK_DIR/pack.yml" <<'YAML'
name: go
version: "1.0.0"
description: "Go craftsman pack"
compatibility:
  core: ">=2.6.0"
  stack: ["*"]
languages:
  - id: go
    extensions: ["go"]
    entry_markers: ["go.mod"]
    protected_configs: ["golangci.yml"]
    # Deliberately not `go test`: that string is already in the hook's literal
    # list, so it would pass whether or not the registry is consulted.
    test_commands: ["gotestsum"]
    lsp: "gopls"
    validators: ["hooks/go-validator.sh"]
    metrics_dialect: c-like
rules:
  builtin: ["GO001"]
hooks:
  validators: ["hooks/go-validator.sh"]
commands:
  scaffold_types: []
YAML

cat > "$EXT_PACK_DIR/hooks/go-validator.sh" <<'BASH'
#!/usr/bin/env bash
pack_validate_go() {
    local file="$1"
    if grep -q 'panic(' "$file" 2>/dev/null; then
        add_violation "GO001" "panic() in production code - return an error"
    fi
}
BASH

cat > "$HOME/.claude/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$EXT_PACK_DIR"
YAML

cd "$TMPDIR_BASE/project" || exit 1

# =============================================================================
# Group A - a language contributed by a pack is routed to its validator
# =============================================================================
echo ""
echo "--- A. Pack-contributed language reaches its validator ---"

php_code=$(hook_exit "$PROJECT_DIR/Dirty.php")
if [[ "$php_code" == "2" ]]; then
    log_pass "control: the hook blocks a non-compliant PHP file (exit 2)"

    go_code=$(hook_exit "$PROJECT_DIR/service.go")
    if [[ "$go_code" == "2" ]]; then
        log_pass "a .go file reaches pack_validate_go and blocks on GO001"
    else
        log_fail "pack-contributed language routed" \
            "expected exit 2 on service.go, got $go_code - the engine's extension list does not include a language its loaded packs declare"
    fi
else
    log_fail "control: hook does not block a non-compliant PHP file" \
        "expected exit 2, got $php_code - the routing assertion below is undetermined, not green"
fi

# The validator being callable is not the same as it being called. The old test
# asserted only the former, which is why it stayed green while the feature was
# dead.
source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/pack-loader.sh"
_pack_reset
pack_loader_init "$TMPDIR_BASE/no-internal-packs"
if type pack_validate_go &>/dev/null; then
    log_pass "control: pack_validate_go is defined after loading (necessary, not sufficient)"
else
    log_fail "control: external pack did not load" "pack_validate_go undefined"
fi

# =============================================================================
# Group B - the pipeline sees every file the hook sees
# =============================================================================
echo ""
echo "--- B. Hook and CI agree on which files are validated ---"

ci_output=$(bash "$ROOT_DIR/ci/craftsman-ci.sh" src 2>&1)

if assert_produced_output "craftsman-ci" "$ci_output"; then
    if echo "$ci_output" | grep -qiE 'PHP[0-9]{3}|LAYER[0-9]{3}'; then
        log_pass "control: CI reports violations on the non-compliant PHP file"

        py_hook_code=$(hook_exit "$PROJECT_DIR/bad.py")
        if [[ "$py_hook_code" == "2" ]]; then
            log_pass "control: the hook blocks bad.py (PY004/PY005)"

            if echo "$ci_output" | grep -qE 'PY00[0-9]'; then
                log_pass "CI reports the same Python violations the hook blocks on"
            else
                log_fail "hook/CI parity on Python" \
                    "hook exits 2 on bad.py, CI reports no PY rule - the pipeline never discovered the file"
            fi
        else
            log_fail "control: hook does not block bad.py" \
                "expected exit 2, got $py_hook_code - the parity assertion is undetermined"
        fi

        # A single PHP file must not silence the empty-gate guard for the other
        # languages present. FILES_DISCOVERED counting only php|ts|tsx is what
        # turns a mixed repository into a silent pass.
        # Take the number immediately before "file(s)". Reading the first
        # integer on the line picks up the violation count instead, which made
        # this assertion pass for the wrong reason the first time it went green.
        scanned_line=$(echo "$ci_output" | grep -iE '[0-9]+ file\(s\)' | head -1)
        scanned_count=$(echo "$scanned_line" \
            | grep -oE '[0-9]+ file\(s\)' | grep -oE '^[0-9]+')
        if [[ -n "$scanned_count" && "$scanned_count" -ge 5 ]]; then
            log_pass "CI counts every file a loaded pack claims (got $scanned_count)"
        else
            log_fail "CI file discovery covers loaded packs" \
                "reported '${scanned_line:-nothing}' for 5 claimed files - Python, Bash and Go were never discovered"
        fi
    else
        log_fail "control: CI reports nothing on a non-compliant PHP file" \
            "the CI harness itself is not working, so the parity assertions below are undetermined"
    fi
fi

# =============================================================================
# Group C - severity is resolved by the rules engine, for every rule
# =============================================================================
echo ""
echo "--- C. Rule severity honours project configuration ---"

# Control: a rule that already flows through add_violation must obey an
# `ignore` override. This proves the rules engine is wired into the hook.
cat > "$TMPDIR_BASE/project/.craft-rules.yml" <<'YAML'
rules:
  PHP001: ignore
  PHP002: ignore
  PHP003: ignore
  PHP004: ignore
  PHP005: ignore
  LAYER001: ignore
  LAYER002: ignore
  LAYER003: ignore
  LAYER004: ignore
YAML

php_ignored_code=$(hook_exit "$PROJECT_DIR/Dirty.php")
if [[ "$php_ignored_code" == "0" ]]; then
    log_pass "control: an 'ignore' override in .craft-rules.yml suppresses a blocking rule"
else
    log_fail "control: rules engine override has no effect" \
        "expected exit 0 with every PHP rule ignored, got $php_ignored_code - Group C assertions are undetermined"
fi

# SH001 is declared a blocking rule in ci/doctrine-export.sh but emitted through
# add_warning, which never consults the rules engine. Promoting it must work.
cat > "$TMPDIR_BASE/project/.craft-rules.yml" <<'YAML'
rules:
  SH001: block
YAML

sh_block_code=$(hook_exit "$PROJECT_DIR/bad.sh")
if [[ "$sh_block_code" == "2" ]]; then
    log_pass "SH001 promoted to block by .craft-rules.yml actually blocks"
else
    log_fail "warning-severity rules are configurable" \
        "expected exit 2 with SH001: block, got $sh_block_code - add_warning bypasses rules_severity_for_file, so user configuration has no purchase on it"
fi

cat > "$TMPDIR_BASE/project/.craft-rules.yml" <<'YAML'
rules:
  SH001: ignore
YAML

sh_ignore_output=$(hook_output "$PROJECT_DIR/bad.sh")
if echo "$sh_ignore_output" | grep -q 'SH001'; then
    log_fail "warning-severity rules honour ignore" \
        "SH001 still reported after being set to ignore - the same bypass, in the other direction"
else
    log_pass "SH001 set to ignore is no longer reported"
fi

# =============================================================================
# Group D - capabilities a manifest declares are actually consumed
#
# A capability that is parsed and indexed but that no consumer reads is not a
# feature, it is a field. These assertions are written against the consumer.
# =============================================================================
echo ""
echo "--- D. Declared capabilities reach their consumer ---"

export CLAUDE_PLUGIN_DATA="$TMPDIR_BASE/plugin-data"
mkdir -p "$CLAUDE_PLUGIN_DATA"
FAILURE_LOG="$CLAUDE_PLUGIN_DATA/test-failures.log"

# run_failing_test <command> - feed a failed Bash run to the verification hook
run_failing_test() {
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_result":{"exit_code":1}}' "$1" \
        | bash "$ROOT_DIR/hooks/post-bash-test-verify.sh" >/dev/null 2>&1
    return 0
}

: > "$FAILURE_LOG"
run_failing_test "pytest tests/"
if grep -q 'pytest' "$FAILURE_LOG" 2>/dev/null; then
    log_pass "control: a failing known test command is recorded (ADR-0023 loop is live)"

    : > "$FAILURE_LOG"
    run_failing_test "gotestsum ./..."
    if grep -q 'gotestsum' "$FAILURE_LOG" 2>/dev/null; then
        log_pass "test_commands declared by a pack drive the verification loop"
    else
        log_fail "test_commands is consumed" \
            "a pack declares 'gotestsum' and the hook ignored it - the deterministic verification loop is blind to every language whose runner is not in its literal list"
    fi
else
    log_fail "control: the verification hook records nothing" \
        "even for pytest - the Group D assertions are undetermined"
fi

# protected_configs: relaxing a quality gate's own config must be refused, and
# which files those are is the packs' knowledge, not the hook's.
run_config_protection() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | bash "$ROOT_DIR/hooks/config-protection.sh" >/dev/null 2>&1
    echo $?
}

touch "$PROJECT_DIR/phpstan.neon" "$PROJECT_DIR/golangci.yml"
php_cfg_code=$(run_config_protection "$PROJECT_DIR/phpstan.neon")
if [[ "$php_cfg_code" == "2" ]]; then
    log_pass "control: writing phpstan.neon is refused (config protection is live)"

    go_cfg_code=$(run_config_protection "$PROJECT_DIR/golangci.yml")
    if [[ "$go_cfg_code" == "2" ]]; then
        log_pass "protected_configs declared by a pack are refused too"
    else
        log_fail "protected_configs is consumed" \
            "a pack declares golangci.yml protected and the write was allowed (exit $go_cfg_code)"
    fi
else
    log_fail "control: config protection does not refuse phpstan.neon" \
        "got exit $php_cfg_code - the assertion below is undetermined"
fi

test_summary
