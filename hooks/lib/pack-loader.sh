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
# The credential shapes SEC001 reads in every pack: one list, so a new key
# prefix reaches each language at once (CR-257).
# shellcheck source=./secret-patterns.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secret-patterns.sh"

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
# Read in-shell. This was grep | head | sed | tr | tr | sed: six processes for
# one scalar, called once per pack per hook invocation.
_pack_yml_strip() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value//\"/}"
    value="${value//\'/}"
    printf '%s' "$value"
}

_pack_yml_value() {
    local key="$1" file="$2" line
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            "${key}:"*)
                _pack_yml_strip "${line#*:}"
                printf '\n'
                return 0
                ;;
        esac
    done < "$file"
    return 0
}

# Extract an inline YAML array value from a top-level key.
# e.g.  stack: ["symfony", "fullstack"]  →  symfony (line 1)  fullstack (line 2)
_pack_yml_array() {
    local key="$1" file="$2" line found="" item rest
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            "${key}:"*) found="$line"; break ;;
        esac
    done < "$file"
    [[ -z "$found" ]] && return 0
    rest="${found#*[}"
    [[ "$rest" == "$found" ]] && return 0
    rest="${rest%%]*}"
    while [[ -n "$rest" ]]; do
        item="${rest%%,*}"
        if [[ "$item" == "$rest" ]]; then rest=""; else rest="${rest#*,}"; fi
        item="$(_pack_yml_strip "$item")"
        [[ -n "$item" ]] && printf '%s\n' "$item"
    done
    return 0
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
# Compiled once per manifest, read from the cache after that.
#
# Four capabilities are asked for per pack, and every question was its own awk
# process: seven packs meant 28 process starts to read seven small files, on a
# hook that runs on every write. The cache holds every nested pair the manifest
# declares, and `-nt` invalidates it the moment the manifest is edited, so a
# pack under development still behaves.
#
# It lives under CLAUDE_PLUGIN_DATA, never in a world-writable /tmp: this file
# decides which validators run, and a cache another user can write is a way to
# choose them.
# Bumped whenever the awk below changes. The cache is keyed by the manifest's
# identity, and a manifest does not change when the PARSER does: without this, a
# release that fixes how `validators:` is extracted would take effect on no
# installed machine, ever, because every one of them would keep serving the file
# compiled by the old parser. This file decides which validators run.
_PACK_YML_CACHE_VERSION="2"

# Injective, unlike `${file//\//_}`, which sent `/` and `_` to the same
# character: `a/b/pack.yml` and `a_b/pack.yml` shared one cache entry, and the
# second pack silently served the first one's validators. External pack paths
# come from the user's own config, so both spellings are reachable.
#
# Hashed past a threshold, because the escaping triples every `_` and mktemp
# adds six characters: a deep checkout crossed NAME_MAX, mktemp failed, and the
# pack lost every validator with nothing on stderr. A hash costs one process on
# the paths that would otherwise not work at all.
_PACK_YML_KEY_MAX=180

_pack_yml_cache_key() {
    local key="$1"
    key="${key//%/%25}"
    key="${key//_/%5f}"
    key="${key//\//_}"
    if [[ "${#key}" -gt "$_PACK_YML_KEY_MAX" ]]; then
        key="h$(printf '%s' "$1" | cksum | tr -d ' ')-${key: -60}"
    fi
    printf '%s' "$key"
}

# The manifest's identity, not its ordering against a file. `-nt` answers "is it
# newer", which is one-directional and second-granular in bash 3.2: a manifest
# edited twice in one second was not re-read, and a `git checkout` of an older
# version, a `git stash pop`, a `tar -x` or an `rsync -t` moved the mtime
# BACKWARDS and froze the cache on the newer content indefinitely. That is the
# pack developer's everyday loop, which the cache comment claimed to protect.
_pack_yml_identity() {
    # The loop names a manifest packs/go//pack.yml, the list packs/go/pack.yml.
    # A bare `/` replacement: bash 3.2 keeps the backslash of `\/` in the
    # result, so packs/go\/pack.yml matched nothing and every manifest was
    # stat'ed on its own anyway.
    local path="${1//\/\///}" before
    if [[ "$_PACK_YML_IDENTITIES" == *$'\t'"$path"$'\n'* ]]; then
        before="${_PACK_YML_IDENTITIES%%$'\t'"$path"$'\n'*}"
        printf '%s' "${before##*$'\n'}"
        return 0
    fi
    stat -f '%m %z' "$1" 2>/dev/null || stat -c '%Y %s' "$1" 2>/dev/null || printf 'unknown'
}

