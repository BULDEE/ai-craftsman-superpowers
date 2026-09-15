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
#   config_strictness            # strict | moderate | relaxed
# =============================================================================

_config_parse_yml_value() {
    local key="$1"
    local file="$2"
    grep -E "^${key}:" "$file" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"
}

# _config_option_env <key>: the plugin option from the environment, if set.
#
# Claude Code exports an option as CLAUDE_PLUGIN_OPTION_<KEY> with the key
# UPPERCASED (plugins-reference); the lowercase form is the plugin's own
# internal export (ci/craftsman-ci.sh) and what the suites set. Exported form
# first, and both, because for four releases only the second was read and no
# option ever reached a hook from plugin.json.
_config_option_env() {
    local key="$1" env_var
    for env_var in "CLAUDE_PLUGIN_OPTION_$(echo "$key" | tr '[:lower:]' '[:upper:]')" "CLAUDE_PLUGIN_OPTION_${key}"; do
        if [[ -n "${!env_var:-}" ]]; then
            echo "${!env_var}"
            return 0
        fi
    done
    return 1
}

# The global configuration layer: ~/.claude/.craft-config.yml, the documented
# location, for every front-end. The pipeline used to read
# $HOME/.craft-config.yml instead, so a global `PHP002: warn` applied at the
# keyboard and not in CI. A gate an agent runs under sets
# CRAFTSMAN_GLOBAL_CONFIG_DIR to nothing (the Hermes adapter does): a layer
# the same uid can write outside the gated turn must not shape the verdict.
config_global_dir() {
    printf '%s' "${CRAFTSMAN_GLOBAL_CONFIG_DIR-${HOME}/.claude}"
}

# The one global file, from the one resolver. Four readers spelled the path
# out and so ignored CRAFTSMAN_GLOBAL_CONFIG_DIR: a gate that had cleared the
# global layer still read trust_project_tools from it.
config_global_file() {
    local dir
    dir=$(config_global_dir)
    [[ -n "$dir" ]] && printf '%s/.craft-config.yml' "$dir"
}

# Are the four agent hooks (headless model calls) on? The plugin option is one
# way to say no, and the only way a test exercised; a host without plugin
# options (Codex, tests/fixtures/hosts/PROVENANCE.md) had none, so the machine
# owner can also say `hooks: agent_hooks: false` in the global file. Global
# only, like `hooks: disabled`: a repository may not decide whether the
# machine spends model calls.
config_agent_hooks_enabled() {
    local option="${CLAUDE_PLUGIN_OPTION_AGENT_HOOKS:-${CLAUDE_PLUGIN_OPTION_agent_hooks:-}}"
    [[ "$option" == "false" ]] && return 1
    [[ -n "$option" ]] && return 0
    local file value
    file=$(config_global_file)
    [[ -n "$file" && -f "$file" ]] || return 0
    value=$(_config_parse_nested_yml_value "hooks" "agent_hooks" "$file")
    [[ "$value" != "false" ]]
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

    if _config_option_env "$key"; then
        return 0
    fi

    if [[ -n "$(config_global_dir)" && -f "$(config_global_dir)/.craft-config.yml" ]]; then
        yml_value=$(_config_parse_yml_value "$key" "$(config_global_dir)/.craft-config.yml")
        if [[ -n "$yml_value" ]]; then
            echo "$yml_value"
            return 0
        fi
    fi

    echo "$default"
}

# The strictness a project gets when nothing declares one.
#
# `strict` for a new project, `moderate` for one that already exists. This is
# a code path and not a line in a setup guide on purpose: the mapping used to
# live only in skills/setup/SKILL.md, as prose a model was expected to follow,
# and a decision that opens or closes the front door of the gate cannot depend
# on that. It is also the answer `--quick` needs, and `--quick` is used by the
# people least likely to notice a bad default.
#
# Why `moderate` on an existing codebase: measured on a real Symfony
# application, 400 files sampled, 98% have no declare(strict_types=1) and 88%
# are not final. Under `strict` the first edit to nearly every file is refused
# for code the user did not write, and the rational response is to relax every
# rule, after which the plugin enforces nothing. `moderate` is not a weaker
# gate, it is the gate aimed at the diff: LAYER* and SEC* still block under it.
#
# A repository is "existing" past 20 commits, the same threshold
# hooks/lib/conventions.py uses for `existing_project`, so the observation
# step and this function cannot disagree.
CONFIG_EXISTING_PROJECT_COMMITS=20

