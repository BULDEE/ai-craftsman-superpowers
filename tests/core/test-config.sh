#!/usr/bin/env bash
# =============================================================================
# Config Resolution Library Tests
# Tests config.sh with TDD: default values, env var overrides, .craft-config.yml
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

source "$ROOT_DIR/hooks/lib/config.sh"

# Use temp dir for isolation
TEST_DIR="/tmp/craftsman-config-tests-$$"
mkdir -p "$TEST_DIR"
ORIGINAL_PWD="$PWD"
cd "$TEST_DIR"

# Sandbox HOME so a developer's real ~/.claude/.craft-config.yml can never
# leak into these tests (config.sh reads ${HOME}/.claude/.craft-config.yml)
ORIGINAL_HOME="$HOME"
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.claude"

# Clean env before each test section
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

# Sections run as plain functions called in the original order: state is
# shared on purpose (exports and files carry between sections exactly as
# they did when the file was one linear script).

# =============================================================================
# 1. Default values (no config, no env vars)
# =============================================================================
test_default_values() {
    echo ""
    echo "=== Default Values ==="

    # Ensure no config file and no env vars
    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

    result=$(config_strictness)
    if [[ "$result" == "strict" ]]; then
        log_pass "Default strictness is 'strict'"
    else
        log_fail "Default strictness should be 'strict'" "got '$result'"
    fi

    result=$(config_stack)
    if [[ "$result" == "fullstack" ]]; then
        log_pass "Default stack is 'fullstack'"
    else
        log_fail "Default stack should be 'fullstack'" "got '$result'"
    fi
}

# =============================================================================
# 2. CLAUDE_PLUGIN_OPTION env var overrides defaults
# =============================================================================
test_env_var_overrides() {
    echo ""
    echo "=== Env Var Overrides ==="

    rm -f "$TEST_DIR/.craft-config.yml"

    export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
    export CLAUDE_PLUGIN_OPTION_stack="react"

    result=$(config_strictness)
    if [[ "$result" == "relaxed" ]]; then
        log_pass "CLAUDE_PLUGIN_OPTION_strictness=relaxed overrides default"
    else
        log_fail "Env var strictness override" "got '$result', expected 'relaxed'"
    fi

    result=$(config_stack)
    if [[ "$result" == "react" ]]; then
        log_pass "CLAUDE_PLUGIN_OPTION_stack=react overrides default"
    else
        log_fail "Env var stack override" "got '$result', expected 'react'"
    fi

    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
}

# =============================================================================
# 3. .craft-config.yml overrides env var (highest priority)
# =============================================================================
test_project_config_precedence() {
    echo ""
    echo "=== .craft-config.yml Overrides Env Var ==="

    export CLAUDE_PLUGIN_OPTION_strictness="relaxed"
    export CLAUDE_PLUGIN_OPTION_stack="react"

    cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
strictness: moderate
stack: symfony
YAML

    result=$(config_strictness)
    if [[ "$result" == "moderate" ]]; then
        log_pass ".craft-config.yml strictness overrides env var"
    else
        log_fail ".craft-config.yml should override env var strictness" "got '$result', expected 'moderate'"
    fi

    result=$(config_stack)
    if [[ "$result" == "symfony" ]]; then
        log_pass ".craft-config.yml stack overrides env var"
    else
        log_fail ".craft-config.yml should override env var stack" "got '$result', expected 'symfony'"
    fi

    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
}

# =============================================================================
# 3b. Global config fallback (~/.claude/.craft-config.yml)
# =============================================================================
test_global_config_applies() {
    echo ""
    echo "=== Global Config Fallback ==="

    GLOBAL_CONFIG="$HOME/.claude/.craft-config.yml"

    # Global-only value resolves (no PWD file, no env var)
    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

    cat > "$GLOBAL_CONFIG" <<'YAML'
strictness: moderate
stack: symfony
YAML

    result=$(config_strictness)
    if [[ "$result" == "moderate" ]]; then
        log_pass "Global config strictness applies when nothing else is set"
    else
        log_fail "Global config strictness should apply" "got '$result', expected 'moderate'"
    fi

    result=$(config_stack)
    if [[ "$result" == "symfony" ]]; then
        log_pass "Global config stack applies when nothing else is set"
    else
        log_fail "Global config stack should apply" "got '$result', expected 'symfony'"
    fi
}

