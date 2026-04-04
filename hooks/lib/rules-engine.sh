#!/usr/bin/env bash
# =============================================================================
# Rules Engine — 3-level config inheritance with custom rules
# Resolves rule severity from: global → project → directory overrides
#
# Config format (.craft-config.yml):
#   version: "2.1"
#   strictness: strict|moderate|relaxed
#   rules:
#     PHP001: block           # Short form
#     CUSTOM001:              # Long form (custom rule)
#       pattern: "dd\\("
#       message: "No dd()"
#       severity: block
#       languages: [php]
#
# Directory override (.craft-rules.yml — rules section only):
#   rules:
#     PHP002: ignore
#
# Usage:
#   source "hooks/lib/rules-engine.sh"
#   rules_init "$project_dir" ["$global_dir"]
#   rules_severity "PHP001"                            # block|warn|ignore
#   rules_severity_for_file "src/Infra/Repo.php" "PHP001"
#   rules_custom_list "php"                            # CUSTOM001\nCUSTOM002
#   rules_pattern "CUSTOM001"                          # regex pattern
#   rules_message "CUSTOM001"                          # human message
# =============================================================================

# ---------------------------------------------------------------------------
# Storage: file-based key-value store (bash 3.2 compatible)
# Each "associative array" is a directory of files: key → content
# ---------------------------------------------------------------------------
_RULES_STORE=""
_RULES_PROJECT_DIR=""
_RULES_STRICTNESS="strict"

_rules_store_dir() {
    local namespace="$1"
    echo "$_RULES_STORE/$namespace"
}

_rules_set() {
    local namespace="$1" key="$2" value="$3"
    local dir
    dir="$(_rules_store_dir "$namespace")"
    mkdir -p "$dir"
    printf '%s' "$value" > "$dir/$key"
}

_rules_get() {
    local namespace="$1" key="$2"
    local file
    file="$(_rules_store_dir "$namespace")/$key"
    if [[ -f "$file" ]]; then
        cat "$file"
    fi
}

_rules_keys() {
    local namespace="$1"
    local dir
    dir="$(_rules_store_dir "$namespace")"
    if [[ -d "$dir" ]]; then
        ls "$dir" 2>/dev/null
    fi
}

_rules_has() {
    local namespace="$1" key="$2"
    [[ -f "$(_rules_store_dir "$namespace")/$key" ]]
}

# ---------------------------------------------------------------------------
# Reset all state (for tests)
# ---------------------------------------------------------------------------
_rules_reset() {
    if [[ -n "$_RULES_STORE" ]] && [[ -d "$_RULES_STORE" ]]; then
        rm -rf "$_RULES_STORE"
    fi
    _RULES_STORE=""
    _RULES_PROJECT_DIR=""
    _RULES_STRICTNESS="strict"
}

_rules_reset_dir_cache() {
    local dir
    dir="$(_rules_store_dir "dir_cache")"
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
    fi
    dir="$(_rules_store_dir "dir_parsed")"
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
    fi
}

_rules_ensure_store() {
    if [[ -z "$_RULES_STORE" ]]; then
        _RULES_STORE=$(mktemp -d "/tmp/craftsman-rules-XXXXXX")
    fi
}

# ---------------------------------------------------------------------------
# Python YAML parser path (co-located with this script)
# ---------------------------------------------------------------------------
_RULES_YAML_PARSER=""
_rules_yaml_parser_path() {
    if [[ -z "$_RULES_YAML_PARSER" ]]; then
        _RULES_YAML_PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yaml-parser.py"
    fi
    echo "$_RULES_YAML_PARSER"
}

# ---------------------------------------------------------------------------
# Parse .craft-config.yml via Python yaml-parser.py → populate stores from JSON
# ---------------------------------------------------------------------------
_rules_apply_parsed_config() {
    local json_output="$1"
    local source_label="$2"

    local val
    val=$(printf '%s' "$json_output" | jq -r '.strictness // empty' 2>/dev/null)
    if [[ -n "$val" ]]; then
        if [[ "$source_label" == "project" ]] || [[ -z "$_RULES_STRICTNESS" ]] || [[ "$_RULES_STRICTNESS" == "strict" && "$source_label" == "global" ]]; then
            _RULES_STRICTNESS="$val"
        fi
    fi

    local rule_ids
    rule_ids=$(printf '%s' "$json_output" | jq -r '.rules // {} | keys[]' 2>/dev/null)

    local rule_id
    for rule_id in $rule_ids; do
        _rules_store_rule_fields "$json_output" "$rule_id"
    done
}

