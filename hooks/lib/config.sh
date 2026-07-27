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
        moderate) [[ "$rule" == LAYER* || "$rule" == SEC* ]] && return 0; return 1 ;;
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

# Parse external pack paths from the USER'S OWN global config.
# Returns one path per line (resolves ~ to $HOME).
#
# SECURITY (deliberate asymmetry with every other config key): external packs
# are `source`d verbatim by pack-loader.sh, so declaring one is equivalent to
# granting arbitrary code execution. Reading this key from the project file
# would let any cloned repository execute code the moment a session starts,
# before the developer writes anything. Only the machine owner may declare
# them, in ~/.claude/.craft-config.yml. Every other key still honours the
# project override: this one cannot.
# Level 2 static analysis runs the PROJECT's own tools: vendor/bin/phpstan,
# node_modules/.bin/eslint, and the config files they auto-discover. In a
# cloned repository all of those are attacker-supplied, and eslint's flat
# config is executable JavaScript by design, so running them at all is running
# the repository's code. Off unless the machine owner opts in globally; every
# other level (regex rules, layer rules, security rules, the ratchet) is ours
# and keeps working untouched.
config_trust_project_tools() {
    local config_file="${HOME}/.claude/.craft-config.yml"
    [[ -f "$config_file" ]] || return 1
    local value
    value=$(grep -E "^trust_project_tools:" "$config_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    [[ "$value" == "true" ]]
}

config_external_packs() {
    local config_file="${HOME}/.claude/.craft-config.yml"
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

# The LAYER rules used to look for "App\Domain" and "App\Infrastructure"
# literally. "App" is the Symfony skeleton's default and nothing more: a
# project that renamed its root namespace, or a monorepo with several, got
# silent green from every layer rule. The root comes from composer.json's
# psr-4 map instead, preferring the entry that maps to src/.
_CONFIG_NS_ROOT_CACHE=""
_CONFIG_NS_ROOT_FOR=""

config_php_namespace_root() {
    local start_dir="${1:-$PWD}"
    if [[ "$_CONFIG_NS_ROOT_FOR" == "$start_dir" && -n "$_CONFIG_NS_ROOT_CACHE" ]]; then
        printf '%s' "$_CONFIG_NS_ROOT_CACHE"
        return 0
    fi

    local dir root=""
    dir="$(cd "$start_dir" 2>/dev/null && pwd)" || dir=""
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -f "$dir/composer.json" ]]; then
            root=$(_config_psr4_root "$dir/composer.json")
            break
        fi
        dir="$(dirname "$dir")"
    done

    [[ -n "$root" ]] || root="App"
    _CONFIG_NS_ROOT_FOR="$start_dir"
    _CONFIG_NS_ROOT_CACHE="$root"
    printf '%s' "$root"
}

_config_psr4_root() {
    local composer="$1" root
    root=$(jq -r '
        (.autoload["psr-4"] // {}) as $m
        | ([$m | to_entries[] | select(.value | tostring | test("^src/?$")) | .key]
           + [$m | keys[]])
        | .[0] // empty
    ' "$composer" 2>/dev/null)
    # psr-4 keys carry a trailing separator: "App\\" in JSON is App\ once read.
    printf '%s' "${root%%\\}"
}

# Comma-separated list of disabled hook ids from hooks.disabled (inline form:
# disabled: [a, b]). Merged with CRAFTSMAN_DISABLED_HOOKS by hook-profile.sh.
#
# SECURITY (same asymmetry as external_packs and trust_project_tools above):
# this key is the off switch for the gates themselves, so honouring the project
# file let any cloned repository ship
#   hooks: {disabled: [config-protection, post-write-check, pre-write-check]}
# and start its first session with every gate silently off, including
# config-protection, which declares tier `always` and is deliberately excluded
# from its own protection list. A repository may tune what the gates check; it
# may not decide whether they run. Only the machine owner can, in
# ~/.claude/.craft-config.yml or through CRAFTSMAN_DISABLED_HOOKS.
config_hooks_disabled_csv() {
    local raw=""
    if [[ -f "${HOME}/.claude/.craft-config.yml" ]]; then
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
