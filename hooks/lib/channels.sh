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
_channels_extract_yml_value() {
    local key="$1" line="$2"
    if [[ "$line" =~ ^[[:space:]]+${key}:[[:space:]]+(.+) ]]; then
        local val="${BASH_REMATCH[1]}"
        val="${val%%#*}"
        val="${val// /}"
        val="${val//\"/}"
        val="${val//\'/}"
        echo "$val"
        return 0
    fi
    return 1
}

_channels_parse_line() {
    local section="$1" key="$2" line="$3"
    local in_channels="$4" in_section="$5"

    if [[ "$in_channels" == "true" ]]; then
        if [[ "$line" =~ ^[a-z] ]]; then
            echo "false false"
            return 1
        fi
        if [[ "$line" =~ ^[[:space:]]{2}${section}: ]]; then
            echo "true true"
            return 1
        fi
        if [[ "$in_section" == "true" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-z] ]] && ! [[ "$line" =~ ^[[:space:]]{4} ]]; then
                echo "true false"
                return 1
            fi
            if _channels_extract_yml_value "$key" "$line"; then
                return 0
            fi
        fi
    fi
    echo "$in_channels $in_section"
    return 1
}

_channels_parse_nested_yml() {
    local section="$1" key="$2" file="$3"
    [[ -f "$file" ]] || return 1

    local in_channels=false in_section=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        if [[ "$line" =~ ^channels: ]]; then
            in_channels=true
            continue
        fi
        local result
        result=$(_channels_parse_line "$section" "$key" "$line" "$in_channels" "$in_section")
        if [[ $? -eq 0 ]]; then
            echo "$result"
            return 0
        fi
        in_channels="${result%% *}"
        in_section="${result##* }"
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
_channel_call_serve_stale() {
    local channel="$1" cache_key="$2"
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
}

_channel_call_serve_cached() {
    local channel="$1" cache_key="$2"
    if $_CACHE_AVAILABLE; then
        local cached
        cached=$(cache_get "$channel" "$cache_key")
        if [[ -n "$cached" ]]; then
            CHANNEL_CALL_SOURCE="cached"
            echo "$cached"
            return 0
        fi
    fi
    return 1
}

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

    if [[ "$state" == "open" ]]; then
        _channel_call_serve_stale "$channel" "$cache_key"
        return 0
    fi

    if _channel_call_serve_cached "$channel" "$cache_key"; then
        return 0
    fi

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
_channel_format_open_cooldown() {
    local channel="$1"
    local file opened_at cooldown now remaining remaining_m remaining_s
    file=$(_cb_state_file "$channel" 2>/dev/null)
    if [[ -n "$file" ]] && [[ -f "$file" ]]; then
        opened_at=$(jq -r '.opened_at // empty' "$file" 2>/dev/null)
        cooldown=$(jq -r '.cooldown_seconds' "$file" 2>/dev/null)
        now=$(date +%s)
        if [[ -n "$opened_at" ]] && [[ "$opened_at" != "null" ]]; then
            remaining=$(( (opened_at + cooldown) - now ))
            [[ $remaining -lt 0 ]] && remaining=0
            remaining_m=$(( remaining / 60 ))
            remaining_s=$(( remaining % 60 ))
            echo "${channel}:open (cooldown ${remaining_m}m ${remaining_s}s remaining) "
            return 0
        fi
    fi
    echo "${channel}:open "
}

_channel_format_status() {
    local channel="$1"
    if ! $_CB_AVAILABLE; then
        echo "${channel}:enabled "
        return 0
    fi
    local state
    state=$(cb_state "$channel")
    if [[ "$state" == "open" ]]; then
        _channel_format_open_cooldown "$channel"
        return 0
    fi
    echo "${channel}:${state} "
}

channel_status_summary() {
    local summary=""
    if channel_available "sentry"; then
        summary="${summary}$(_channel_format_status "sentry")"
    fi
    echo "$summary"
}
