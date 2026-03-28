#!/usr/bin/env bash
# =============================================================================
# Channel Lifecycle Helpers
# Checks if external channels (Sentry, CI, etc.) are configured and available.
#
# Usage:
#   source "${SCRIPT_DIR}/lib/channels.sh"
#   channel_available "sentry" && echo "Sentry channel ready"
#   channel_status_summary  # → "sentry:enabled "
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/config.sh" 2>/dev/null || true

channel_available() {
    local channel="$1"
    case "$channel" in
        sentry)
            config_sentry_enabled
            ;;
        *)
            return 1
            ;;
    esac
}

channel_status_summary() {
    local summary=""
    if channel_available "sentry"; then
        summary="${summary}sentry:enabled "
    fi
    echo "$summary"
}
