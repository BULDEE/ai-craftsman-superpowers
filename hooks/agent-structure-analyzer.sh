#!/usr/bin/env bash
# =============================================================================
# Project Structure Analyzer — command wrapper for agent hook
# Checks agent_hooks gate BEFORE emitting any context.
# When enabled, injects architectural context and correction trends.
# =============================================================================
set -uo pipefail

# Gate: skip entirely if agent hooks are disabled
if [[ "${CLAUDE_PLUGIN_OPTION_agent_hooks:-true}" == "false" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
DB="${PLUGIN_DATA}/metrics.db"

# Collect correction trends if DB exists
CORRECTIONS=""
if [[ -f "$DB" ]]; then
    CORRECTIONS=$(sqlite3 "$DB" "SELECT rule, action, COUNT(*) as count FROM corrections WHERE timestamp > datetime('now','-30 days') GROUP BY rule, action ORDER BY count DESC LIMIT 10;" 2>/dev/null) || true
fi

# Collect channel status if available
CHANNELS=""
if [[ -f "${SCRIPT_DIR}/lib/channels.sh" ]]; then
    CHANNELS=$(source "${SCRIPT_DIR}/lib/channels.sh" && channel_status_summary 2>/dev/null) || true
fi

# Build context message
MSG="PROJECT ANALYSIS REQUEST: Scan src/ directories to build an architectural context map. Report: bounded contexts (namespaces/directories with file counts), available Value Objects (max 10), aggregate roots (max 10), layer structure. Max 500 chars. Skip sections with no findings. If no src/ directory exists, skip."

if [[ -n "$CORRECTIONS" ]]; then
    MSG="${MSG}\n\nCORRECTION TRENDS (30d):\n${CORRECTIONS}"
fi

if [[ -n "$CHANNELS" ]]; then
    MSG="${MSG}\n\nACTIVE CHANNELS: ${CHANNELS}"
fi

jq -n --arg msg "$MSG" '{ systemMessage: $msg }'
exit 0