_rules_parse_config() {
    local file="$1"
    local source_label="$2"

    [[ ! -f "$file" ]] && return 0

    local parser_path
    parser_path="$(_rules_yaml_parser_path)"
    local json_output
    json_output=$(python3 "$parser_path" "$file" "config") || json_output="{}"

    if [[ -z "$json_output" ]] || [[ "$json_output" == "{}" ]]; then
        return 0
    fi

    _rules_apply_parsed_config "$json_output" "$source_label"
}

# Store all fields (severity, pattern, message, languages) for a single rule from JSON
_rules_store_rule_fields() {
    local json_output="$1"
    local rule_id="$2"

    local severity
    severity=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].severity // empty" 2>/dev/null)
    [[ -n "$severity" ]] && _rules_set "severity" "$rule_id" "$severity"

    local pattern
    pattern=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].pattern // empty" 2>/dev/null)
    [[ -n "$pattern" ]] && _rules_set "pattern" "$rule_id" "$pattern"

    local message
    message=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].message // empty" 2>/dev/null)
    [[ -n "$message" ]] && _rules_set "message" "$rule_id" "$message"

    local languages
    languages=$(printf '%s' "$json_output" | jq -r '.rules["'"$rule_id"'"].languages // empty | if type == "array" then join(",") else empty end' 2>/dev/null)
    if [[ -n "$languages" ]]; then
        _rules_set "languages" "$rule_id" "$languages"
    else
        local languages_type
        languages_type=$(printf '%s' "$json_output" | jq -r '.rules["'"$rule_id"'"].languages | type' 2>/dev/null)
        [[ "$languages_type" == "array" ]] && _rules_set "languages" "$rule_id" ""
    fi
}

# ---------------------------------------------------------------------------
# Parse directory-level .craft-rules.yml via Python yaml-parser.py
# ---------------------------------------------------------------------------
_rules_parse_dir_config() {
    local file="$1"
    local dir_key="$2"  # sanitized dir path for cache key

    [[ ! -f "$file" ]] && return 0

    local parser_path
    parser_path="$(_rules_yaml_parser_path)"
    local json_output
    json_output=$(python3 "$parser_path" "$file" "rules") || json_output="{}"

    if [[ -z "$json_output" ]] || [[ "$json_output" == "{}" ]]; then
        return 0
    fi

    local rule_ids
    rule_ids=$(printf '%s' "$json_output" | jq -r '.rules // {} | keys[]' 2>/dev/null)

    local rule_id
    for rule_id in $rule_ids; do
        local rule_val
        rule_val=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"]" 2>/dev/null)
        if [[ "$rule_val" =~ ^(block|warn|ignore)$ ]]; then
            _rules_set "dir_cache" "${dir_key}:${rule_id}" "$rule_val"
        fi
    done
}

# ---------------------------------------------------------------------------
# Validate custom rules: pattern, severity, languages
# Invalid rules get severity forced to "ignore" + stderr warning
# ---------------------------------------------------------------------------
_rules_validate_pattern() {
    local rule_id="$1"
    local pattern
    pattern=$(_rules_get "pattern" "$rule_id")
    if [[ -z "$pattern" ]]; then
        echo "[rules-engine] WARNING: Rule $rule_id has no pattern, setting to ignore" >&2
        return 1
    fi
    local grep_ret=0
    echo "test" | grep -E "$pattern" >/dev/null 2>&1 || grep_ret=$?
    if [[ $grep_ret -eq 2 ]]; then
        echo "[rules-engine] WARNING: Rule $rule_id has invalid regex pattern '$pattern', setting to ignore" >&2
        return 1
    fi
    return 0
}

_rules_match_custom_rule() {
    local rule_id="$1"
    local valid=1

    _rules_validate_pattern "$rule_id" || valid=0

    local severity
    severity=$(_rules_get "severity" "$rule_id")
    if [[ -n "$severity" ]] && [[ ! "$severity" =~ ^(block|warn|ignore)$ ]]; then
        valid=0
        echo "[rules-engine] WARNING: Rule $rule_id has invalid severity '$severity', setting to ignore" >&2
    fi

    local languages
    languages=$(_rules_get "languages" "$rule_id")
    if [[ -z "$languages" ]]; then
        valid=0
        echo "[rules-engine] WARNING: Rule $rule_id has no languages, setting to ignore" >&2
    fi

    echo "$valid"
}

