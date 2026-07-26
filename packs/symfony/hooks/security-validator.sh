#!/usr/bin/env bash
# =============================================================================
# PHP Security Validator - Symfony Pack
# Provides pack_validate_php_security() for the pack-loader pipeline.
#
# Rules:
#   SEC001 - hardcoded secret (api key, token, password, private key) in source
#   SEC002 - data executed as code (eval, assert on a variable, shell exec)
#   SEC003 - SQL assembled by concatenation or interpolation instead of binding
# Requires: add_violation(), line_has_ignore()
#   These are provided by the orchestrator (post-write-check.sh, craftsman-ci.sh).
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

# Values that document a credential instead of being one
_SECURITY_PHP_FAKE='(YOUR[_-]?|CHANGE[_-]?ME|EXAMPLE|PLACEHOLDER|DUMMY|SAMPLE|REDACTED|X{6,}|\.\.\.)'

# Credentials resolved at runtime (environment, container parameters, vault)
_SECURITY_PHP_RUNTIME='(getenv|\$_ENV|\$_SERVER|%env\(|->get\(|getParameter\(|resolve\()'

# Secret-shaped assignments plus known provider key prefixes
_SECURITY_PHP_SECRET='(api_?key|secret|password|passwd|token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_/+.=-]{12,}["'"'"']|(sk_live|ghp_|gho_|github_pat_|xox[bapr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}|BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'

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
    hit=$(_security_php_code_lines "$1" \
        | grep -Ei "$_SECURITY_PHP_SECRET" \
        | grep -viE "$_SECURITY_PHP_FAKE|$_SECURITY_PHP_RUNTIME" | head -1)
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
