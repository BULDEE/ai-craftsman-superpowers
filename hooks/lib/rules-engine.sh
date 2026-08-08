#!/usr/bin/env bash
# =============================================================================
# Rules Engine - 3-level config inheritance with custom rules
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
# Directory override (.craft-rules.yml - rules section only):
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

# A rule's default severity belongs to whoever owns the rule, so severity
# resolution needs the rule registry whether or not the caller loaded the packs.
# shellcheck source=./rule-registry.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rule-registry.sh"

_rules_store_dir() {
    local namespace="$1"
    echo "$_RULES_STORE/$namespace"
}

# Rule ids reach this as filenames, and they come from YAML keys in a
# repository-controlled config. A key containing a path separator would write
# outside the store; keys are therefore structurally constrained here as well
# as validated at the point of entry (defense in depth: this also covers
# callers added later).
# A rule id becomes a filename and a store key. It comes from a YAML key in a
# repository-controlled config, so it is constrained to an identifier charset
# before it reaches any sink.
_rules_id_is_safe() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

_rules_key_is_safe() {
    local key="$1"
    [[ -n "$key" ]] || return 1
    [[ "$key" != */* ]] || return 1
    [[ "$key" != *..* ]] || return 1
    return 0
}

_rules_set() {
    local namespace="$1" key="$2" value="$3"
    _rules_key_is_safe "$key" || {
        echo "[rules-engine] rejected unsafe rule key: ${key}" >&2
        return 0
    }
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
        _rules_id_is_safe "$rule_id" || continue
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
    # A parser failure is not an empty config. Built-in rules fall back to
    # strict, but every custom rule declared in .craft-config.yml simply
    # ceased to exist, silently, and CI suppressed the stderr that would have
    # said so. Announce it: a rule the team wrote and that never fires is
    # worse than no rule, because they believe it is running.
    json_output=$(python3 "$parser_path" "$file" "config") || {
        echo "craftsman: could not parse $file, its custom rules will not be enforced" >&2
        json_output="{}"
    }

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
    json_output=$(python3 "$parser_path" "$file" "rules") || {
        echo "craftsman: could not parse rules from $file, they will not be enforced" >&2
        json_output="{}"
    }

    if [[ -z "$json_output" ]] || [[ "$json_output" == "{}" ]]; then
        return 0
    fi

    local rule_ids
    rule_ids=$(printf '%s' "$json_output" | jq -r '.rules // {} | keys[]' 2>/dev/null)

    _rules_cache_dir_rules "$json_output" "$dir_key" "$rule_ids"
}

_rules_cache_dir_rules() {
    local json_output="$1" dir_key="$2" rule_ids="$3"
    local rule_id rule_val
    for rule_id in $rule_ids; do
        _rules_id_is_safe "$rule_id" || continue
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
    # -e is required: the pattern comes from the audited repository's own
    # .craft-config.yml, and without it a leading dash is parsed as an option.
    # `--file=/dev/zero` hangs the hook on every Write/Edit; `--file=/etc/passwd`
    # makes grep read an arbitrary local file as its pattern source.
    echo "test" | grep -E -e "$pattern" >/dev/null 2>&1 || grep_ret=$?
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
# Rules that always warn regardless of strictness.
# WARN*/PHP005 are advisory by nature. The structural rules
# (NEST001/LOC001/GOD001/PARAM001/CTRL001) ship advisory-first so teams can
# measure real noise on an existing codebase before escalating. LOC001 stays
# advisory permanently; drop NEST001/GOD001/PARAM001/CTRL001 from this list to
# let strict-mode block them once the codebase is clean.
_rules_is_advisory() {
    case "$1" in
        WARN*|PHP005|NEST001|LOC001|GOD001|PARAM001|CTRL001) return 0 ;;
        # TS002/TS003/PHP003 are design preferences with legitimate exceptions
        # a regex cannot see: a framework contract that hands you a mutable
        # DTO, a third-party type whose nullability is wrong, a barrel a build
        # tool insists on. Blocking a write on those trains the developer to
        # suppress the rule, and a rule that is always suppressed enforces
        # nothing while still costing a round trip. Set them to `block` in
        # .craft-config.yml where the codebase has no such exceptions.
        TS002|TS003|PHP003) return 0 ;;
        # RATCHET001 ships advisory while the metric core is validated against
        # real work (ADR-0025). Set `RATCHET001: block` in .craft-config.yml to
        # opt in early; the default escalates once a full cycle runs clean.
        RATCHET001) return 0 ;;
        # These were advisory de facto, by being emitted through add_warning
        # instead of add_violation. That made the choice invisible here and,
        # worse, unreachable: add_warning never consulted this engine, so a
        # project could neither promote them to block nor set them to ignore.
        # Declaring them advisory keeps today's behaviour and hands the
        # decision back to .craft-config.yml and .craft-rules.yml.
        DB001|DB002|DB003|PY003|SH001|SH003|SH005) return 0 ;;
    esac
    return 1
}