_rules_validate_custom() {
    local rule_id="$1"
    local valid
    valid=$(_rules_match_custom_rule "$rule_id")

    if [[ $valid -eq 0 ]]; then
        _rules_set "severity" "$rule_id" "ignore"
    fi
}

# ---------------------------------------------------------------------------
# Compute default severity for a rule based on strictness
# ---------------------------------------------------------------------------
_rules_default_severity() {
    local rule_id="$1"

    # WARN* and PHP005 always warn
    case "$rule_id" in
        WARN*|PHP005) echo "warn"; return 0 ;;
    esac

    case "$_RULES_STRICTNESS" in
        strict)
            echo "block"
            ;;
        moderate)
            case "$rule_id" in
                LAYER*) echo "block" ;;
                *)      echo "warn" ;;
            esac
            ;;
        relaxed)
            echo "warn"
            ;;
        *)
            echo "block"
            ;;
    esac
}

# ===========================================================================
# PUBLIC API
# ===========================================================================

# ---------------------------------------------------------------------------
# rules_init "$project_dir" ["$global_dir"]
# Load and merge config from global → project
# ---------------------------------------------------------------------------
_rules_load_config_file() {
    local project_dir="$1"
    local global_dir="${2:-}"

    if [[ -n "${CLAUDE_PLUGIN_OPTION_strictness:-}" ]]; then
        _RULES_STRICTNESS="$CLAUDE_PLUGIN_OPTION_strictness"
    fi

    if [[ -n "$global_dir" ]] && [[ -f "$global_dir/.craft-config.yml" ]]; then
        _rules_parse_config "$global_dir/.craft-config.yml" "global"
    fi

    if [[ -f "$project_dir/.craft-config.yml" ]]; then
        _rules_parse_config "$project_dir/.craft-config.yml" "project"
    fi
}

rules_init() {
    local project_dir="$1"
    local global_dir="${2:-}"

    _rules_ensure_store
    _RULES_PROJECT_DIR="$project_dir"
    _RULES_STRICTNESS="strict"

    _rules_load_config_file "$project_dir" "$global_dir"

    local rule_id
    for rule_id in $(_rules_keys "pattern"); do
        _rules_validate_custom "$rule_id"
    done

    for rule_id in $(_rules_keys "languages"); do
        if ! _rules_has "pattern" "$rule_id"; then
            _rules_validate_custom "$rule_id"
        fi
    done
}

# ---------------------------------------------------------------------------
# rules_severity "$rule_id"
# Returns block|warn|ignore for a rule (project-level, no directory override)
# ---------------------------------------------------------------------------
rules_severity() {
    local rule_id="$1"
    local sev
    sev=$(_rules_get "severity" "$rule_id")
    if [[ -n "$sev" ]]; then
        echo "$sev"
    else
        _rules_default_severity "$rule_id"
    fi
}

# ---------------------------------------------------------------------------
# rules_severity_for_file "$path" "$rule_id"
# Like rules_severity but with directory-level .craft-rules.yml override.
# Walks up from file's directory looking for .craft-rules.yml, stops at project root.
# ---------------------------------------------------------------------------
# Walk directories from file up to project root, looking for .craft-rules.yml override.
# Prints the overridden severity if found, prints nothing if no directory override exists.
_rules_check_directory_override() {
    local current_directory="$1"
    local directory_key="$2"
    local rule_id="$3"

    if [[ -f "$current_directory/.craft-rules.yml" ]]; then
        if ! _rules_has "dir_parsed" "$directory_key"; then
            _rules_parse_dir_config "$current_directory/.craft-rules.yml" "$directory_key"
            _rules_set "dir_parsed" "$directory_key" "1"
        fi
        local cached_severity
        cached_severity=$(_rules_get "dir_cache" "${directory_key}:${rule_id}")
        if [[ -n "$cached_severity" ]]; then
            echo "$cached_severity"
            return 0
        fi
    fi
    return 1
}

