#!/usr/bin/env bash
# =============================================================================
# Hook Events Configuration
# Defines all valid Claude Code hook lifecycle events supported by Claude Code plugin
# =============================================================================

# Array of all valid hook event types
# Source: https://code.claude.com/docs/en/hooks#event-types
declare -ra VALID_HOOK_EVENTS=(
    "SessionStart"
    "PreToolUse"
    "PostToolUse"
    "PostToolUseFailure"
    "UserPromptSubmit"
    "PermissionRequest"
    "PermissionDenied"
    "Notification"
    "SubagentStart"
    "SubagentStop"
    "TaskCreated"
    "TaskCompleted"
    "TeammateIdle"
    "InstructionsLoaded"
    "ConfigChange"
    "CwdChanged"
    "FileChanged"
    "WorktreeCreate"
    "WorktreeRemove"
    "PreCompact"
    "PostCompact"
    "Elicitation"
    "ElicitationResult"
    "Stop"
    "StopFailure"
    "SessionEnd"
)

# Get all valid hook events as a comma-separated string
hook_events_comma_separated() {
    echo "${VALID_HOOK_EVENTS[@]}" | tr ' ' ','
}

# Get all valid hook events as a Python set literal (for Python validation)
hook_events_python_set() {
    local events_str=""
    for event in "${VALID_HOOK_EVENTS[@]}"; do
        if [[ -z "$events_str" ]]; then
            events_str="'$event'"
        else
            events_str="${events_str},'$event'"
        fi
    done
    echo "{${events_str}}"
}

# Check if a given hook event is valid
is_valid_hook_event() {
    local event="$1"
    local event_found=false

    for valid_event in "${VALID_HOOK_EVENTS[@]}"; do
        if [[ "$valid_event" == "$event" ]]; then
            event_found=true
            break
        fi
    done

    if $event_found; then
        return 0
    else
        return 1
    fi
}
