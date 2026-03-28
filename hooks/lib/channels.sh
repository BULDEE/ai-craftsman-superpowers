#!/usr/bin/env bash
# =============================================================================
# Channel Lifecycle — Registry, circuit breaker, cache orchestration
# Checks if external channels (Sentry, CI, etc.) are configured and available.
# Integrates circuit breaker protection and response caching.
#
# Usage:
#   source "${SCRIPT_DIR}/lib/channels.sh"
#   channel_available "sentry" && echo "Sentry channel ready"
#   channel_call "sentry" "issues:open"
#   channel_health "sentry"          # → closed|open|half-open
#   channel_reset "sentry"           # → force close circuit
#   channel_status_summary           # → "sentry:closed " or "sentry:enabled "
# =============================================================================

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_LIB_DIR}/config.sh" 2>/dev/null || true
source "${SCRIPT_LIB_DIR}/circuit-breaker.sh" 2>/dev/null || true
source "${SCRIPT_LIB_DIR}/channel-cache.sh" 2>/dev/null || true

# Circuit breaker feature detection
_CB_AVAILABLE=false
if type cb_init &>/dev/null; then
    _CB_AVAILABLE=true
fi

_CACHE_AVAILABLE=false
if type cache_get &>/dev/null; then
    _CACHE_AVAILABLE=true
fi

# Module-level config vars (set by _channels_load_config)
_CHANNEL_THRESHOLD=3
_CHANNEL_COOLDOWN=300
_CHANNEL_CACHE_TTL=3600
_CHANNEL_CACHE_MAX=200

# Track call source for callers
CHANNEL_CALL_SOURCE=""

# =============================================================================
# _channels_parse_nested_yml "$section" "$key" "$file"
# Parse nested YAML values like: channels.sentry.circuit_threshold
# Supports indent-based nesting (2-space indent).
# =============================================================================
_channels_parse_nested_yml() {
    local section="$1" key="$2" file="$3"
    [[ -f "$file" ]] || return 1

    local in_channels=false in_section=false
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Detect "channels:" (top-level)
        if [[ "$line" =~ ^channels: ]]; then
            in_channels=true
            continue
        fi

        if $in_channels; then
            # If we hit another top-level key, stop
            if [[ "$line" =~ ^[a-z] ]]; then
                in_channels=false
                continue
            fi

            # Detect section (e.g., "  sentry:")
            if [[ "$line" =~ ^[[:space:]]{2}${section}: ]]; then
                in_section=true
                continue
            fi

            # If in section, look for key
            if $in_section; then
                # If we hit another section at same indent level, stop
                if [[ "$line" =~ ^[[:space:]]{2}[a-z] ]] && ! [[ "$line" =~ ^[[:space:]]{4} ]]; then
                    in_section=false
                    continue
                fi
                # Match "    key: value"
                if [[ "$line" =~ ^[[:space:]]+${key}:[[:space:]]+(.+) ]]; then
                    local val="${BASH_REMATCH[1]}"
                    val="${val%%#*}"
                    val="${val// /}"
                    val="${val//\"/}"
                    val="${val//\'/}"
                    echo "$val"
                    return 0
                fi
            fi
        fi
    done < "$file"

    return 1
}

# =============================================================================
# _channels_load_config "$channel"
# Parse channels section from .craft-config.yml and set module vars.
# Falls back to defaults if no config file or missing keys.
# =============================================================================
_channels_load_config() {
    local channel="$1"

    _CHANNEL_THRESHOLD=3
    _CHANNEL_COOLDOWN=300
    _CHANNEL_CACHE_TTL=3600
    _CHANNEL_CACHE_MAX=200

    local config_file="${PWD}/.craft-config.yml"
    [[ -f "$config_file" ]] || return 0

    local val
    val=$(_channels_parse_nested_yml "$channel" "circuit_threshold" "$config_file") && _CHANNEL_THRESHOLD="$val"
    val=$(_channels_parse_nested_yml "$channel" "circuit_cooldown" "$config_file") && _CHANNEL_COOLDOWN="$val"
    val=$(_channels_parse_nested_yml "$channel" "cache_ttl" "$config_file") && _CHANNEL_CACHE_TTL="$val"
    val=$(_channels_parse_nested_yml "$channel" "cache_max_entries" "$config_file") && _CHANNEL_CACHE_MAX="$val"
}