# What a rule defaults to when no configuration names it.
#
# The owning pack states the intent (rules/core.yml or its own manifest), and
# strictness then applies on top: `relaxed` still relaxes everything, `moderate`
# still keeps only boundary rules blocking. Returning the declared value
# directly made a project's `strictness: relaxed` a no-op, which is a setting
# silently ignored rather than a visible failure.
_rules_declared_severity() {
    local rule_id="$1" declared=""
    if type rule_default_severity &>/dev/null 2>&1; then
        declared=$(rule_default_severity "$rule_id" 2>/dev/null)
    fi
    if [[ -z "$declared" ]]; then
        # No declaration: a rule a validator emits without owning it, or a
        # caller that never loaded the packs.
        _rules_is_advisory "$rule_id" && declared="warn" || declared="block"
    fi
    printf '%s' "$declared"
}

_rules_default_severity() {
    local rule_id="$1" declared
    declared=$(_rules_declared_severity "$rule_id")
    [[ "$declared" == "ignore" ]] && { echo "ignore"; return 0; }
    [[ "$declared" == "warn" ]] && { echo "warn"; return 0; }

    case "$_RULES_STRICTNESS" in
        relaxed)  echo "warn" ;;
        moderate) case "$rule_id" in LAYER*) echo "$declared" ;; *) echo "warn" ;; esac ;;
        *)        echo "$declared" ;;
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

# The severity this one directory declares for the rule, cache first.
_rules_severity_in_dir() {
    local directory="$1" rule_id="$2"
    local directory_key cached
    directory_key=$(echo "$directory" | sed 's|/|__|g')

    cached=$(_rules_get "dir_cache" "${directory_key}:${rule_id}")
    if [[ -n "$cached" ]]; then
        echo "$cached"
        return 0
    fi

    _rules_check_directory_override "$directory" "$directory_key" "$rule_id"
}

# The next directory up, or nothing when the walk is over. The project root and
# "/" are absolute, so a relative path reaches neither: dirname of "." is "."
# and the walk spins forever. Whoever calls this decides the path shape, so
# termination cannot depend on them getting it right.
_rules_next_dir_up() {
    local directory="$1"
    [[ "$directory" == "$_RULES_PROJECT_DIR" || "$directory" == "/" ]] && return 1

    local parent
    parent=$(dirname "$directory")
    [[ "$parent" == "$directory" ]] && return 1
    printf '%s' "$parent"
}

_rules_search_parent_dirs() {
    local current_directory="$1"
    local rule_id="$2"

    while [[ -n "$current_directory" ]]; do
        local severity
        severity=$(_rules_severity_in_dir "$current_directory" "$rule_id") && {
            echo "$severity"
            return 0
        }
        current_directory=$(_rules_next_dir_up "$current_directory") || break
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

        local parent
        parent=$(dirname "$current_directory")
        # The two stops above are absolute, so a relative path never reaches
        # either: dirname of "." is "." and the walk spins forever. Whoever
        # calls this decides the path shape, so termination cannot depend on
        # them getting it right. Stop as soon as dirname stops moving.
        [[ "$parent" == "$current_directory" ]] && break
        current_directory="$parent"
    done
    return 1
}