# A mark buys back `strict`, and it has to.
#
# Without this the two halves of this feature cancel each other out, which an
# adversarial run measured: under `moderate` only LAYER* and SEC* block, SEC* is
# exempt from the baseline by design, so on any repository past 20 commits the
# whole rule baseline is inert. A brand new file full of violations passed with
# four warnings. "Inherited debt reports, new debt still blocks" was false on
# exactly the population the feature exists for.
#
# So the two settings answer two different questions. `moderate` is for a
# repository whose debt has never been measured: report everything, block only
# a boundary or a secret. Taking the mark IS the measurement, and once it is
# taken `strict` is survivable, because the debt it would refuse is recorded
# and reported without blocking. `craftsman-ci baseline` is what moves a
# project from one to the other, and `/craftsman:setup` step D runs it.
_config_has_baseline() {
    local dir="${1:-$PWD}"
    dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        [[ -f "$dir/.craftsman-baseline.json" ]] && return 0
        [[ -e "$dir/.git" ]] && return 1
        dir="$(dirname "$dir")"
    done
    return 1
}

config_default_strictness() {
    local project_dir="${1:-$PWD}"
    local commits
    commits=$(git -C "$project_dir" rev-list --count HEAD 2>/dev/null) || commits=0
    [[ "$commits" =~ ^[0-9]+$ ]] || commits=0
    if [[ "$commits" -lt "$CONFIG_EXISTING_PROJECT_COMMITS" ]]; then
        printf 'strict'
        return 0
    fi
    if _config_has_baseline "$project_dir"; then
        printf 'strict'
    else
        printf 'moderate'
    fi
}

config_strictness() {
    _config_resolve "strictness" "$(config_default_strictness)"
}

config_stack() {
    _config_resolve "stack" "fullstack"
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
    local config_file
    config_file=$(config_global_file)
    [[ -n "$config_file" && -f "$config_file" ]] || return 1
    # Read in-shell. This was grep | head | awk | tr | tr: five processes to
    # answer one boolean, on a hook that runs on every write.
    #
    # Three shapes had to be decided explicitly rather than inherited from what
    # a pipeline happened to do, because this key is the plugin's ONLY consent
    # to run a cloned repository's own analysers:
    #
    #   trust_project_tools:true          NOT a YAML mapping (no space after
    #                                     the colon), so not this key. Refused,
    #                                     as the pipeline refused it.
    #   trust_project_tools: true # why   a comment is not part of the value.
    #                                     Honoured, as the pipeline honoured it.
    #   trust_project_tools: true\r\n      a CRLF file is valid YAML and the
    #                                     machine owner wrote it. Honoured,
    #                                     where the pipeline silently ignored
    #                                     the whole line. This one is a
    #                                     deliberate change, asserted in
    #                                     tests/core/test-config.sh.
    local line value=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "trust_project_tools:"[[:space:]]*) ;;
            *) continue ;;
        esac
        value="${line#trust_project_tools:}"
        value="${value%%#*}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value//\"/}"
        value="${value//\'/}"
        break
    done < "$config_file"
    [[ "$value" == "true" ]]
}

config_external_packs() {
    local config_file
    config_file=$(config_global_file)
    [[ -z "$config_file" || ! -f "$config_file" ]] && return

    # Matched in-shell, one process for the whole file.
    #
    # This ran `echo "$line" | grep` once per line, and up to three times per
    # line inside the block. A 50-line ~/.claude/.craft-config.yml therefore
    # cost 50 to 150 process starts, on a function called by every hook on
    # every write: measured at half of post-write-check.sh's entire runtime,
    # to read a key most installations do not even set.
    local in_external=false path_val
    while IFS= read -r line || [[ -n "$line" ]]; do
        # A CRLF file is valid YAML. The pipeline this replaced emitted the
        # path with the carriage return still attached, so the directory test
        # downstream failed and the pack was silently not loaded: the machine
        # owner's own declaration, ignored without a word.
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]+external: ]]; then
            in_external=true
            continue
        fi
        [[ "$in_external" == true ]] || continue

        # Out of the nested block on any key indented three spaces or less.
        if [[ "$line" =~ ^[[:space:]]{0,3}[a-zA-Z] ]]; then
            in_external=false
            continue
        fi
        [[ "$line" =~ path:[[:space:]]*(.*)$ ]] || continue
        path_val="${BASH_REMATCH[1]}"
        path_val="${path_val%%#*}"
        path_val="${path_val%"${path_val##*[![:space:]]}"}"
        path_val="${path_val//\"/}"
        path_val="${path_val//\'/}"
        [[ -z "$path_val" ]] && continue
        path_val="${path_val/#\~/$HOME}"
        echo "$path_val"
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
    local global_file
    global_file=$(config_global_file)
    if [[ -z "$value" && -n "$global_file" && -f "$global_file" ]]; then
        value=$(_config_parse_nested_yml_value "$section" "$key" "$global_file")
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
    local raw="" global_file
    global_file=$(config_global_file)
    if [[ -n "$global_file" && -f "$global_file" ]]; then
        raw=$(_config_parse_nested_inline_list "hooks" "disabled" "$global_file")
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
