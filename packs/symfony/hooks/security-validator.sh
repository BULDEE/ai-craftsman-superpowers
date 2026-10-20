#!/usr/bin/env bash
# =============================================================================
# PHP Security Validator - Symfony Pack
# Provides pack_validate_php_security() for the pack-loader pipeline.
#
# Rules:
#   SEC001 - hardcoded secret (api key, token, password, private key) in source
#   SEC002 - data executed as code (eval, assert on a variable, shell exec)
#   SEC003 - SQL assembled by concatenation or interpolation instead of binding
# Requires: add_violation(), line_has_ignore(), secret_hits()
#   The orchestrator provides the first two (post-write-check.sh,
#   craftsman-ci.sh); secret_hits and the credential shapes come from
#   hooks/lib/secret-patterns.sh, sourced by pack-loader.sh.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
#
# Design bias: silence over noise. A security gate that cries wolf gets muted,
# so every pattern below is paired with a safe counter-example in
# tests/packs/test-security.sh (env reads, bound parameters, UI copy, docs).
# =============================================================================

# SQL statement shape, never a bare keyword ("Delete from cart" is plain copy)
_SECURITY_PHP_SQL='(SELECT[[:space:]]+[^;]+[[:space:]]+FROM[[:space:]]|INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[^;]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]])'

# A database sink on the same line: a SQL string on its own injects nothing
_SECURITY_PHP_SINK='(query|exec|execute|prepare|fetch|statement)[A-Za-z]*[[:space:]]*\('

# Credentials resolved at runtime (environment, container parameters, vault)
_SECURITY_PHP_RUNTIME='(getenv|\$_ENV|\$_SERVER|%env\(|->get\(|getParameter\(|resolve\()'

# Numbered source lines minus comment-only lines: prose about eval is not eval
_security_php_code_lines() {
    grep -n '' "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|#|\*|/\*)'
}

_security_php_report() {
    local rule="$1" hit="$2" message="$3"
    [[ -z "$hit" ]] && return 0
    line_has_ignore "${hit#*:}" "$rule" && return 0
    add_violation "$rule" "$message (line ${hit%%:*})"
}

_security_php_check_secrets() {
    local hit
    hit=$(_security_php_code_lines "$1" | secret_hits "$_SECURITY_PHP_RUNTIME" | head -1)
    _security_php_report "SEC001" "$hit" \
        "Hardcoded secret - read it from the environment or a secrets vault, then rotate the leaked value"
}

_security_php_check_eval() {
    local direct="(^|[^->:\$[:alnum:]_\"'\`])"
    local hit
    hit=$(_security_php_code_lines "$1" | grep -Ei \
        "${direct}(eval|create_function)[[:space:]]*\(|${direct}assert[[:space:]]*\([[:space:]]*\\\$|call_user_func(_array)?[[:space:]]*\([[:space:]]*\\\$_(GET|POST|REQUEST|COOKIE)|${direct}(system|shell_exec|passthru|proc_open|popen|pcntl_exec|exec)[[:space:]]*\([^)]*\\\$" \
        | head -1)
    _security_php_report "SEC002" "$hit" \
        "Data executed as code - never eval or shell out with values you did not author"
}

_security_php_check_sql_injection() {
    local file="$1"
    local hit
    hit=$(_security_php_code_lines "$file" | grep -Ei \
        "${_SECURITY_PHP_SINK}.*${_SECURITY_PHP_SQL}.*[\"'][[:space:]]*\.[[:space:]]*\\\$" | head -1)
    [[ -z "$hit" ]] && hit=$(_security_php_code_lines "$file" | grep -Ei \
        "${_SECURITY_PHP_SINK}.*\"[^\"]*${_SECURITY_PHP_SQL}[^\"]*\\\$[A-Za-z_{]" | head -1)
    _security_php_report "SEC003" "$hit" \
        "SQL built by concatenation or interpolation - bind the values as parameters"
}

pack_validate_php_security() {
    local file="$1"
    _security_php_check_secrets "$file"
    _security_php_check_eval "$file"
    _security_php_check_sql_injection "$file"
}
