#!/usr/bin/env bash
# =============================================================================
# Pack Loader - Discovers, validates, and loads packs based on stack config.
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
_PACK_MANIFESTS=""
_PACK_MANIFESTS_ALL=""

# The registry turns the manifests this loader accepted into the engine's only
# source of truth about languages. Sourced here so every caller of
# pack_loader_init gets lang_for_file and pack_dispatch_file for free.
# shellcheck source=./lang-registry.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lang-registry.sh"
# shellcheck source=./rule-registry.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rule-registry.sh"

_pack_reset() {
    _LOADED_PACKS=""
    _PACK_VALIDATORS=""
    _PACK_SA_TOOLS=""
    _PACK_SCAFFOLD_TYPES=""
    _PACKS_DIR=""
    _PACK_MANIFESTS=""
    _PACK_MANIFESTS_ALL=""
    lang_registry_init
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
# One awk pass, not two forks per line.
#
# This read the manifest line by line and ran `echo "$line" | grep` up to three
# times per line. pack_loader_init calls it once per capability per pack, so a
# five-pack install spent thousands of forks parsing a few hundred lines of
# YAML: 2.9s per load, and craftsman-ci pays it twice. Declaring `languages:`
# lengthened the manifests by roughly 40 percent and made it visible by timing
# the CI suite out at 300s.
_pack_yml_nested_array() {
    local parent="$1" child="$2" file="$3"
    awk -v parent="$parent" -v child="$child" '
        index($0, parent ":") == 1 { inside = 1; next }
        inside && /^[a-zA-Z]/ { inside = 0 }
        inside && $0 ~ ("^[[:space:]]+" child ":") {
            line = $0
            sub(/^[^[]*\[/, "", line)
            sub(/\].*$/, "", line)
            count = split(line, items, ",")
            for (index_ = 1; index_ <= count; index_++) {
                value = items[index_]
                gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", value)
                gsub(/^'"'"'|'"'"'$/, "", value)
                if (value != "") print value
            }
            exit
        }
    ' "$file" 2>/dev/null
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
    _PACK_MANIFESTS="${_PACK_MANIFESTS}${pack_dir}/pack.yml\n"
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

_pack_load_internal() {
    local packs_dir="$1"
    [[ ! -d "$packs_dir" ]] && return 0
    local pack_dir
    for pack_dir in "$packs_dir"/*/; do
        [[ ! -f "$pack_dir/pack.yml" ]] && continue
        _PACK_MANIFESTS_ALL="${_PACK_MANIFESTS_ALL}${pack_dir}/pack.yml\n"
        if _pack_stack_compatible "$pack_dir"; then
            _load_pack "$pack_dir"
        fi
    done
    # An incompatible last pack would otherwise leave the loop's status at 1,
    # which trips the fail-open `trap ERR` in pre-write-check.sh and silently
    # turns the whole hook into a no-op.
    return 0
}

_pack_load_external() {
    type config_external_packs &>/dev/null || return 0
    local ext_path
    while IFS= read -r ext_path; do
        [[ -z "$ext_path" ]] && continue
        [[ ! -d "$ext_path" ]] && continue
        [[ ! -f "$ext_path/pack.yml" ]] && continue
        _PACK_MANIFESTS_ALL="${_PACK_MANIFESTS_ALL}${ext_path}/pack.yml\n"
        if _pack_stack_compatible "$ext_path"; then
            _load_pack "$ext_path"
        fi
    done <<< "$(config_external_packs)"
    return 0
}

# Scan packs_dir, filter by stack compatibility, source validators, then build
# the language registry from exactly the manifests that passed the filter. A
# language is enabled because a compatible pack declared it, never because the
# engine has heard of it.
# CLAUDE_PLUGIN_ROOT is set by the harness and absent everywhere else: a test
# harness, a CI shell, a developer running a hook by hand. It used to be a soft
# dependency, because the extension list was a literal and dispatch worked
# without any pack loaded. Now an unresolved packs directory means an empty
# registry, which means every hook silently validates nothing. Derive the
# location from this file instead, and keep the env var as the override.
_pack_default_packs_dir() {
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}/packs" ]]; then
        printf '%s' "${CLAUDE_PLUGIN_ROOT}/packs"
        return 0
    fi
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/packs"
}

pack_loader_init() {
    local packs_dir="${1:-$(_pack_default_packs_dir)}"
    _PACKS_DIR="$packs_dir"

    _pack_load_internal "$packs_dir"
    _pack_load_external
    _pack_build_registry
    return 0
}

_pack_manifest_list() {
    local raw="$1"
    local manifest
    while IFS= read -r manifest; do
        [[ -z "$manifest" ]] && continue
        [[ -f "$manifest" ]] && printf '%s\n' "$manifest"
    done <<< "$(printf '%b' "$raw")"
}

_pack_build_registry() {
    local manifests=()
    local manifest
    while IFS= read -r manifest; do
        [[ -n "$manifest" ]] && manifests+=("$manifest")
    done <<< "$(_pack_manifest_list "$_PACK_MANIFESTS")"
    if [[ ${#manifests[@]} -eq 0 ]]; then
        lang_registry_init
    else
        lang_registry_init "${manifests[@]}"
    fi

    local known=()
    while IFS= read -r manifest; do
        [[ -n "$manifest" ]] && known+=("$manifest")
    done <<< "$(_pack_manifest_list "$_PACK_MANIFESTS_ALL")"
    if [[ ${#known[@]} -eq 0 ]]; then
        lang_registry_init_known
    else
        lang_registry_init_known "${known[@]}"
    fi

    _pack_build_rule_registry "${manifests[@]:-}"
}

# Doctrine follows the same rule as dispatch: only packs the stack admits
# contribute. rules/core.yml is always in, because layer, security and
# structural rules belong to no pack and a React-only project still needs them.
_pack_build_rule_registry() {
    local core_rules
    core_rules="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/rules/core.yml"
    local sources=()
    [[ -f "$core_rules" ]] && sources+=("$core_rules")
    local manifest
    for manifest in "$@"; do
        [[ -n "$manifest" && -f "$manifest" ]] && sources+=("$manifest")
    done
    if [[ ${#sources[@]} -eq 0 ]]; then
        rule_registry_init
    else
        rule_registry_init "${sources[@]}"
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

# Portable relative path: GNU realpath --relative-to is absent on BSD/macOS
# (it fails and yields an empty string, producing empty-target symlinks).
# Fallback chain: GNU realpath -> python3 os.path.relpath -> absolute path.
_pack_relpath() {
    local target_dir="$1"
    local src_file="$2"
    local rel
    rel=$(realpath --relative-to="$target_dir" "$src_file" 2>/dev/null)
    if [[ -z "$rel" ]]; then
        rel=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$src_file" "$target_dir" 2>/dev/null)
    fi
    if [[ -z "$rel" ]]; then
        rel="$src_file"
    fi
    printf '%s' "$rel"
}

_sync_symlink_type() {
    local pack_dir="$1"
    local type_dir="$2"
    local target_dir="$3"
    [[ ! -d "$pack_dir/$type_dir" ]] && return
    for src_file in "$pack_dir/$type_dir/"*.md; do
        [[ ! -f "$src_file" ]] && continue
        local basename rel_path
        basename=$(basename "$src_file")
        rel_path=$(_pack_relpath "$target_dir" "$src_file")
        ln -sf "$rel_path" "$target_dir/$basename"
    done
}

# Pack workflows are flat .md files inside the pack; the plugin exposes them
# as skills/<name>/SKILL.md symlinks (skill layout requires one dir per skill).
_sync_pack_skills() {
    local pack_dir="$1"
    local skills_root="$2"
    [[ ! -d "$pack_dir/commands" ]] && return
    for src_file in "$pack_dir/commands/"*.md; do
        [[ ! -f "$src_file" ]] && continue
        local name rel_path
        name=$(basename "$src_file" .md)
        mkdir -p "$skills_root/$name"
        rel_path=$(_pack_relpath "$skills_root/$name" "$src_file")
        ln -sf "$rel_path" "$skills_root/$name/SKILL.md"
    done
}

# Does this symlink point at something inside the packs directory?
# The sweep below used to remove every symlink it found under agents/ and
# skills/, which is more than this function owns: it runs on SessionStart
# against the live checkout, so anything else a developer had symlinked there
# was deleted and never put back. It now only removes what a pack put there.
_pack_owns_symlink() {
    local link="$1" packs_dir="$2"
    [[ -L "$link" ]] || return 1
    # A dangling link is a pack that went away: sweeping it is the point.
    [[ -e "$link" ]] || return 0
    local target
    target=$(cd "$(dirname "$link")" 2>/dev/null && cd "$(dirname "$(readlink "$link")")" 2>/dev/null && pwd) || return 1
    [[ "$target" == "$packs_dir"/* ]]
}

pack_sync_symlinks() {
    local root="${CLAUDE_PLUGIN_ROOT:-$(pwd)}"
    local packs_dir="${_PACKS_DIR:-$root/packs}"
    packs_dir=$(cd "$packs_dir" 2>/dev/null && pwd) || return 0

    for f in "$root/agents/"*.md; do
        _pack_owns_symlink "$f" "$packs_dir" && rm -- "$f"
    done
    for f in "$root/skills/"*/SKILL.md; do
        _pack_owns_symlink "$f" "$packs_dir" || continue
        rm -- "$f"
        # Only the directory this loop just emptied, never a core skill's.
        rmdir "$(dirname "$f")" 2>/dev/null || true
    done

    local pack_name
    while IFS= read -r pack_name; do
        [[ -z "$pack_name" ]] && continue
        local pack_dir="$packs_dir/$pack_name"
        _sync_symlink_type "$pack_dir" "agents" "$root/agents"
        _sync_pack_skills "$pack_dir" "$root/skills"
    done <<< "$(pack_loaded)"
}
