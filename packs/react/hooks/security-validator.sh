#!/usr/bin/env bash
# =============================================================================
# TypeScript Security Validator - React Pack
# Provides pack_validate_typescript_security() for the pack-loader pipeline.
#
# Rules:
#   SEC001 - hardcoded secret (api key, token, password) shipped in the bundle
#   SEC002 - data executed as code (eval, new Function)
#   SEC003 - SQL assembled by template literal or concatenation instead of binding
# Requires: add_violation(), line_has_ignore()
#   These are provided by the orchestrator (post-write-check.sh, craftsman-ci.sh).
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
#
# Design bias: silence over noise. UI copy says "Delete", "Update" and "token"
# all day long, so each rule needs a real code shape, not a keyword. Safe
# counter-examples live in tests/packs/test-security.sh.
# =============================================================================

# SQL statement shape, never a bare keyword (`Delete ${name}?` is a label)
_SECURITY_TS_SQL='(SELECT[[:space:]]+[^;]+[[:space:]]+FROM[[:space:]]|INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[^;]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]])'

# A database sink on the same line: a SQL string on its own injects nothing
_SECURITY_TS_SINK='(query|execute|exec|prepare|raw|unsafe)[A-Za-z]*[[:space:]]*\('

# Values that document a credential instead of being one
_SECURITY_TS_FAKE='(YOUR[_-]?|CHANGE[_-]?ME|EXAMPLE|PLACEHOLDER|DUMMY|SAMPLE|REDACTED|X{6,}|\.\.\.)'

# Credentials resolved at runtime (build env, edge runtime, server config)
_SECURITY_TS_RUNTIME='(process\.env|import\.meta\.env|Deno\.env|useRuntimeConfig|getServerSideProps)'

# Secret-shaped assignments plus known provider key prefixes
_SECURITY_TS_SECRET='(api_?key|secret|password|passwd|token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'`][A-Za-z0-9_/+.=-]{12,}["'"'"'`]|(sk_live|ghp_|gho_|github_pat_|xox[bapr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}|BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'

# Numbered source lines minus comment-only lines: a warning about eval is not eval
_security_ts_code_lines() {
    grep -n '' "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|#|\*|/\*)'
}

_security_ts_report() {
    local rule="$1" hit="$2" message="$3"
    [[ -z "$hit" ]] && return 0
    line_has_ignore "${hit#*:}" "$rule" && return 0
    add_violation "$rule" "$message (line ${hit%%:*})"
}

_security_ts_check_secrets() {
    local hit
    hit=$(_security_ts_code_lines "$1" \
        | grep -Ei "$_SECURITY_TS_SECRET" \
        | grep -viE "$_SECURITY_TS_FAKE|$_SECURITY_TS_RUNTIME" | head -1)
    _security_ts_report "SEC001" "$hit" \
        "Hardcoded secret - anything in the bundle is public; read it from the environment on the server and rotate the leaked value"
}

_security_ts_check_eval() {
    local direct="(^|[^->.\$[:alnum:]_\"'\`])"
    local hit
    hit=$(_security_ts_code_lines "$1" | grep -E \
        "${direct}eval[[:space:]]*\(|new[[:space:]]+Function[[:space:]]*\(|${direct}Function[[:space:]]*\([^)]*\)[[:space:]]*\(" \
        | head -1)
    _security_ts_report "SEC002" "$hit" \
        "Data executed as code - never eval or build a Function from values you did not author"
}

_security_ts_check_sql_injection() {
    local file="$1"
    local hit
    hit=$(_security_ts_code_lines "$file" | grep -Ei \
        "${_SECURITY_TS_SINK}[[:space:]]*\`[^\`]*${_SECURITY_TS_SQL}[^\`]*\\\$\{" | head -1)
    [[ -z "$hit" ]] && hit=$(_security_ts_code_lines "$file" | grep -Ei \
        "${_SECURITY_TS_SINK}.*${_SECURITY_TS_SQL}.*[\"'\`][[:space:]]*\+[[:space:]]*[A-Za-z_\$]" | head -1)
    _security_ts_report "SEC003" "$hit" \
        "SQL built by interpolation or concatenation - use a parameterized query"
}

pack_validate_typescript_security() {
    local file="$1"
    _security_ts_check_secrets "$file"
    _security_ts_check_eval "$file"
    _security_ts_check_sql_injection "$file"
}