_rules_search_parent_dirs() {
    local current_directory="$1"
    local rule_id="$2"

    while [[ -n "$current_directory" ]]; do
        local directory_key
        directory_key=$(echo "$current_directory" | sed 's|/|__|g')

        local cached_severity
        cached_severity=$(_rules_get "dir_cache" "${directory_key}:${rule_id}")
        if [[ -n "$cached_severity" ]]; then
            echo "$cached_severity"
            return 0
        fi

        cached_severity=$(_rules_check_directory_override "$current_directory" "$directory_key" "$rule_id") && {
            echo "$cached_severity"
            return 0
        }

        [[ "$current_directory" == "$_RULES_PROJECT_DIR" || "$current_directory" == "/" ]] && break
        current_directory=$(dirname "$current_directory")
    done
    return 1
}

_rules_find_directory_override() {
    local file_path="$1"
    local rule_id="$2"

    local current_directory
    current_directory=$(dirname "$file_path")

    _rules_search_parent_dirs "$current_directory" "$rule_id"
}

# Find the nearest directory containing .craft-rules.yml for a file path.
# Prints the directory path, or nothing if no override directory exists.
_rules_find_override_directory() {
    local file_path="$1"
    local current_directory
    current_directory=$(dirname "$file_path")

    while [[ -n "$current_directory" ]]; do
        [[ -f "$current_directory/.craft-rules.yml" ]] && { echo "$current_directory"; return 0; }
        [[ "$current_directory" == "$_RULES_PROJECT_DIR" || "$current_directory" == "/" ]] && break
        current_directory=$(dirname "$current_directory")
    done
    return 1
}

rules_severity_for_file() {
    local file_path="$1"
    local rule_id="$2"

    local directory_severity
    directory_severity=$(_rules_find_directory_override "$file_path" "$rule_id") && {
        echo "$directory_severity"
        return 0
    }

    rules_severity "$rule_id"
}

# ---------------------------------------------------------------------------
# rules_custom_list "$language"
# Returns list of custom rule IDs for a given language (one per line)
# ---------------------------------------------------------------------------
rules_custom_list() {
    local language="$1"
    local rule_id

    for rule_id in $(_rules_keys "languages"); do
        local langs
        langs=$(_rules_get "languages" "$rule_id")
        # Check if language is in comma-separated list
        local lang
        local IFS=','
        for lang in $langs; do
            if [[ "$lang" == "$language" ]]; then
                # Only include if severity is not ignore
                local sev
                sev=$(rules_severity "$rule_id")
                if [[ "$sev" != "ignore" ]]; then
                    echo "$rule_id"
                fi
                break
            fi
        done
        unset IFS
    done
}

# ---------------------------------------------------------------------------
# rules_pattern "$rule_id"
# Returns regex pattern for a custom rule
# ---------------------------------------------------------------------------
rules_pattern() {
    local rule_id="$1"
    _rules_get "pattern" "$rule_id"
}

# ---------------------------------------------------------------------------
# rules_message "$rule_id"
# Returns human-readable message for a custom rule
# ---------------------------------------------------------------------------
rules_message() {
    local rule_id="$1"
    _rules_get "message" "$rule_id"
}

# ---------------------------------------------------------------------------
# rules_explain "$rule_id" ["$file_path"]
# Shows where the rule's current severity comes from (traceability).
# Output: "RULE_ID: severity (source: description)"
# ---------------------------------------------------------------------------
rules_explain() {
    local rule_id="$1"
    local file_path="${2:-}"

    # Check directory overrides first (if file path provided)
    if [[ -n "$file_path" ]]; then
        local directory_severity
        directory_severity=$(_rules_find_directory_override "$file_path" "$rule_id") && {
            local override_directory
            override_directory=$(_rules_find_override_directory "$file_path")
            echo "$rule_id: $directory_severity (source: directory override ${override_directory}/.craft-rules.yml)"
            return 0
        }
    fi

    # Check project-level explicit config
    local configured_severity
    configured_severity=$(_rules_get "severity" "$rule_id")
    if [[ -n "$configured_severity" ]]; then
        local config_source="global ~/.claude/.craft-config.yml"
        [[ -f "$_RULES_PROJECT_DIR/.craft-config.yml" ]] && config_source="project $_RULES_PROJECT_DIR/.craft-config.yml"
        echo "$rule_id: $configured_severity (source: $config_source)"
        return 0
    fi

    # Default severity from strictness
    local default_severity
    default_severity=$(_rules_default_severity "$rule_id")
    echo "$rule_id: $default_severity (source: default strictness '$_RULES_STRICTNESS')"
}
