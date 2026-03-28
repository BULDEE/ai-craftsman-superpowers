#!/usr/bin/env bash
# =============================================================================
# Config Resolution Library
# Resolves configuration from multiple sources with priority:
#   1. .craft-config.yml in $PWD (highest)
#   2. CLAUDE_PLUGIN_OPTION_* env vars
#   3. Hardcoded defaults (lowest)
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
#   strictness=$(config_strictness)   # strict | moderate | relaxed
#   stack=$(config_stack)             # symfony | react | fullstack | other
#   config_php_enabled && echo "PHP checks active"
#   config_ts_enabled  && echo "TS checks active"
#   config_should_block "PHP001" && exit 2 || echo "warn only"
# =============================================================================

_config_parse_yml_value() {
    local key="$1"
    local file="$2"
    grep -E "^${key}:" "$file" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"
}

config_strictness() {
    local yml_value=""
    if [[ -f "$PWD/.craft-config.yml" ]]; then
        yml_value=$(_config_parse_yml_value "strictness" "$PWD/.craft-config.yml")
    fi

    if [[ -n "$yml_value" ]]; then
        echo "$yml_value"
        return 0
    fi

    if [[ -n "${CLAUDE_PLUGIN_OPTION_strictness:-}" ]]; then
        echo "$CLAUDE_PLUGIN_OPTION_strictness"
        return 0
    fi

    echo "strict"
}

config_stack() {
    local yml_value=""
    if [[ -f "$PWD/.craft-config.yml" ]]; then
        yml_value=$(_config_parse_yml_value "stack" "$PWD/.craft-config.yml")
    fi

    if [[ -n "$yml_value" ]]; then
        echo "$yml_value"
        return 0
    fi

    if [[ -n "${CLAUDE_PLUGIN_OPTION_stack:-}" ]]; then
        echo "$CLAUDE_PLUGIN_OPTION_stack"
        return 0
    fi

    echo "fullstack"
}

config_php_enabled() {
    local stack
    stack=$(config_stack)
    case "$stack" in
        symfony|fullstack) return 0 ;;
        *) return 1 ;;
    esac
}

config_ts_enabled() {
    local stack
    stack=$(config_stack)
    case "$stack" in
        react|fullstack) return 0 ;;
        *) return 1 ;;
    esac
}

config_should_block() {
    local rule="$1"

    # Warnings never block regardless of strictness
    case "$rule" in
        WARN*|PHP005) return 1 ;;
    esac

    local strictness
    strictness=$(config_strictness)
    case "$strictness" in
        strict)   return 0 ;;
        moderate) [[ "$rule" == LAYER* ]] && return 0; return 1 ;;
        relaxed)  return 1 ;;
        *)        return 0 ;;
    esac
}

config_stop_review_enabled() {
    local strictness
    strictness=$(config_strictness)
    [[ "$strictness" == "strict" ]]
}
