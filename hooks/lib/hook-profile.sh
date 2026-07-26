#!/usr/bin/env bash
# =============================================================================
# Hook Profile Library
# Lets a session opt out of secondary/costed hooks without touching plugin
# config, answering the recurring friction of "this hook is too aggressive
# for a trivial change".
#
# Env vars (read fresh on every call, no caching - cheap string ops only):
#   CRAFTSMAN_HOOK_PROFILE   minimal | standard (default) | strict
#   CRAFTSMAN_DISABLED_HOOKS comma-separated hook ids, e.g. "bias-detector,file-changed"
#   CRAFTSMAN_HOOK_DRY_RUN   true|false (default false) - log skip decisions to stderr
#
# Usage (from any hook, right after sourcing):
#   source "${SCRIPT_DIR}/lib/hook-profile.sh"
#   hook_profile_should_run "post-write-check" "always" || exit 0
#
# Profile tiers a hook can declare (2nd arg, comma-separated):
#   always            - never skipped by profile (only by CRAFTSMAN_DISABLED_HOOKS)
#   standard,strict    - skipped when profile=minimal (secondary/costed hooks)
# =============================================================================

# Ensure the config lib (hooks.disabled parsing) is available even for hooks
# that only source hook-profile.sh.
if ! declare -F config_hooks_disabled_csv >/dev/null 2>&1; then
    # shellcheck source=hooks/lib/config.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh" 2>/dev/null || true
fi

_hook_profile_is_disabled() {
    local hook_id="$1"
    local dry_run="$2"
    local disabled="${CRAFTSMAN_DISABLED_HOOKS:-}"

    # Merge config-file kill switches (hooks.disabled, ADR-0021) when the
    # config lib is loaded; hooks that source config.sh get yaml-level
    # opt-outs for free, env var opt-outs always work.
    if declare -F config_hooks_disabled_csv >/dev/null 2>&1; then
        local from_config
        from_config=$(config_hooks_disabled_csv)
        [[ -n "$from_config" ]] && disabled="${disabled},${from_config}"
    fi

    [[ ",${disabled}," == *",${hook_id},"* ]] || return 1
    if [[ "$dry_run" == "true" ]]; then
        echo "HOOK_PROFILE: ${hook_id} skipped (disabled hooks list)" >&2
    fi
    return 0
}

hook_profile_should_run() {
    local hook_id="$1"
    local applicable_profiles="${2:-always}"
    local profile="${CRAFTSMAN_HOOK_PROFILE:-standard}"
    local dry_run="${CRAFTSMAN_HOOK_DRY_RUN:-false}"

    # Explicit per-hook opt-out always wins, regardless of profile
    if _hook_profile_is_disabled "$hook_id" "$dry_run"; then
        [[ "$dry_run" == "true" ]] && return 0
        return 1
    fi

    [[ "$applicable_profiles" == "always" ]] && return 0
    [[ ",${applicable_profiles}," == *",${profile},"* ]] && return 0

    if [[ "$dry_run" == "true" ]]; then
        echo "HOOK_PROFILE: ${hook_id} would be skipped (profile=${profile}, applicable=${applicable_profiles})" >&2
        return 0
    fi

    return 1
}