# Paths where the structural premise does not hold. A long setup method, a
# fixture builder taking six arguments, a deeply nested data literal: those are
# the normal shape of a test, not decay. A credential in a fixture is a
# fixture, not a leak. Blocking on them is what teaches a developer to reach
# for craftsman-ignore, and that habit then covers the real findings too.
#
# Degraded to warn, never dropped: the finding stays visible, it just stops
# standing between the developer and their own test file. An explicit
# directory override in .craft-rules.yml still wins over this, since a project
# that means it should be able to say so.
_RULES_TEST_PATH_RE='(^|/)(tests?|spec|__tests__|__mocks__|fixtures?|factories)(/|$)'
_RULES_TEST_RELAXED='LOC001 NEST001 PARAM001 GOD001 CTRL001 SEC001 SEC002'

# Case-insensitive: the case of a directory name is not semantic, and the
# regex missed the PSR-4 convention this plugin's own primary stack uses.
# `Tests/Unit/FooTest.php` resolved SEC001 to block while `tests/` resolved it
# to warn, so the relaxation written to stop blocking on fixture credentials
# missed the most common PHP layout. nocasematch is saved and restored rather
# than set globally: it is shell-wide state and the hook shares its shell with
# every other validator.
_rules_is_test_path() {
    # Restored by branching rather than by eval'ing `shopt -p`: the idiomatic
    # save/restore is data-as-code, and SH004 is right to refuse it even when
    # the string comes from the shell itself.
    if shopt -q nocasematch; then
        [[ "$1" =~ $_RULES_TEST_PATH_RE ]]
        return $?
    fi
    local matched
    shopt -s nocasematch
    [[ "$1" =~ $_RULES_TEST_PATH_RE ]]
    matched=$?
    shopt -u nocasematch
    return $matched
}

_rules_relaxed_in_tests() {
    case " $_RULES_TEST_RELAXED " in
        *" $1 "*) return 0 ;;
    esac
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

    local severity
    severity=$(rules_severity "$rule_id")
    if [[ "$severity" == "block" ]] \
        && _rules_is_test_path "$file_path" \
        && _rules_relaxed_in_tests "$rule_id"; then
        echo "warn"
        return 0
    fi
    echo "$severity"
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
_explain_directory_override() {
    local rule_id="$1" file_path="$2"
    [[ -n "$file_path" ]] || return 1
    local directory_severity override_directory
    directory_severity=$(_rules_find_directory_override "$file_path" "$rule_id") || return 1
    override_directory=$(_rules_find_override_directory "$file_path")
    echo "$rule_id: $directory_severity (source: directory override ${override_directory}/.craft-rules.yml)"
}

_explain_configured() {
    local rule_id="$1" configured_severity config_source
    configured_severity=$(_rules_get "severity" "$rule_id")
    [[ -n "$configured_severity" ]] || return 1
    config_source="global ~/.claude/.craft-config.yml"
    [[ -f "$_RULES_PROJECT_DIR/.craft-config.yml" ]] && config_source="project $_RULES_PROJECT_DIR/.craft-config.yml"
    echo "$rule_id: $configured_severity (source: $config_source)"
}

rules_explain() {
    local rule_id="$1"
    local file_path="${2:-}"

    _explain_directory_override "$rule_id" "$file_path" && return 0
    _explain_configured "$rule_id" && return 0

    # An advisory rule warns whatever the strictness is, so naming the
    # strictness as the source would send the reader to change a setting that
    # has no effect on it.
    if _rules_is_advisory "$rule_id"; then
        echo "$rule_id: warn (source: advisory by default, set '$rule_id: block' to enforce)"
        return 0
    fi

    echo "$rule_id: $(_rules_default_severity "$rule_id") (source: default strictness '$_RULES_STRICTNESS')"
}
