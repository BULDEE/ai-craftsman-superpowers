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
source "${SCRIPT_DIR}/lib/healthcheck.sh"
source "${SCRIPT_DIR}/lib/routing-table.sh"
source "${SCRIPT_DIR}/lib/hook-events.sh"

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

# Python3 availability check - skip python-dependent features if missing
HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

# Init metrics DB (idempotent, non-blocking)
if $HAS_PYTHON3; then
    metrics_init 2>/dev/null || echo "WARNING: Metrics DB init failed" >&2
fi

# Write the canonical session-state path to a stable bridge file so that
# skills running via the Bash tool (where CLAUDE_PLUGIN_DATA is unavailable)
# can find the same state file that hooks use.
# The bridge file is intentionally placed outside the plugin data directory
# so it is independent of the plugin slug and survives renames.
SESSION_STATE_PATH="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-state.json"
printf '%s' "$SESSION_STATE_PATH" > "${HOME}/.claude/craftsman-session-state-path" 2>/dev/null || true

# Record session start epoch. SessionEnd input has no duration field
# (only session_id/transcript_path/cwd/reason), so session-metrics.sh
# derives duration and its violation-count window from this marker.
printf '%s' "$(date +%s)" > "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/session-start-ts" 2>/dev/null || true

# Generate a self-contained verify wrapper at a well-known path.
# Skills run via the Bash tool without CLAUDE_PLUGIN_ROOT, so they cannot
# locate session_state.py directly. This wrapper bakes in the resolved path
# at session start, making the verify skill a one-liner call.
cat > "${HOME}/.claude/craftsman-set-verified.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
exec python3 "${SCRIPT_DIR}/lib/session_state.py" set-verified
WRAPPER
chmod +x "${HOME}/.claude/craftsman-set-verified.sh" 2>/dev/null || true

# Same bridge pattern for the instinct pipeline (ADR-0020): /craftsman:metrics
# runs via the Bash tool without CLAUDE_PLUGIN_ROOT, so bake resolved paths in.
cat > "${HOME}/.claude/craftsman-instincts.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
DB="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db"
PROJECT_HASH=\$(echo -n "\$PWD" | shasum -a 256 | cut -d' ' -f1)
CMD="\${1:-candidates}"
shift 2>/dev/null || true
case "\$CMD" in
    approve|reject)
        exec python3 "${SCRIPT_DIR}/lib/instincts.py" "\$CMD" "\$DB" "\$@"
        ;;
    *)
        exec python3 "${SCRIPT_DIR}/lib/instincts.py" "\$CMD" "\$DB" "\$PROJECT_HASH" "\$@"
        ;;
esac
WRAPPER
chmod +x "${HOME}/.claude/craftsman-instincts.sh" 2>/dev/null || true

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
PACK_STATUS=$(_init_packs 2>/dev/null || echo "PACKS:error")
MSG="Craftsman active | Stack: ${STACK} | Strictness: ${STRICTNESS} | PHP rules: ${PHP_STATUS} | TS rules: ${TS_STATUS} | Metrics: initialized | ${PACK_STATUS}"

# Correction learning: trends kept separate so the context budget can drop
# them first (ADR-0021 priority order)
CORRECTION_TRENDS=""
if $HAS_PYTHON3; then
    CORRECTION_TRENDS=$(metrics_correction_trends 2>/dev/null || true)
fi

# Instinct pipeline (ADR-0020): surface pending candidates without injecting
# their content; review happens in /craftsman:metrics.
PENDING_INSTINCTS=""
if $HAS_PYTHON3; then
    _pending=$(python3 "${SCRIPT_DIR}/lib/instincts.py" pending-count \
        "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db" \
        "$(metrics_project_hash)" 2>/dev/null || echo 0)
    if [[ "$_pending" =~ ^[0-9]+$ ]] && [[ "$_pending" -gt 0 ]]; then
        PENDING_INSTINCTS="Instincts: ${_pending} candidate(s) pending review - run /craftsman:metrics"
    fi
fi

# Config mismatch warning
WARNINGS=""

# Validate hooks.json schema - catch unsupported events early
HOOKS_FILE="${SCRIPT_DIR}/hooks.json"
if [[ -f "$HOOKS_FILE" ]]; then
    SUPPORTED_EVENTS=$(hook_events_python_set)
    _unsupported=$(python3 -c "
import json, sys
supported = ${SUPPORTED_EVENTS}
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

# Auto-setup gate - check both global and project config
if [[ ! -f "${HOME}/.claude/.craft-config.yml" ]] && [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | First time? Run /craftsman:setup to configure your profile and project. The plugin works with defaults, but setup unlocks full customization."
elif [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | No project .craft-config.yml found. Run /craftsman:setup to configure this project."
fi

# Healthcheck summary
HC_SUMMARY=$(hc_summary 2>/dev/null || echo "Healthcheck: unavailable")
MSG="${MSG} | ${HC_SUMMARY}"

# Command routing table
ROUTING=$(routing_table 2>/dev/null || echo "")

# =============================================================================
# Context budget assembly (ADR-0021). Priority when over budget:
# core status + warnings > pending instincts > routing table > trends.
# Trends are dropped first, then the routing table is truncated.
# =============================================================================
BUDGET=$(config_session_start_max_chars)

assemble_msg() {
    local include_trends="$1" routing_text="$2"
    local out="${MSG}"
    [[ "$include_trends" == "yes" && -n "$CORRECTION_TRENDS" ]] && out="${out} | Learning: ${CORRECTION_TRENDS}"
    [[ -n "$PENDING_INSTINCTS" ]] && out="${out} | ${PENDING_INSTINCTS}"
    out="${out}${WARNINGS}"
    [[ -n "$routing_text" ]] && out="${out}

${routing_text}"
    printf '%s' "$out"
}

FULL=$(assemble_msg "yes" "$ROUTING")
if [[ "${#FULL}" -gt "$BUDGET" ]]; then
    FULL=$(assemble_msg "no" "$ROUTING")
fi
if [[ "${#FULL}" -gt "$BUDGET" ]]; then
    _head_len=$(( ${#FULL} - ${#ROUTING} ))
    _room=$(( BUDGET - _head_len ))
    [[ "$_room" -lt 0 ]] && _room=0
    FULL=$(assemble_msg "no" "$(printf '%s' "$ROUTING" | head -c "$_room")")
fi

jq -n --arg msg "$FULL" '{
    systemMessage: $msg
}'

exit 0
