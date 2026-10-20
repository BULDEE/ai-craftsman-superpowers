#!/usr/bin/env bash
# =============================================================================
# Python Security Validator - Python Pack
# Provides pack_validate_python_security() for the pack-loader pipeline.
#
# Rules:
#   SEC001 - hardcoded secret (api key, token, password, private key) in source
# Requires: add_violation(), line_has_ignore(), secret_hits()
#   The orchestrator provides the first two (post-write-check.sh,
#   craftsman-ci.sh); secret_hits and the credential shapes come from
#   hooks/lib/secret-patterns.sh, sourced by pack-loader.sh.
#
# NOTE: This file is source'd by pack-loader, NOT executed directly.
#   Do NOT add set -euo pipefail - it would affect the sourcing script.
#
# Python is where most model provider keys are used, and it had no SEC001 at
# all: `client = Anthropic(api_key="sk-ant-...")` was written clean (CR-257).
# =============================================================================

# Credentials resolved at runtime (environment, keyring, secrets managers)
_SECURITY_PY_RUNTIME='(os\.environ|getenv[[:space:]]*\(|environ\.get|environ\[|keyring\.|get_secret)'

_security_py_check_secrets() {
    local hit
    hit=$(grep -n '' "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' \
        | secret_hits "$_SECURITY_PY_RUNTIME" | head -1)
    [[ -z "$hit" ]] && return 0
    line_has_ignore "${hit#*:}" "SEC001" && return 0
    add_violation "SEC001" "Hardcoded secret - read it from the environment or a secrets manager, then rotate the leaked value (line ${hit%%:*})"
}

pack_validate_python_security() {
    _security_py_check_secrets "$1"
}
