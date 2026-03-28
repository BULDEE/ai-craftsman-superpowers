#!/usr/bin/env bash
# =============================================================================
# Session Start Hook for Claude Code
# Loads project context and outputs active profile as systemMessage.
#
# TRIGGERS: SessionStart
# EXIT CODES: 0 always (non-blocking, informational)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

# Consume stdin (may be empty or JSON)
cat > /dev/null 2>&1 || true

# Init metrics DB (idempotent)
metrics_init 2>/dev/null || true

# Detect project type from filesystem
detect_project_type() {
    local has_php=false has_ts=false
    [[ -f "${PWD}/composer.json" ]] && has_php=true
    [[ -f "${PWD}/package.json" ]] && has_ts=true
    if $has_php && $has_ts; then echo "fullstack"
    elif $has_php; then echo "symfony"
    elif $has_ts; then echo "react"
    else echo "other"
    fi
}

DETECTED=$(detect_project_type)
STRICTNESS=$(config_strictness)
STACK=$(config_stack)
PHP_STATUS="OFF"
TS_STATUS="OFF"
config_php_enabled && PHP_STATUS="ON"
config_ts_enabled && TS_STATUS="ON"

# Build message
MSG="Craftsman active | Stack: ${STACK} | Strictness: ${STRICTNESS} | PHP rules: ${PHP_STATUS} | TS rules: ${TS_STATUS} | Metrics: initialized"

# Config mismatch warning
WARNINGS=""
if [[ "$DETECTED" != "other" && "$DETECTED" != "$STACK" ]]; then
    WARNINGS="${WARNINGS} | Warning: detected '${DETECTED}' but config says '${STACK}'. Run /craftsman:setup to update."
fi

# First session detection
if [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | No .craft-config.yml found. Run /craftsman:setup to configure this project."
fi

jq -n --arg msg "${MSG}${WARNINGS}" '{
    systemMessage: $msg
}'

exit 0