# Continues on the state test_global_config_applies left behind: the global
# file is still in place, which is exactly what the precedence checks need.
test_global_config_overridden() {
    # Env var overrides global config (explicit plugin config wins)
    export CLAUDE_PLUGIN_OPTION_strictness="relaxed"

    result=$(config_strictness)
    if [[ "$result" == "relaxed" ]]; then
        log_pass "Env var overrides global config"
    else
        log_fail "Env var should override global config" "got '$result', expected 'relaxed'"
    fi

    # PWD config overrides global config
    cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
strictness: strict
YAML

    result=$(config_strictness)
    if [[ "$result" == "strict" ]]; then
        log_pass "PWD config overrides global config and env var"
    else
        log_fail "PWD config should override global config" "got '$result', expected 'strict'"
    fi
}

test_global_config_fills_missing_keys() {
    # Global fills only the keys the higher sources leave unset
    result=$(config_stack)
    if [[ "$result" == "symfony" ]]; then
        log_pass "Global config fills keys missing from PWD config"
    else
        log_fail "Global config should fill missing keys" "got '$result', expected 'symfony'"
    fi

    rm -f "$TEST_DIR/.craft-config.yml" "$GLOBAL_CONFIG"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
}

test_default_values
test_env_var_overrides
test_project_config_precedence
test_global_config_applies
test_global_config_overridden
test_global_config_fills_missing_keys

# =============================================================================
# 4. Stack helpers
# =============================================================================
test_stack_resolution() {
    echo ""
    echo "=== Stack Helpers ==="

    # The stack resolves; it no longer decides which language is checked.
    # `config_php_enabled` and `config_ts_enabled` answered "PHP checks off"
    # for stack=react while PHP files were being refused (#35), so they are
    # gone rather than kept as a helper waiting for a caller to mislead.
    export CLAUDE_PLUGIN_OPTION_stack="react"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    rm -f "$TEST_DIR/.craft-config.yml"
    if [[ "$(config_stack)" == "react" ]]; then
        log_pass "config_stack resolves the plugin option"
    else
        log_fail "config_stack resolves the plugin option" "got '$(config_stack)'"
    fi
    if ! type config_php_enabled >/dev/null 2>&1 && ! type config_ts_enabled >/dev/null 2>&1; then
        log_pass "no helper claims a language is switched off by the stack"
    else
        log_fail "no helper claims a language is switched off by the stack" \
            "config_php_enabled or config_ts_enabled still defined"
    fi
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
}

# =============================================================================
# 5. Blocking behavior (config_should_block)
# =============================================================================
test_blocking_strict() {
    echo ""
    echo "=== Blocking Behavior ==="

    rm -f "$TEST_DIR/.craft-config.yml"

    # strict: always block
    export CLAUDE_PLUGIN_OPTION_strictness="strict"
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

    if config_should_block "PHP001"; then
        log_pass "strict: blocks PHP001"
    else
        log_fail "strict should block PHP001" "returned non-blocking"
    fi

    if config_should_block "TS001"; then
        log_pass "strict: blocks TS001"
    else
        log_fail "strict should block TS001" "returned non-blocking"
    fi

    if config_should_block "LAYER001"; then
        log_pass "strict: blocks LAYER001"
    else
        log_fail "strict should block LAYER001" "returned non-blocking"
    fi
}

test_blocking_moderate() {
    # moderate: only LAYER* rules block
    export CLAUDE_PLUGIN_OPTION_strictness="moderate"

    if config_should_block "LAYER001"; then
        log_pass "moderate: blocks LAYER001"
    else
        log_fail "moderate should block LAYER001" "returned non-blocking"
    fi

    if config_should_block "LAYER_VIOLATION"; then
        log_pass "moderate: blocks LAYER_VIOLATION"
    else
        log_fail "moderate should block LAYER_VIOLATION" "returned non-blocking"
    fi

    if ! config_should_block "PHP001"; then
        log_pass "moderate: does NOT block PHP001 (warns only)"
    else
        log_fail "moderate should not block PHP001" "returned blocking"
    fi

    if ! config_should_block "TS001"; then
        log_pass "moderate: does NOT block TS001 (warns only)"
    else
        log_fail "moderate should not block TS001" "returned blocking"
    fi
}

test_blocking_relaxed() {
    # relaxed: nothing blocks
    export CLAUDE_PLUGIN_OPTION_strictness="relaxed"

    if ! config_should_block "PHP001"; then
        log_pass "relaxed: does NOT block PHP001"
    else
        log_fail "relaxed should not block PHP001" "returned blocking"
    fi

    if ! config_should_block "LAYER001"; then
        log_pass "relaxed: does NOT block LAYER001"
    else
        log_fail "relaxed should not block LAYER001" "returned blocking"
    fi

    if ! config_should_block "TS001"; then
        log_pass "relaxed: does NOT block TS001"
    else
        log_fail "relaxed should not block TS001" "returned blocking"
    fi
}

