#!/usr/bin/env bash
# =============================================================================
# Which permission mode the session is in, from the hook's own input.
#
# Claude Code passes `permission_mode` in the common fields of every hook's
# JSON (default, plan, acceptEdits, auto, dontAsk, bypassPermissions). Nothing
# in this plugin read it, and the cost of that was not theoretical:
#
#   - In `plan` the harness does NOT execute the Write, and post-write-check.sh
#     ran anyway and recorded a violation. Every one of those rows is a
#     violation on a file that was never written, and they feed /craftsman:metrics,
#     the 7-day trends and the instinct candidate query, so the noise reached
#     the learning loop with no way to tell it apart.
#   - In `plan` agent-ddd-verifier.sh spent a headless Haiku subprocess on a
#     file the harness will not create.
#
# What does NOT change: the finding is still printed in plan mode, because the
# value of a check while planning is telling the model what its plan would
# break. And the gate keeps blocking in every mode including bypassPermissions,
# which the hooks reference says outranks a permissionDecision: that stays a
# decision taken on purpose rather than by omission.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/permission-mode.sh"
#   MODE=$(hook_permission_mode "$INPUT")
#   hook_mode_records_metrics "$MODE" || skip the write
# =============================================================================

# hook_permission_mode <hook-json>
# Prints the mode, or "default" when the field is absent (every version of the
# harness before it existed, and every caller that builds its own input).
hook_permission_mode() {
    local input="$1" mode=""
    if command -v jq >/dev/null 2>&1; then
        mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
    fi
    case "$mode" in
        plan|default|acceptEdits|auto|dontAsk|bypassPermissions) printf '%s' "$mode" ;;
        # An unknown mode is treated as `default`, which is the strict reading:
        # a mode this plugin has never heard of must not silently turn anything
        # off. New modes appear in the harness faster than here.
        *) printf 'default' ;;
    esac
}

# Nothing is written to the metrics database for a file the harness will not
# write. A phantom violation is worse than a missing one: it is counted, it
# moves a trend, and nothing in the row says it never happened.
hook_mode_records_metrics() {
    [[ "${1:-default}" != "plan" ]]
}

# No paid subprocess for a file that will not exist.
hook_mode_runs_verification() {
    [[ "${1:-default}" != "plan" ]]
}
