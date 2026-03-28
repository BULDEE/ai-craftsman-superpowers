#!/usr/bin/env bash
# =============================================================================
# Session Metrics Hook for Claude Code
# Logs session summary on SessionEnd.
#
# TRIGGERS: SessionEnd
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

metrics_init 2>/dev/null || true

# Read session info from stdin
INPUT=$(cat)
SESSION_DURATION=$(echo "$INPUT" | jq -r '.session_duration_seconds // 0' 2>/dev/null)

# Count violations from this session (approximate using duration)
PROJECT_HASH=$(metrics_project_hash)
BLOCKED=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM violations WHERE project_hash='$PROJECT_HASH' AND blocked=1 AND timestamp > datetime('now', '-${SESSION_DURATION:-3600} seconds');" 2>/dev/null || echo 0)
WARNED=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM violations WHERE project_hash='$PROJECT_HASH' AND blocked=0 AND ignored=0 AND timestamp > datetime('now', '-${SESSION_DURATION:-3600} seconds');" 2>/dev/null || echo 0)

# Record session
metrics_record_session "${SESSION_DURATION:-0}" '[]' '[]' "$BLOCKED" "$WARNED" 2>/dev/null || true

# Output summary as systemMessage (non-blocking)
if [[ "$BLOCKED" -gt 0 || "$WARNED" -gt 0 ]]; then
    jq -n --arg b "$BLOCKED" --arg w "$WARNED" '{
        systemMessage: ("Session summary: " + $b + " violations blocked, " + $w + " warnings. Run /craftsman:metrics for details.")
    }'
fi

exit 0
