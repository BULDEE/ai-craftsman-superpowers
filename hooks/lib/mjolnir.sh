#!/usr/bin/env bash
# =============================================================================
# Mjolnir Companion Library — Norse forge repliques for quality events
#
# Usage:
#   source "${SCRIPT_DIR}/lib/mjolnir.sh"
#   mjolnir_enabled          # returns 0 if on, 1 if off
#   mjolnir_pick <event>     # random replique for event
#   mjolnir_line <event>     # formatted "⚒ Mjolnir: ..." or empty if disabled
# =============================================================================

# Replique pools — indexed by event name
_MJ_SESSION_START=("The forge is lit." "Steel awaits." "The anvil is ready.")
_MJ_VIOLATION_BLOCKED=("Weak steel." "Unworthy." "The forge rejects this." "Back to the crucible.")
_MJ_VIOLATION_CORRECTED=("Tempered." "Better steel." "The blade holds.")
_MJ_VERIFY_PASS=("Forged and true." "Ready for battle." "The steel holds.")
_MJ_VERIFY_FAIL=("Unfinished blade." "Back to the anvil." "Not yet worthy.")
_MJ_PUSH_SUCCESS=("Sent to the front." "The blade ships." "The forge delivers.")

mjolnir_enabled() {
    local val="${CLAUDE_PLUGIN_OPTION_mjolnir:-true}"
    [[ "$val" == "true" || "$val" == "1" ]]
}

mjolnir_pick() {
    local event="$1"
    local pool=()
    case "$event" in
        session_start)        pool=("${_MJ_SESSION_START[@]}") ;;
        violation_blocked)    pool=("${_MJ_VIOLATION_BLOCKED[@]}") ;;
        violation_corrected)  pool=("${_MJ_VIOLATION_CORRECTED[@]}") ;;
        verify_pass)          pool=("${_MJ_VERIFY_PASS[@]}") ;;
        verify_fail)          pool=("${_MJ_VERIFY_FAIL[@]}") ;;
        push_success)         pool=("${_MJ_PUSH_SUCCESS[@]}") ;;
        *)                    return 0 ;;
    esac
    local count=${#pool[@]}
    [[ $count -eq 0 ]] && return 0
    local idx=$((RANDOM % count))
    echo "${pool[$idx]}"
}

mjolnir_line() {
    mjolnir_enabled || return 0
    local replique
    replique=$(mjolnir_pick "$1")
    [[ -z "$replique" ]] && return 0
    echo "⚒ Mjolnir: \"${replique}\""
}