test_blocking_warn_rules() {
    # WARN rules never block, even in strict
    cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
strictness: strict
YAML

    if ! config_should_block "WARN-PHP001"; then
        log_pass "strict: WARN-PHP001 does NOT block (warnings never block)"
    else
        log_fail "strict: WARN-PHP001 should NOT block" ""
    fi

    if ! config_should_block "PHP005"; then
        log_pass "strict: PHP005 does NOT block (warnings never block)"
    else
        log_fail "strict: PHP005 should NOT block" ""
    fi

    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
}

test_stack_resolution
test_blocking_strict
test_blocking_moderate
test_blocking_relaxed
test_blocking_warn_rules

# =============================================================================
# 6. Stop review enabled (config_stop_review_enabled)
# =============================================================================
test_stop_review_strict() {
    echo ""
    echo "=== Stop Review Enabled ==="

    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true

    # strict: stop review enabled
    export CLAUDE_PLUGIN_OPTION_strictness="strict"

    if config_stop_review_enabled; then
        log_pass "strict: stop review enabled"
    else
        log_fail "strict: stop review should be enabled" "returned false"
    fi
}

test_stop_review_moderate_relaxed() {
    # moderate: stop review disabled
    export CLAUDE_PLUGIN_OPTION_strictness="moderate"

    if ! config_stop_review_enabled; then
        log_pass "moderate: stop review disabled"
    else
        log_fail "moderate: stop review should be disabled" "returned true"
    fi

    # relaxed: stop review disabled
    export CLAUDE_PLUGIN_OPTION_strictness="relaxed"

    if ! config_stop_review_enabled; then
        log_pass "relaxed: stop review disabled"
    else
        log_fail "relaxed: stop review should be disabled" "returned true"
    fi
}

test_stop_review_default() {
    # default (no env var): strict enabled
    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true

    if config_stop_review_enabled; then
        log_pass "default (strict): stop review enabled"
    else
        log_fail "default should enable stop review" "returned false"
    fi

    unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
}

# =============================================================================
# 7. Sentry config (config_sentry_org, config_sentry_project, config_sentry_enabled)
# =============================================================================
test_sentry_defaults() {
    echo ""
    echo "=== Sentry Config ==="

    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true

    # Default: empty (opt-in)
    result=$(config_sentry_org)
    if [[ -z "$result" ]]; then
        log_pass "Default sentry_org is empty"
    else
        log_fail "Default sentry_org should be empty" "got '$result'"
    fi

    result=$(config_sentry_project)
    if [[ -z "$result" ]]; then
        log_pass "Default sentry_project is empty"
    else
        log_fail "Default sentry_project should be empty" "got '$result'"
    fi
}

test_sentry_gating() {
    # Not enabled when both empty
    if ! config_sentry_enabled; then
        log_pass "config_sentry_enabled returns false when both empty"
    else
        log_fail "config_sentry_enabled should be false" "returned true"
    fi

    # Not enabled when only org set
    export CLAUDE_PLUGIN_OPTION_sentry_org="my-org"
    if ! config_sentry_enabled; then
        log_pass "config_sentry_enabled returns false when only org set"
    else
        log_fail "config_sentry_enabled should be false (no project)" "returned true"
    fi

    # Not enabled when only project set
    unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
    export CLAUDE_PLUGIN_OPTION_sentry_project="my-project"
    if ! config_sentry_enabled; then
        log_pass "config_sentry_enabled returns false when only project set"
    else
        log_fail "config_sentry_enabled should be false (no org)" "returned true"
    fi
}

test_sentry_env_values() {
    # Enabled when both set via env vars
    export CLAUDE_PLUGIN_OPTION_sentry_org="my-org"
    export CLAUDE_PLUGIN_OPTION_sentry_project="my-project"
    if config_sentry_enabled; then
        log_pass "config_sentry_enabled returns true when both set"
    else
        log_fail "config_sentry_enabled should be true" "returned false"
    fi

    result=$(config_sentry_org)
    if [[ "$result" == "my-org" ]]; then
        log_pass "config_sentry_org reads env var"
    else
        log_fail "config_sentry_org env var" "got '$result'"
    fi

    result=$(config_sentry_project)
    if [[ "$result" == "my-project" ]]; then
        log_pass "config_sentry_project reads env var"
    else
        log_fail "config_sentry_project env var" "got '$result'"
    fi
}

