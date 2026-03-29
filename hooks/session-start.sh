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
source "${SCRIPT_DIR}/lib/pack-loader.sh"

# Check required dependencies
_check_dependencies() {
    local missing=""
    command -v python3 >/dev/null 2>&1 || missing="${missing} python3"
    command -v jq >/dev/null 2>&1 || missing="${missing} jq"
    command -v sqlite3 >/dev/null 2>&1 || missing="${missing} sqlite3"

    if [[ -n "$missing" ]]; then
        echo "Dependencies: MISSING${missing}. Install: brew install${missing} (macOS) or apt-get install${missing} (Linux)"
    fi
}

_init_packs() {
    pack_loader_init
    pack_sync_symlinks

    local loaded
    loaded=$(pack_loaded)
    if [[ -n "$loaded" ]]; then
        local pack_list
        pack_list=$(echo "$loaded" | tr '\n' ', ' | sed 's/,$//')
        echo "PACKS:${pack_list}"
    else
        echo "PACKS:none"
    fi
}

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
DEP_STATUS=$(_check_dependencies)
PACK_STATUS=$(_init_packs 2>/dev/null || echo "PACKS:error")
MSG="Craftsman active | Stack: ${STACK} | Strictness: ${STRICTNESS} | PHP rules: ${PHP_STATUS} | TS rules: ${TS_STATUS} | Metrics: initialized | ${PACK_STATUS}"
if [[ -n "$DEP_STATUS" ]]; then
    MSG="${MSG} | ${DEP_STATUS}"
fi

# Config mismatch warning
WARNINGS=""

# Validate hooks.json schema — catch unsupported events early
HOOKS_FILE="${SCRIPT_DIR}/hooks.json"
if [[ -f "$HOOKS_FILE" ]]; then
    _unsupported=$(python3 -c "
import json, sys
supported = {'SessionStart','PreToolUse','PostToolUse','UserPromptSubmit','FileChanged','InstructionsLoaded','Stop','SessionEnd'}
try:
    data = json.load(open(sys.argv[1]))
    actual = set(data.get('hooks', {}).keys())
    bad = actual - supported
    if bad:
        print(','.join(sorted(bad)))
except Exception:
    pass
" "$HOOKS_FILE" 2>/dev/null)
    if [[ -n "$_unsupported" ]]; then
        WARNINGS="${WARNINGS} | SCHEMA WARNING: hooks.json contains unsupported events: ${_unsupported}. Remove them to avoid CI failures."
    fi
fi

if [[ "$DETECTED" != "other" && "$DETECTED" != "$STACK" ]]; then
    WARNINGS="${WARNINGS} | Warning: detected '${DETECTED}' but config says '${STACK}'. Run /craftsman:setup to update."
fi

# Auto-setup gate — check both global and project config
if [[ ! -f "${HOME}/.claude/.craft-config.yml" ]] && [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | First time? Run /craftsman:setup to configure your profile and project. The plugin works with defaults, but setup unlocks full customization."
elif [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | No project .craft-config.yml found. Run /craftsman:setup to configure this project."
fi

jq -n --arg msg "${MSG}${WARNINGS}" '{
    systemMessage: $msg
}'

exit 0
