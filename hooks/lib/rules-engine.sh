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
    local ns="$1"
    echo "$_RULES_STORE/$ns"
}

_rules_set() {
    local ns="$1" key="$2" value="$3"
    local dir
    dir="$(_rules_store_dir "$ns")"
    mkdir -p "$dir"
    printf '%s' "$value" > "$dir/$key"
}

_rules_get() {
    local ns="$1" key="$2"
    local file
    file="$(_rules_store_dir "$ns")/$key"
    if [[ -f "$file" ]]; then
        cat "$file"
    fi
}

_rules_keys() {
    local ns="$1"
    local dir
    dir="$(_rules_store_dir "$ns")"
    if [[ -d "$dir" ]]; then
        ls "$dir" 2>/dev/null
    fi
}

_rules_has() {
    local ns="$1" key="$2"
    [[ -f "$(_rules_store_dir "$ns")/$key" ]]
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
_rules_parse_config() {
    local file="$1"
    local source_label="$2"  # "global" or "project"

    [[ ! -f "$file" ]] && return 0

    local parser_path
    parser_path="$(_rules_yaml_parser_path)"
    local json_output
    json_output=$(python3 "$parser_path" "$file" "config") || json_output="{}"

    # Empty or invalid → skip
    if [[ -z "$json_output" ]] || [[ "$json_output" == "{}" ]]; then
        return 0
    fi

    # Parse strictness
    local val
    val=$(printf '%s' "$json_output" | jq -r '.strictness // empty' 2>/dev/null)
    if [[ -n "$val" ]]; then
        if [[ "$source_label" == "project" ]] || [[ -z "$_RULES_STRICTNESS" ]] || [[ "$_RULES_STRICTNESS" == "strict" && "$source_label" == "global" ]]; then
            _RULES_STRICTNESS="$val"
        fi
    fi

    # Parse rules
    local rule_ids
    rule_ids=$(printf '%s' "$json_output" | jq -r '.rules // {} | keys[]' 2>/dev/null)

    local rule_id
    for rule_id in $rule_ids; do
        # Check if short form (severity only) or long form (custom rule)
        local rule_json
        rule_json=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"]" 2>/dev/null)

        local sev
        sev=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].severity // empty" 2>/dev/null)
        if [[ -n "$sev" ]]; then
            _rules_set "severity" "$rule_id" "$sev"
        fi

        local pat
        pat=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].pattern // empty" 2>/dev/null)
        if [[ -n "$pat" ]]; then
            _rules_set "pattern" "$rule_id" "$pat"
        fi

        local msg
        msg=$(printf '%s' "$json_output" | jq -r ".rules[\"$rule_id\"].message // empty" 2>/dev/null)
        if [[ -n "$msg" ]]; then
            _rules_set "message" "$rule_id" "$msg"
        fi

        local langs
        langs=$(printf '%s' "$json_output" | jq -r '.rules["'"$rule_id"'"].languages // empty | if type == "array" then join(",") else empty end' 2>/dev/null)
        if [[ -n "$langs" ]]; then
            _rules_set "languages" "$rule_id" "$langs"
        else
            # Check for empty array explicitly
            local langs_type
            langs_type=$(printf '%s' "$json_output" | jq -r '.rules["'"$rule_id"'"].languages | type' 2>/dev/null)
            if [[ "$langs_type" == "array" ]]; then
                _rules_set "languages" "$rule_id" ""
            fi
        fi
    done
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
_rules_validate_custom() {
    local rule_id="$1"
    local valid=1

    # Must have a pattern
    local pattern
    pattern=$(_rules_get "pattern" "$rule_id")
    if [[ -z "$pattern" ]]; then
        valid=0
        echo "[rules-engine] WARNING: Rule $rule_id has no pattern, setting to ignore" >&2
    else
        # Validate regex: grep -E returns 2 for invalid regex
        local grep_ret=0
        echo "test" | grep -E "$pattern" >/dev/null 2>&1 || grep_ret=$?
        if [[ $grep_ret -eq 2 ]]; then
            valid=0
            echo "[rules-engine] WARNING: Rule $rule_id has invalid regex pattern '$pattern', setting to ignore" >&2
        fi
    fi

    # Severity must be block|warn|ignore
    local severity
    severity=$(_rules_get "severity" "$rule_id")
    if [[ -n "$severity" ]] && [[ ! "$severity" =~ ^(block|warn|ignore)$ ]]; then
        valid=0
        echo "[rules-engine] WARNING: Rule $rule_id has invalid severity '$severity', setting to ignore" >&2
    fi

    # Languages must be non-empty
    local languages
    languages=$(_rules_get "languages" "$rule_id")
    if [[ -z "$languages" ]]; then
        valid=0
        echo "[rules-engine] WARNING: Rule $rule_id has no languages, setting to ignore" >&2
    fi

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
rules_init() {
    local project_dir="$1"
    local global_dir="${2:-}"

    _rules_ensure_store
    _RULES_PROJECT_DIR="$project_dir"
    _RULES_STRICTNESS="strict"  # default

    # 0. Check CLAUDE_PLUGIN_OPTION_strictness env var (lower priority than config files)
    if [[ -n "${CLAUDE_PLUGIN_OPTION_strictness:-}" ]]; then
        _RULES_STRICTNESS="$CLAUDE_PLUGIN_OPTION_strictness"
    fi

    # 1. Load global config if exists (overrides env var)
    if [[ -n "$global_dir" ]] && [[ -f "$global_dir/.craft-config.yml" ]]; then
        _rules_parse_config "$global_dir/.craft-config.yml" "global"
    fi

    # 2. Load project config, deep merge over global (highest priority)
    if [[ -f "$project_dir/.craft-config.yml" ]]; then
        _rules_parse_config "$project_dir/.craft-config.yml" "project"
    fi

    # 3. Validate custom rules (those with a pattern or languages key)
    local rule_id
    for rule_id in $(_rules_keys "pattern"); do
        _rules_validate_custom "$rule_id"
    done

    # Also validate rules that have languages but no pattern yet checked
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
rules_severity_for_file() {
    local file_path="$1"
    local rule_id="$2"

    local dir
    dir=$(dirname "$file_path")

    # Walk up from file dir to project root looking for .craft-rules.yml
    while [[ -n "$dir" ]]; do
        # Sanitize dir for cache key (replace / with __)
        local dir_key
        dir_key=$(echo "$dir" | sed 's|/|__|g')

        # Check cache first
        local cached
        cached=$(_rules_get "dir_cache" "${dir_key}:${rule_id}")
        if [[ -n "$cached" ]]; then
            echo "$cached"
            return 0
        fi

        # Parse .craft-rules.yml if it exists and hasn't been parsed
        if [[ -f "$dir/.craft-rules.yml" ]]; then
            # Check if we've already parsed this directory
            if ! _rules_has "dir_parsed" "$dir_key"; then
                _rules_parse_dir_config "$dir/.craft-rules.yml" "$dir_key"
                _rules_set "dir_parsed" "$dir_key" "1"
            fi

            # Check again after parsing
            cached=$(_rules_get "dir_cache" "${dir_key}:${rule_id}")
            if [[ -n "$cached" ]]; then
                echo "$cached"
                return 0
            fi
        fi

        # Stop at project root
        if [[ "$dir" == "$_RULES_PROJECT_DIR" ]] || [[ "$dir" == "/" ]]; then
            break
        fi

        # Go up one level
        dir=$(dirname "$dir")
    done

    # Fall back to project-level severity
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

    # If file_path provided, check directory overrides first
    if [[ -n "$file_path" ]]; then
        local dir
        dir=$(dirname "$file_path")

        while [[ -n "$dir" ]]; do
            local dir_key
            dir_key=$(echo "$dir" | sed 's|/|__|g')

            # Parse if needed
            if [[ -f "$dir/.craft-rules.yml" ]]; then
                if ! _rules_has "dir_parsed" "$dir_key"; then
                    _rules_parse_dir_config "$dir/.craft-rules.yml" "$dir_key"
                    _rules_set "dir_parsed" "$dir_key" "1"
                fi

                local cached
                cached=$(_rules_get "dir_cache" "${dir_key}:${rule_id}")
                if [[ -n "$cached" ]]; then
                    echo "$rule_id: $cached (source: directory override $dir/.craft-rules.yml)"
                    return 0
                fi
            fi

            if [[ "$dir" == "$_RULES_PROJECT_DIR" ]] || [[ "$dir" == "/" ]]; then
                break
            fi
            dir=$(dirname "$dir")
        done
    fi

    # Check project-level explicit config
    local sev
    sev=$(_rules_get "severity" "$rule_id")
    if [[ -n "$sev" ]]; then
        # Determine if from project or global
        if [[ -f "$_RULES_PROJECT_DIR/.craft-config.yml" ]]; then
            echo "$rule_id: $sev (source: project $_RULES_PROJECT_DIR/.craft-config.yml)"
        else
            echo "$rule_id: $sev (source: global ~/.claude/.craft-config.yml)"
        fi
        return 0
    fi

    # Default severity from strictness
    local default_sev
    default_sev=$(_rules_default_severity "$rule_id")
    echo "$rule_id: $default_sev (source: default strictness '$_RULES_STRICTNESS')"
}