# _pack_yml_identities_load <manifest>...: every identity in one `stat`, as
# lines of "<identity><TAB><path>". One process per manifest was seven per
# hook, 30 ms of a post-write (CR-278); a path missing from the list is
# stat'ed on its own, so the list can only save work, never change an answer.
_PACK_YML_IDENTITIES=""
_pack_yml_identities_load() {
    [[ $# -gt 0 ]] || return 0
    _PACK_YML_IDENTITIES=$'\n'"$(stat -f '%m %z%t%N' "$@" 2>/dev/null || stat --printf='%Y %s\t%n\n' "$@" 2>/dev/null)"$'\n'
}

# The compile itself. Kept as a function because it is also the FALLBACK: a
# cache is an optimisation, and a read-only CLAUDE_PLUGIN_DATA, a full disk or a
# path no filesystem will hold must never change the answer, only its cost.
_pack_yml_nested_compile() {
    awk '
        /^[a-zA-Z]/ { parent = $0; sub(/:.*/, "", parent); next }
        /^[[:space:]]+[a-zA-Z_]+:.*\[/ {
            child = $0
            sub(/^[[:space:]]+/, "", child)
            sub(/:.*/, "", child)
            if (seen[parent "." child]++) next
            line = $0
            sub(/^[^[]*\[/, "", line)
            sub(/\].*$/, "", line)
            count = split(line, items, ",")
            for (index_ = 1; index_ <= count; index_++) {
                value = items[index_]
                gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", value)
                gsub(/^'"'"'|'"'"'$/, "", value)
                if (value != "" && parent != "") print parent "." child "\t" value
            }
        }
    ' "$1" 2>/dev/null
}

_pack_yml_nested_cache() {
    local file="$1"
    # The directory pack_loader_init resolved, without a subshell per manifest.
    local cache_dir="${_CRAFTSMAN_CACHE_DIR:-$(session_cache_dir)}"
    [[ -n "$cache_dir" ]] || return 1
    cache_dir="${cache_dir}/cache/pack-yml"
    local cache="${cache_dir}/v${_PACK_YML_CACHE_VERSION}-$(_pack_yml_cache_key "$file")"
    local want header temp

    want="#craftsman-pack-yml v${_PACK_YML_CACHE_VERSION} $(_pack_yml_identity "$file")"

    # A header line, not an mtime comparison. It carries the parser version and
    # the manifest's size and mtime, so a cache truncated by a crash, written by
    # an older parser, or left behind by a manifest that moved backwards in time
    # all fail the same equality test. An empty COMPILE is legitimate (a
    # manifest with no nested arrays), so emptiness cannot be the test.
    if [[ -f "$cache" ]] && IFS= read -r header < "$cache" 2>/dev/null \
        && [[ "$header" == "$want" ]]; then
        printf '%s' "$cache"
        return 0
    fi

    mkdir -p "$cache_dir" 2>/dev/null || return 1
    chmod 700 "$cache_dir" 2>/dev/null || true

    # Written to a temp file and renamed over the target, the same rule
    # CLAUDE.md states for session-state.json, and worse here: a torn read does
    # not lose a counter, it loses every validator a pack declares. Measured
    # before this: twelve concurrent readers on a cold cache, three saw zero
    # entries and ran no validator at all, exit 0 and no message.
    temp=$(mktemp "${cache_dir}/tmp.XXXXXX" 2>/dev/null) || return 1
    {
        printf '%s\n' "$want"
        _pack_yml_nested_compile "$file"
    } > "$temp" 2>/dev/null || { rm -f "$temp"; return 1; }
    mv -f "$temp" "$cache" 2>/dev/null || { rm -f "$temp"; return 1; }
    printf '%s' "$cache"
}

# The pairs of the last manifest read, kept in this process. pack_loader_init
# asks four questions of each pack in a row, and every answer came back through
# `$(...)`: a subshell that could keep nothing it read, so each question paid
# for its own cache lookup, cache key and `stat`. Seven packs cost 430 ms of a
# 1.3 s post-write (CR-278). The loader now asks in this shell, through
# _pack_yml_nested_into, and reads each manifest once.
# A here-string is a temporary file in bash 3.2, so the answers are walked by
# parameter expansion instead (_pack_lines_next), and the pairs searched by it.
_PACK_YML_MEMO_FILE=""
_PACK_YML_MEMO_PAIRS=""

# _pack_lines_next <var>: pops the first line of _PACK_LINES into <var>;
# returns 1 when none is left. _PACK_LINES ends with a newline.
_pack_lines_next() {
    [[ -n "$_PACK_LINES" ]] || return 1
    printf -v "$1" '%s' "${_PACK_LINES%%$'\n'*}"
    _PACK_LINES="${_PACK_LINES#*$'\n'}"
}

_pack_yml_nested_load() {
    local file="$1" cache pairs=""
    [[ "$file" == "$_PACK_YML_MEMO_FILE" ]] && return 0
    cache="$(_pack_yml_nested_cache "$file")"
    if [[ -n "$cache" && -f "$cache" ]]; then
        # One read for the whole file: line by line, the seven manifests cost
        # 587 reads per hook. Its first line, the identity, stays: a search
        # needs a newline, a key and a tab, which that line never holds.
        IFS= read -r -d '' pairs < "$cache"
    else
        # No cache available. Parse the manifest directly rather than answer
        # "this pack declares nothing", which is what a returning-empty
        # optimisation would have said on a read-only data directory.
        pairs="$(_pack_yml_nested_compile "$file")"$'\n'
    fi
    _PACK_YML_MEMO_FILE="$file"
    _PACK_YML_MEMO_PAIRS="$pairs"
}

# _pack_yml_nested_into <var> <parent> <child> <file>: the values, one per line,
# assigned to <var> in the caller's shell.
# Its locals carry a prefix: printf -v assigns the innermost variable of that
# name, so a caller asking for `values` was answered into this function's own.
_pack_yml_nested_into() {
    local _pny_into="$1" _pny_needle=$'\n'"${2}.${3}"$'\t' _pny_file="$4" _pny_rest _pny_value _pny_values=""
    printf -v "$_pny_into" '%s' ""
    [[ -f "$_pny_file" ]] || return 0
    _pack_yml_nested_load "$_pny_file"
    # Jump from one matching line to the next: walking every pair cost four
    # questions times seven manifests times each manifest's lines, 2,200 turns
    # of the loop per hook.
    _pny_rest=$'\n'"$_PACK_YML_MEMO_PAIRS"
    while [[ "$_pny_rest" == *"$_pny_needle"* ]]; do
        _pny_rest="${_pny_rest#*"$_pny_needle"}"
        _pny_value="${_pny_rest%%$'\n'*}"
        _pny_values="${_pny_values}${_pny_value}"$'\n'
        _pny_rest="${_pny_rest#"$_pny_value"}"
    done
    printf -v "$_pny_into" '%s' "$_pny_values"
}

_pack_yml_nested_array() {
    local values
    _pack_yml_nested_into values "$1" "$2" "$3"
    printf '%s' "$values"
}

# Return 0 if the pack at pack_dir is compatible with the current stack.
_pack_stack_compatible() {
    local pack_dir="$1"
    local manifest="$pack_dir/pack.yml"
    local current_stack="${_PACK_CURRENT_STACK:-}"
    [[ -n "$current_stack" ]] || current_stack=$(config_stack 2>/dev/null || echo "fullstack")

    local compat_stacks
    _pack_yml_nested_into compat_stacks "compatibility" "stack" "$manifest"
    [[ -z "$compat_stacks" ]] && return 1

    local s _PACK_LINES="$compat_stacks"
    while _pack_lines_next s; do
        [[ -z "$s" ]] && continue
        [[ "$s" == "*" ]] && return 0
        [[ "$s" == "$current_stack" ]] && return 0
    done

    return 1
}

_register_pack_validators() {
    local pack_dir="$1"
    local validators
    _pack_yml_nested_into validators "hooks" "validators" "$pack_dir/pack.yml"
    local v _PACK_LINES="$validators"
    while _pack_lines_next v; do
        [[ -z "$v" ]] && continue
        local vpath="$pack_dir/$v"
        if [[ -f "$vpath" ]]; then
            # shellcheck disable=SC1090
            source "$vpath"
            _PACK_VALIDATORS="${_PACK_VALIDATORS}${vpath}\n"
        fi
    done
}

_register_pack_sa_tools() {
    local pack_dir="$1"
    local sa_tools
    _pack_yml_nested_into sa_tools "static_analysis" "tools" "$pack_dir/pack.yml"
    local tool_entry _PACK_LINES="$sa_tools"
    while _pack_lines_next tool_entry; do
        [[ -z "$tool_entry" ]] && continue
        local tpath="$pack_dir/$tool_entry"
        if [[ -f "$tpath" ]]; then
            # shellcheck disable=SC1090
            source "$tpath"
            _PACK_SA_TOOLS="${_PACK_SA_TOOLS}${tpath}\n"
        fi
    done
}

_register_pack_scaffolds() {
    local pack_dir="$1"
    local pack_name="$2"
    local scaffold_types
    _pack_yml_nested_into scaffold_types "commands" "scaffold_types" "$pack_dir/pack.yml"
    local scaffold_type _PACK_LINES="$scaffold_types"
    while _pack_lines_next scaffold_type; do
        [[ -z "$scaffold_type" ]] && continue
        _PACK_SCAFFOLD_TYPES="${_PACK_SCAFFOLD_TYPES}${pack_name}:${scaffold_type}\n"
    done
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
    _pack_yml_identities_load "$packs_dir"/*/pack.yml
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
    local cache_directory
    cache_directory=$(session_cache_dir)
    local _CRAFTSMAN_CACHE_DIR="$cache_directory"
    local packs_dir="${1:-$(_pack_default_packs_dir)}"
    _PACKS_DIR="$packs_dir"
    # One answer for every pack: config_stack resolves three config layers.
    local _PACK_CURRENT_STACK
    _PACK_CURRENT_STACK=$(config_stack 2>/dev/null || echo "fullstack")

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
# Fallback chain: GNU realpath -> lexical -> python3 os.path.relpath -> absolute path.
_pack_relpath() {
    local target_dir="$1"
    local src_file="$2"
    local rel
    rel=$(realpath --relative-to="$target_dir" "$src_file" 2>/dev/null)
    [[ -z "$rel" ]] && rel=$(_pack_relpath_lexical "$target_dir" "$src_file")
    if [[ -z "$rel" ]]; then
        rel=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$src_file" "$target_dir" 2>/dev/null)
    fi
    if [[ -z "$rel" ]]; then
        rel="$src_file"
    fi
    printf '%s' "$rel"
}

# os.path.relpath without the python3 start, which was a third of a macOS
# session start: one per pack file, every session. For two absolute paths free
# of `.`, `..` and `//`, a file outside the directory it is measured from,
# relpath is a pure prefix computation; anything else returns 1 and goes on
# down the chain.
_pack_relpath_lexical() {
    local from="$1" to="$2" common up=""
    [[ "$from" == /* && "$to" == /* && "$from/" != "$to"/* ]] || return 1
    case "$from/ $to/" in *//*|*/./*|*/../*) return 1 ;; esac
    common="$from"
    while [[ "$to" != "$common"/* ]]; do
        common="${common%/*}"
        up="../$up"
    done
    printf '%s%s' "$up" "${to#"$common"/}"
}

_sync_symlink_type() {
    local pack_dir="$1"
    local type_dir="$2"
    local target_dir="$3"
    [[ ! -d "$pack_dir/$type_dir" ]] && return
    for src_file in "$pack_dir/$type_dir/"*.md; do
        [[ ! -f "$src_file" ]] && continue
        local basename rel_path
        basename="${src_file##*/}"
        # Shipped agent copies are built and checked before installation.
        # Keep regular files intact; only runtime-owned links are refreshed.
        [[ -f "$target_dir/$basename" && ! -L "$target_dir/$basename" ]] && continue
        rel_path=$(_pack_relpath "$target_dir" "$src_file")
        ln -sf "$rel_path" "$target_dir/$basename"
    done
}

# Pack workflows are flat .md files inside the pack; the plugin exposes them
# as skills/<name>/SKILL.md (skill layout requires one dir per skill). A COPY,
# not a symlink: the Codex skill loader (0.154.0, `codex debug prompt-input`)
# lists a regular SKILL.md and a symlinked directory, and skips a symlinked
# SKILL.md file, so the three pack skills were absent from every Codex session
# (audit CR-117, C5: 19 of 22). The copy is refreshed whenever it differs from
# its source, and a sidecar names that source so the sweep above knows which
# skill directories a pack owns. tests/core/test-pack-loader.sh refuses a copy
# that diverges from its source.
PACK_SKILL_SOURCE_FILE=".craftsman-pack-source"
_sync_pack_skills() {
    local pack_dir="$1"
    local skills_root="$2"
    [[ ! -d "$pack_dir/commands" ]] && return
    for src_file in "$pack_dir/commands/"*.md; do
        [[ ! -f "$src_file" ]] && continue
        local name rel_path target
        name="${src_file##*/}"
        name="${name%.md}"
        target="$skills_root/$name/SKILL.md"
        mkdir -p "$skills_root/$name"
        rel_path=$(_pack_relpath "$skills_root/$name" "$src_file")
        # A symlink left by an older version is replaced by the copy.
        [[ -L "$target" ]] && rm -f -- "$target"
        if ! cmp -s -- "$src_file" "$target" 2>/dev/null; then
            cp -- "$src_file" "$target.tmp.$$" && mv -f -- "$target.tmp.$$" "$target"
        fi
        _pack_write_sidecar "$skills_root/$name/$PACK_SKILL_SOURCE_FILE" "$rel_path"
    done
}

# Rewritten only when it would change: the plugin directory is shared by every
# session on the machine, and a write per session per skill buys nothing.
_pack_write_sidecar() {
    local sidecar="$1" rel_path="$2" current=""
    { IFS= read -r current < "$sidecar"; } 2>/dev/null
    [[ "$current" == "$rel_path" ]] || printf '%s\n' "$rel_path" > "$sidecar"
}

# The skill names the loaded packs serve, one per line between newlines, so a
# name is tested whole: `*$'\n'name$'\n'*`.
_pack_served_skills() {
    local packs_dir="$1" pack_name src names=$'\n'
    while IFS= read -r pack_name; do
        [[ -z "$pack_name" ]] && continue
        for src in "$packs_dir/$pack_name/commands/"*.md; do
            [[ -f "$src" ]] || continue
            src="${src##*/}"
            names="${names}${src%.md}"$'\n'
        done
    done <<< "$(pack_loaded)"
    printf '%s' "$names"
}

# Does this skill directory hold a pack's copy (sidecar naming a source under
# packs/), or the symlink an older version left? Either is the pack's to sweep.
_pack_owns_skill() {
    local skill_md="$1" packs_dir="$2" sidecar source rel=""
    _pack_owns_symlink "$skill_md" "$packs_dir" && return 0
    sidecar="${skill_md%/*}/$PACK_SKILL_SOURCE_FILE"
    [[ -f "$sidecar" ]] || return 1
    { IFS= read -r rel < "$sidecar"; } 2>/dev/null
    # dirname, in-shell: a name with no slash is in `.`.
    [[ "$rel" == */* ]] && rel="${rel%/*}" || rel=.
    source=$(cd "${skill_md%/*}" 2>/dev/null && cd "$rel" 2>/dev/null && pwd) || return 0
    [[ "$source" == "$packs_dir"/* ]]
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

# Removes the skill copies a pack owns and no loaded pack serves any more. A
# skill a loaded pack still serves is refreshed in place by _sync_pack_skills,
# never removed and copied back: Claude Code discovers skills while
# SessionStart hooks run, and a session that looked in between found it missing.
_pack_sweep_skills() {
    local root="$1" packs_dir="$2" served skill_dir
    served="$(_pack_served_skills "$packs_dir")"$'\n'
    for skill_dir in "$root/skills/"*/SKILL.md; do
        _pack_owns_skill "$skill_dir" "$packs_dir" || continue
        skill_dir="${skill_dir%/SKILL.md}"
        [[ "$served" == *$'\n'"${skill_dir##*/}"$'\n'* ]] && continue
        rm -f -- "$skill_dir/SKILL.md" "$skill_dir/$PACK_SKILL_SOURCE_FILE"
        # Only the directory this loop just emptied, never a core skill's.
        rmdir "$skill_dir" 2>/dev/null || true
    done
}

pack_sync_symlinks() {
    local root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local packs_dir="${_PACKS_DIR:-$root/packs}"
    packs_dir=$(cd "$packs_dir" 2>/dev/null && pwd) || return 0

    for f in "$root/agents/"*.md; do
        _pack_owns_symlink "$f" "$packs_dir" && rm -- "$f"
    done
    _pack_sweep_skills "$root" "$packs_dir"

    local pack_name
    while IFS= read -r pack_name; do
        [[ -z "$pack_name" ]] && continue
        local pack_dir="$packs_dir/$pack_name"
        _sync_symlink_type "$pack_dir" "agents" "$root/agents"
        _sync_pack_skills "$pack_dir" "$root/skills"
    done <<< "$(pack_loaded)"
}
