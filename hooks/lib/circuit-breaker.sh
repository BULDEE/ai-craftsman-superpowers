#!/usr/bin/env bash
# =============================================================================
# Circuit Breaker State Machine
# Protects against cascading failures from external channels (Sentry, CI, etc.)
#
# States: CLOSED -> OPEN -> HALF-OPEN
# State file: ${CLAUDE_PLUGIN_DATA}/channel-state/<channel>.json
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/circuit-breaker.sh"
#   cb_init "sentry" 3 300
#   cb_state "sentry"           # closed|open|half-open
#   cb_record_failure "sentry"  # increment failures, maybe open
#   cb_record_success "sentry"  # reset failures, close circuit
# =============================================================================

_CB_STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/channel-state"

_cb_state_file() {
    echo "${_CB_STATE_DIR}/${1}.json"
}

_cb_read_field() {
    local channel="$1" field="$2"
    local file
    file=$(_cb_state_file "$channel")
    [[ -f "$file" ]] || return 1
    jq -r ".$field // empty" "$file" 2>/dev/null
}

_cb_write() {
    local channel="$1" json="$2"
    local file
    file=$(_cb_state_file "$channel")
    echo "$json" > "$file"
}

cb_init() {
    local channel="$1" threshold="${2:-3}" cooldown="${3:-300}"
    mkdir -p "$_CB_STATE_DIR"
    local file
    file=$(_cb_state_file "$channel")
    if [[ ! -f "$file" ]]; then
        jq -n \
            --arg ch "$channel" \
            --argjson th "$threshold" \
            --argjson cd "$cooldown" \
            '{channel:$ch, state:"closed", failures:0, threshold:$th, last_failure:null, opened_at:null, cooldown_seconds:$cd}' \
            > "$file"
    fi
}

cb_state() {
    local channel="$1"
    local file
    file=$(_cb_state_file "$channel")
    [[ -f "$file" ]] || { echo "closed"; return; }

    local raw_state opened_at cooldown now
    raw_state=$(jq -r '.state' "$file" 2>/dev/null)
    opened_at=$(jq -r '.opened_at // empty' "$file" 2>/dev/null)
    cooldown=$(jq -r '.cooldown_seconds' "$file" 2>/dev/null)
    now=$(date +%s)

    if [[ "$raw_state" == "open" ]] && [[ -n "$opened_at" ]] && [[ "$opened_at" != "null" ]]; then
        local elapsed=$(( now - opened_at ))
        if [[ $elapsed -ge $cooldown ]]; then
            echo "half-open"
            return
        fi
    fi

    echo "$raw_state"
}

cb_failures() {
    local channel="$1"
    local count
    count=$(_cb_read_field "$channel" "failures")
    echo "${count:-0}"
}

cb_record_success() {
    local channel="$1"
    local file
    file=$(_cb_state_file "$channel")
    [[ -f "$file" ]] || return 0

    local current_state
    current_state=$(cb_state "$channel")

    local updated
    updated=$(jq '.state = "closed" | .failures = 0 | .last_failure = null | .opened_at = null' "$file")
    _cb_write "$channel" "$updated"
}

cb_record_failure() {
    local channel="$1"
    local file
    file=$(_cb_state_file "$channel")
    [[ -f "$file" ]] || return 1

    local current_state now
    current_state=$(cb_state "$channel")
    now=$(date +%s)

    if [[ "$current_state" == "half-open" ]]; then
        local updated
        updated=$(jq --argjson now "$now" \
            '.state = "open" | .opened_at = $now' "$file")
        _cb_write "$channel" "$updated"
        return 0
    fi

    local new_failures threshold
    new_failures=$(jq '.failures + 1' "$file")
    threshold=$(jq '.threshold' "$file")

    local new_state="closed"
    local opened_at_val="null"
    if [[ $new_failures -ge $threshold ]]; then
        new_state="open"
        opened_at_val="$now"
    fi

    local updated
    updated=$(jq \
        --argjson nf "$new_failures" \
        --arg ns "$new_state" \
        --argjson now "$now" \
        --argjson oa "$opened_at_val" \
        '.failures = $nf | .state = $ns | .last_failure = $now | .opened_at = $oa' "$file")
    _cb_write "$channel" "$updated"
}

cb_reset() {
    local channel="$1"
    local file
    file=$(_cb_state_file "$channel")
    [[ -f "$file" ]] || return 0

    local updated
    updated=$(jq '.state = "closed" | .failures = 0 | .last_failure = null | .opened_at = null' "$file")
    _cb_write "$channel" "$updated"
}

cb_status_summary() {
    local channel="$1"
    local file
    file=$(_cb_state_file "$channel")
    if [[ ! -f "$file" ]]; then
        echo "${channel}: not initialized"
        return
    fi

    local state failures threshold cooldown
    state=$(cb_state "$channel")
    failures=$(cb_failures "$channel")
    threshold=$(_cb_read_field "$channel" "threshold")
    cooldown=$(_cb_read_field "$channel" "cooldown_seconds")

    echo "${channel}: ${state} (failures: ${failures}/${threshold}, cooldown: ${cooldown}s)"
}