test_sentry_yml_override() {
    # .craft-config.yml overrides env var
    cat > "$TEST_DIR/.craft-config.yml" <<'YAML'
sentry_org: yml-org
sentry_project: yml-project
YAML

    result=$(config_sentry_org)
    if [[ "$result" == "yml-org" ]]; then
        log_pass "config_sentry_org reads .craft-config.yml"
    else
        log_fail "config_sentry_org yml override" "got '$result'"
    fi

    result=$(config_sentry_project)
    if [[ "$result" == "yml-project" ]]; then
        log_pass "config_sentry_project reads .craft-config.yml"
    else
        log_fail "config_sentry_project yml override" "got '$result'"
    fi

    rm -f "$TEST_DIR/.craft-config.yml"
    unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
    unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true
}

test_stop_review_strict
test_stop_review_moderate_relaxed
test_stop_review_default
test_sentry_defaults
test_sentry_gating
test_sentry_env_values
test_sentry_yml_override

# =============================================================================
# Cleanup
# =============================================================================
cd "$ORIGINAL_PWD"
export HOME="$ORIGINAL_HOME"
unset CLAUDE_PLUGIN_OPTION_strictness 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_stack 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_org 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_sentry_project 2>/dev/null || true
# --- The one key that consents to running a cloned repository's code ---------
#
# `trust_project_tools` lets Level 2 run vendor/bin/phpstan and an eslint flat
# config, which is executable JavaScript by design. The parser was rewritten
# in-shell for speed, and three shapes had to be DECIDED rather than inherited
# from whatever a pipeline happened to do. Each is asserted, because a silent
# change here is a change to who may execute code on this machine.
CONSENT_HOME=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-consent.XXXXXX")
mkdir -p "$CONSENT_HOME/.claude"

_consent_says() {
    printf '%s' "$1" > "$CONSENT_HOME/.claude/.craft-config.yml"
    if HOME="$CONSENT_HOME" bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_trust_project_tools"; then
        printf 'trusted'
    else
        printf 'inert'
    fi
}

for case_line in \
    'trust_project_tools: true|trusted|the canonical form' \
    'trust_project_tools: false|inert|an explicit false' \
    'trust_project_tools:true|inert|no space after the colon is not a YAML mapping' \
    'trust_project_tools: true # I trust this machine|trusted|a comment is not part of the value' \
    'trust_project_tools: "true"|trusted|a quoted value' \
    'other_key: true|inert|another key entirely'
do
    IFS='|' read -r line expected why <<< "$case_line"
    got=$(_consent_says "$line
")
    if [[ "$got" == "$expected" ]]; then
        log_pass "consent: $why ($expected)"
    else
        log_fail "consent: $why" "expected $expected, got $got"
    fi
done

# CRLF is the one shape that deliberately CHANGED. A CRLF file is valid YAML
# and the machine owner wrote it; the pipeline this replaced ignored the whole
# line, which is a user's own declaration silently dropped.
printf 'trust_project_tools: true\r\n' > "$CONSENT_HOME/.claude/.craft-config.yml"
if HOME="$CONSENT_HOME" bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_trust_project_tools"; then
    log_pass "consent: a CRLF file is honoured, and this is a deliberate change"
else
    log_fail "consent: a CRLF file is honoured" "still ignored"
fi

# The same question for the external pack list, where the value is a path this
# plugin then loads code from.
EXTERNAL_PACK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-extpack.XXXXXX")
printf 'packs:\r\n  external:\r\n    - path: %s\r\n' "$EXTERNAL_PACK" \
    > "$CONSENT_HOME/.claude/.craft-config.yml"
crlf_path=$(HOME="$CONSENT_HOME" bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_external_packs")
if [[ "$crlf_path" == "$EXTERNAL_PACK" ]]; then
    log_pass "an external pack path survives CRLF without a stray carriage return"
else
    log_fail "an external pack path survives CRLF" "got '$crlf_path'"
fi

printf 'packs:\n  external:\n    - path: %s # my pack\n' "$EXTERNAL_PACK" \
    > "$CONSENT_HOME/.claude/.craft-config.yml"
commented_path=$(HOME="$CONSENT_HOME" bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; config_external_packs")
if [[ "$commented_path" == "$EXTERNAL_PACK" ]]; then
    log_pass "and a trailing comment is not part of the path"
else
    log_fail "and a trailing comment is not part of the path" "got '$commented_path'"
fi

rm -rf "$CONSENT_HOME" "$EXTERNAL_PACK"

rm -rf "$TEST_DIR"

test_summary