# =============================================================================
# channel_available "$channel"
# Check if a channel is configured. Initialize circuit breaker if available.
# Returns 0 if configured, 1 otherwise.
# =============================================================================
channel_available() {
    local channel="$1"
    case "$channel" in
        sentry)
            config_sentry_enabled || return 1
            if $_CB_AVAILABLE; then
                _channels_load_config "$channel"
                cb_init "$channel" "$_CHANNEL_THRESHOLD" "$_CHANNEL_COOLDOWN"
            fi
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# channel_call "$channel" "$cache_key"
# Full lifecycle with circuit breaker and cache orchestration.
# Sets CHANNEL_CALL_SOURCE to: "stale", "cached", or "live"
#
# Returns cached/stale content on stdout, or empty if live call needed.
# =============================================================================
channel_call() {
    local channel="$1" cache_key="${2:-default}"
    CHANNEL_CALL_SOURCE=""

    _channels_load_config "$channel"

    if $_CB_AVAILABLE; then
        cb_init "$channel" "$_CHANNEL_THRESHOLD" "$_CHANNEL_COOLDOWN"
    fi

    local state="closed"
    if $_CB_AVAILABLE; then
        state=$(cb_state "$channel")
    fi

    # Circuit OPEN: serve stale cache
    if [[ "$state" == "open" ]]; then
        if $_CACHE_AVAILABLE; then
            local stale
            stale=$(cache_get_stale "$channel" "$cache_key")
            if [[ -n "$stale" ]]; then
                CHANNEL_CALL_SOURCE="stale"
                echo "$stale"
                return 0
            fi
        fi
        CHANNEL_CALL_SOURCE="stale"
        return 0
    fi

    # Circuit CLOSED or HALF-OPEN: check fresh cache first
    if $_CACHE_AVAILABLE; then
        local cached
        cached=$(cache_get "$channel" "$cache_key")
        if [[ -n "$cached" ]]; then
            CHANNEL_CALL_SOURCE="cached"
            echo "$cached"
            return 0
        fi
    fi

    # No cache hit: caller handles live call
    CHANNEL_CALL_SOURCE="live"
    return 0
}

# =============================================================================
# channel_health "$channel"
# Returns circuit breaker state: closed, open, or half-open.
# Falls back to "closed" if circuit breaker is not available.
# =============================================================================
channel_health() {
    local channel="$1"
    if $_CB_AVAILABLE; then
        cb_state "$channel"
    else
        echo "closed"
    fi
}

# =============================================================================
# channel_reset "$channel"
# Force circuit breaker to CLOSED state.
# =============================================================================
channel_reset() {
    local channel="$1"
    if $_CB_AVAILABLE; then
        cb_reset "$channel"
    fi
}

# =============================================================================
# channel_status_summary
# Returns summary string for InstructionsLoaded agent.
# Format: "sentry:closed " or "sentry:open (cooldown Xm Ys remaining) "
# Falls back to "sentry:enabled " when circuit breaker is not available.
# =============================================================================
channel_status_summary() {
    local summary=""

    if channel_available "sentry"; then
        if $_CB_AVAILABLE; then
            local state
            state=$(cb_state "sentry")
            if [[ "$state" == "open" ]]; then
                local file opened_at cooldown now remaining remaining_m remaining_s
                file=$(_cb_state_file "sentry" 2>/dev/null)
                if [[ -n "$file" ]] && [[ -f "$file" ]]; then
                    opened_at=$(jq -r '.opened_at // empty' "$file" 2>/dev/null)
                    cooldown=$(jq -r '.cooldown_seconds' "$file" 2>/dev/null)
                    now=$(date +%s)
                    if [[ -n "$opened_at" ]] && [[ "$opened_at" != "null" ]]; then
                        remaining=$(( (opened_at + cooldown) - now ))
                        [[ $remaining -lt 0 ]] && remaining=0
                        remaining_m=$(( remaining / 60 ))
                        remaining_s=$(( remaining % 60 ))
                        summary="${summary}sentry:open (cooldown ${remaining_m}m ${remaining_s}s remaining) "
                    else
                        summary="${summary}sentry:open "
                    fi
                else
                    summary="${summary}sentry:open "
                fi
            else
                summary="${summary}sentry:${state} "
            fi
        else
            summary="${summary}sentry:enabled "
        fi
    fi

    echo "$summary"
}
