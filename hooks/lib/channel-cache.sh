#!/usr/bin/env bash
# =============================================================================
# Channel Cache (File-Based with TTL + LRU Eviction)
# Caches external channel responses to reduce API calls and provide stale
# fallback when circuits are open.
#
# Cache dir: ${CLAUDE_PLUGIN_DATA}/channel-cache/<channel>/
# Each entry: {sha256_of_key}.json
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/channel-cache.sh"
#   cache_set "sentry" "issues:open" "42 issues" 60
#   cache_get "sentry" "issues:open"         # empty if expired
#   cache_get_stale "sentry" "issues:open"   # returns even if expired
#   cache_evict "sentry" 100                 # LRU eviction, keep max 100
# =============================================================================

_CACHE_BASE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/channel-cache"

_cache_channel_dir() {
    echo "${_CACHE_BASE_DIR}/${1}"
}

_cache_key_hash() {
    echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

_cache_entry_file() {
    local channel="$1" key="$2"
    local hash
    hash=$(_cache_key_hash "$key")
    echo "$(_cache_channel_dir "$channel")/${hash}.json"
}

cache_set() {
    local channel="$1" key="$2" value="$3" ttl="${4:-300}"
    local dir
    dir=$(_cache_channel_dir "$channel")
    mkdir -p "$dir"

    local now expires file
    now=$(date +%s)
    expires=$(( now + ttl ))
    file=$(_cache_entry_file "$channel" "$key")

    jq -n \
        --arg k "$key" \
        --arg v "$value" \
        --argjson ca "$now" \
        --argjson ea "$expires" \
        '{key:$k, value:$v, created_at:$ca, expires_at:$ea}' \
        > "$file"
}

cache_get() {
    local channel="$1" key="$2"
    local file
    file=$(_cache_entry_file "$channel" "$key")
    [[ -f "$file" ]] || return 0

    local expires_at now
    expires_at=$(jq -r '.expires_at' "$file" 2>/dev/null)
    now=$(date +%s)

    if [[ $now -ge $expires_at ]]; then
        return 0
    fi

    jq -r '.value' "$file" 2>/dev/null
}

cache_get_stale() {
    local channel="$1" key="$2"
    local file
    file=$(_cache_entry_file "$channel" "$key")
    [[ -f "$file" ]] || return 0

    jq -r '.value' "$file" 2>/dev/null
}

cache_evict() {
    local channel="$1" max_entries="${2:-100}"
    local dir
    dir=$(_cache_channel_dir "$channel")
    [[ -d "$dir" ]] || return 0

    local count
    count=$(find "$dir" -name '*.json' -type f | wc -l | tr -d ' ')

    if [[ $count -le $max_entries ]]; then
        return 0
    fi

    local to_remove=$(( count - max_entries ))

    # Sort by modification time ascending (oldest first), remove the oldest
    ls -1t "$dir"/*.json 2>/dev/null | tail -n "$to_remove" | while read -r f; do
        rm -f "$f"
    done
}
