#!/usr/bin/env bash
# =============================================================================
# Config Resolution Library
# Resolves configuration from multiple sources with priority:
#   1. .craft-config.yml in $PWD (highest)
#   2. CLAUDE_PLUGIN_OPTION_* env vars (explicit plugin config, can be project-scoped)
#   3. .craft-config.yml in ~/.claude (global, shared across projects)
#   4. Hardcoded defaults (lowest)
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

_config_resolve() {
    local key="$1"
    local default="$2"

    local yml_value=""
    if [[ -f "$PWD/.craft-config.yml" ]]; then
        yml_value=$(_config_parse_yml_value "$key" "$PWD/.craft-config.yml")
    fi

    if [[ -n "$yml_value" ]]; then
        echo "$yml_value"
        return 0
    fi

    local env_var="CLAUDE_PLUGIN_OPTION_${key}"
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    if [[ -f "${HOME}/.claude/.craft-config.yml" ]]; then
        yml_value=$(_config_parse_yml_value "$key" "${HOME}/.claude/.craft-config.yml")
        if [[ -n "$yml_value" ]]; then
            echo "$yml_value"
            return 0
        fi
    fi

    echo "$default"
}

config_strictness() {
    _config_resolve "strictness" "strict"
}

config_stack() {
    _config_resolve "stack" "fullstack"
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
        moderate) [[ "$rule" == LAYER* || "$rule" == RATCHET* || "$rule" == SEC* ]] && return 0; return 1 ;;
        relaxed)  return 1 ;;
        *)        return 0 ;;
    esac
}

config_guided() {
    local value
    value=$(_config_resolve "guided" "false")
    [[ "$value" == "true" ]]
}

config_stop_review_enabled() {
    local strictness
    strictness=$(config_strictness)
    [[ "$strictness" == "strict" ]]
}

config_sentry_org() {
    _config_resolve "sentry_org" ""
}

config_sentry_project() {
    _config_resolve "sentry_project" ""
}

config_sentry_enabled() {
    [[ -n "$(config_sentry_org)" ]] && [[ -n "$(config_sentry_project)" ]]
}

config_packs_dir() {
    echo "${CLAUDE_PLUGIN_ROOT:-$(pwd)}/packs"
}

# Parse external pack paths from .craft-config.yml
# Returns one path per line (resolves ~ to $HOME)
config_external_packs() {
    local config_file="$PWD/.craft-config.yml"
    [[ ! -f "$config_file" ]] && return

    local in_external=false
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^[[:space:]]+external:'; then
            in_external=true
            continue
        fi
        if [[ "$in_external" == true ]]; then
            # Exit nested block on non-indented or less-indented key
            if echo "$line" | grep -qE '^[a-zA-Z]' || echo "$line" | grep -qE '^[[:space:]]{0,3}[a-zA-Z]'; then
                in_external=false
                continue
            fi
            local path_val
            path_val=$(echo "$line" | grep -oE 'path:[[:space:]]*.*' | sed -E 's/^path:[[:space:]]*//' | tr -d '"' | tr -d "'")
            if [[ -n "$path_val" ]]; then
                path_val="${path_val/#\~/$HOME}"
                echo "$path_val"
            fi
        fi
    done < "$config_file"
}

# =============================================================================
# v4 context budgets and per-hook kill switches (ADR-0021)
# =============================================================================

# Parse a nested "section: / key: value" pair from a yml file (2-space indent).
_config_parse_nested_yml_value() {
    local section="$1" key="$2" file="$3"
    awk -v section="$section" -v key="$key" '
        $0 ~ "^" section ":" { in_section = 1; next }
        /^[a-zA-Z]/ { in_section = 0 }
        in_section && $1 == key ":" { gsub(/["'"'"']/, "", $2); print $2; exit }
    ' "$file" 2>/dev/null
}

_config_resolve_nested() {
    local section="$1" key="$2" default="$3"
    local value=""
    if [[ -f "$PWD/.craft-config.yml" ]]; then
        value=$(_config_parse_nested_yml_value "$section" "$key" "$PWD/.craft-config.yml")
    fi
    if [[ -z "$value" && -f "${HOME}/.claude/.craft-config.yml" ]]; then
        value=$(_config_parse_nested_yml_value "$section" "$key" "${HOME}/.claude/.craft-config.yml")
    fi
    [[ -n "$value" ]] && echo "$value" || echo "$default"
}

config_session_start_max_chars() {
    local v
    v=$(_config_resolve_nested "context_budget" "session_start_max_chars" "4000")
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo "4000"
}

config_max_learned_skills() {
    local v
    v=$(_config_resolve_nested "context_budget" "max_learned_skills" "6")
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo "6"
}

# Comma-separated list of disabled hook ids from hooks.disabled (inline form:
# disabled: [a, b]). Merged with CRAFTSMAN_DISABLED_HOOKS by hook-profile.sh.
config_hooks_disabled_csv() {
    local raw=""
    if [[ -f "$PWD/.craft-config.yml" ]]; then
        raw=$(_config_parse_nested_inline_list "hooks" "disabled" "$PWD/.craft-config.yml")
    fi
    if [[ -z "$raw" && -f "${HOME}/.claude/.craft-config.yml" ]]; then
        raw=$(_config_parse_nested_inline_list "hooks" "disabled" "${HOME}/.claude/.craft-config.yml")
    fi
    echo "$raw"
}

_config_parse_nested_inline_list() {
    local section="$1" key="$2" file="$3"
    awk -v section="$section" -v key="$key" '
        $0 ~ "^" section ":" { in_section = 1; next }
        /^[a-zA-Z]/ { in_section = 0 }
        in_section && $1 == key ":" {
            sub(/^[^:]*:[[:space:]]*/, "")
            gsub(/[\[\]"'"'"' ]/, "")
            print
            exit
        }
    ' "$file" 2>/dev/null
}
