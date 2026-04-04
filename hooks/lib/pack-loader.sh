#!/usr/bin/env bash
# =============================================================================
# Pack Loader — Discovers, validates, and loads packs based on stack config.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/pack-loader.sh"
#   pack_loader_init [packs_dir]
#   pack_run_validators "/path/to/file.php" "php"
#   pack_run_static_analysis "/path/to/file.php" "php"
#   pack_list_scaffold_types
#   pack_loaded
# =============================================================================

_LOADED_PACKS=""
_PACK_VALIDATORS=""
_PACK_SA_TOOLS=""
_PACK_SCAFFOLD_TYPES=""
_PACKS_DIR=""

_pack_reset() {
    _LOADED_PACKS=""
    _PACK_VALIDATORS=""
    _PACK_SA_TOOLS=""
    _PACK_SCAFFOLD_TYPES=""
    _PACKS_DIR=""
}

# Extract a top-level scalar value from a simple YAML file.
# e.g. _pack_yml_value "name" pack.yml  →  symfony
_pack_yml_value() {
    local key="$1" file="$2"
    grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1 \
        | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '"' | tr -d "'" \
        | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//'
}

# Extract an inline YAML array value from a top-level key.
# e.g.  stack: ["symfony", "fullstack"]  →  symfony (line 1)  fullstack (line 2)
_pack_yml_array() {
    local key="$1" file="$2"
    local line
    line=$(grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return
    echo "$line" \
        | sed -E 's/^[^[]*\[//' \
        | sed -E 's/\].*//' \
        | tr ',' '\n' \
        | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' \
        | grep -v '^$'
}

# Extract an inline YAML array nested under a parent key.
# e.g.  compatibility:\n  stack: ["symfony"]  →  symfony
_pack_yml_nested_array() {
    local parent="$1" child="$2" file="$3"
    local in_parent=false
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^${parent}:"; then
            in_parent=true
            continue
        fi
        if [[ "$in_parent" == true ]]; then
            # A non-indented key signals we have left the parent block
            if echo "$line" | grep -qE '^[a-zA-Z]'; then
                in_parent=false
                continue
            fi
            if echo "$line" | grep -qE "^[[:space:]]+${child}:"; then
                echo "$line" \
                    | sed -E 's/^[^[]*\[//' \
                    | sed -E 's/\].*//' \
                    | tr ',' '\n' \
                    | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' \
                    | grep -v '^$'
                return
            fi
        fi
    done < "$file"
}

# Return 0 if the pack at pack_dir is compatible with the current stack.
_pack_stack_compatible() {
    local pack_dir="$1"
    local manifest="$pack_dir/pack.yml"
    local current_stack
    current_stack=$(config_stack 2>/dev/null || echo "fullstack")

    local compat_stacks
    compat_stacks=$(_pack_yml_nested_array "compatibility" "stack" "$manifest")
    [[ -z "$compat_stacks" ]] && return 1

    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        [[ "$s" == "*" ]] && return 0
        [[ "$s" == "$current_stack" ]] && return 0
    done <<< "$compat_stacks"

    return 1
}

_register_pack_validators() {
    local pack_dir="$1"
    local validators
    validators=$(_pack_yml_nested_array "hooks" "validators" "$pack_dir/pack.yml")
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        local vpath="$pack_dir/$v"
        if [[ -f "$vpath" ]]; then
            # shellcheck disable=SC1090
            source "$vpath"
            _PACK_VALIDATORS="${_PACK_VALIDATORS}${vpath}\n"
        fi
    done <<< "$validators"
}

_register_pack_sa_tools() {
    local pack_dir="$1"
    local sa_tools
    sa_tools=$(_pack_yml_nested_array "static_analysis" "tools" "$pack_dir/pack.yml")
    while IFS= read -r tool_entry; do
        [[ -z "$tool_entry" ]] && continue
        local tpath="$pack_dir/$tool_entry"
        if [[ -f "$tpath" ]]; then
            # shellcheck disable=SC1090
            source "$tpath"
            _PACK_SA_TOOLS="${_PACK_SA_TOOLS}${tpath}\n"
        fi
    done <<< "$sa_tools"
}

_register_pack_scaffolds() {
    local pack_dir="$1"
    local pack_name="$2"
    local scaffold_types
    scaffold_types=$(_pack_yml_nested_array "commands" "scaffold_types" "$pack_dir/pack.yml")
    while IFS= read -r scaffold_type; do
        [[ -z "$scaffold_type" ]] && continue
        _PACK_SCAFFOLD_TYPES="${_PACK_SCAFFOLD_TYPES}${pack_name}:${scaffold_type}\n"
    done <<< "$scaffold_types"
}

_register_pack_components() {
    local pack_dir="$1"
    local pack_name="$2"
    _register_pack_validators "$pack_dir"
    _register_pack_sa_tools "$pack_dir"
    _register_pack_scaffolds "$pack_dir" "$pack_name"
}

_load_pack() {
    local pack_dir="$1"
    local pack_name
    pack_name=$(_pack_yml_value "name" "$pack_dir/pack.yml")
    [[ -z "$pack_name" ]] && return

    _register_pack_components "$pack_dir" "$pack_name"

    _LOADED_PACKS="${_LOADED_PACKS}${pack_name}\n"
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Scan packs_dir, filter by stack compatibility, source validators.
pack_loader_init() {
    local packs_dir="${1:-${CLAUDE_PLUGIN_ROOT:-}/packs}"
    _PACKS_DIR="$packs_dir"

    # 1. Load internal packs
    if [[ -d "$packs_dir" ]]; then
        for pack_dir in "$packs_dir"/*/; do
            [[ ! -f "$pack_dir/pack.yml" ]] && continue
            if _pack_stack_compatible "$pack_dir"; then
                _load_pack "$pack_dir"
            fi
        done
    fi

    # 2. Load external packs from .craft-config.yml
    if type config_external_packs &>/dev/null; then
        local ext_path
        while IFS= read -r ext_path; do
            [[ -z "$ext_path" ]] && continue
            [[ ! -d "$ext_path" ]] && continue
            [[ ! -f "$ext_path/pack.yml" ]] && continue
            if _pack_stack_compatible "$ext_path"; then
                _load_pack "$ext_path"
            fi
        done <<< "$(config_external_packs)"
    fi
}

# Invoke pack_validate_<lang>() if it was sourced from a loaded pack.
pack_run_validators() {
    local file="$1"
    local lang="$2"
    local func="pack_validate_${lang}"
    if type "$func" &>/dev/null 2>&1; then
        "$func" "$file"
    fi
}

# Invoke pack_sa_<lang>() if it was sourced from a loaded pack.
pack_run_static_analysis() {
    local file="$1"
    local lang="$2"
    local func="pack_sa_${lang}"
    if type "$func" &>/dev/null 2>&1; then
        "$func" "$file"
    fi
}

# Return all scaffold types from loaded packs, one per line (format: pack:type).
pack_list_scaffold_types() {
    printf '%b' "$_PACK_SCAFFOLD_TYPES" | grep -v '^$'
}

# Return loaded pack names, one per line.
pack_loaded() {
    printf '%b' "$_LOADED_PACKS" | grep -v '^$'
}

_sync_symlink_type() {
    local pack_dir="$1"
    local type_dir="$2"
    local target_dir="$3"
    [[ ! -d "$pack_dir/$type_dir" ]] && return
    for src_file in "$pack_dir/$type_dir/"*.md; do
        [[ ! -f "$src_file" ]] && continue
        local basename
        basename=$(basename "$src_file")
        ln -sf "$src_file" "$target_dir/$basename"
    done
}

pack_sync_symlinks() {
    local root="${CLAUDE_PLUGIN_ROOT:-$(pwd)}"
    local packs_dir="${_PACKS_DIR:-$root/packs}"

    for f in "$root/agents/"*.md; do
        [[ -L "$f" ]] && rm -- "$f"
    done
    for f in "$root/commands/"*.md; do
        [[ -L "$f" ]] && rm -- "$f"
    done

    local pack_name
    while IFS= read -r pack_name; do
        [[ -z "$pack_name" ]] && continue
        local pack_dir="$packs_dir/$pack_name"
        _sync_symlink_type "$pack_dir" "agents" "$root/agents"
        _sync_symlink_type "$pack_dir" "commands" "$root/commands"
    done <<< "$(pack_loaded)"
}
