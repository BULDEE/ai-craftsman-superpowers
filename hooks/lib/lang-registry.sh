#!/usr/bin/env bash
# =============================================================================
# Language Registry - the file-to-language mapping, owned by the packs.
#
# The engine knows the SHAPE of the registry and none of its content. Adding
# the fiftieth language is adding a fiftieth pack, with no edit here and none
# in any hook. The literal `case "$EXT" in php|ts|tsx)` this replaces was
# duplicated across ten call sites with no parity test, and it silently
# disabled every pack whose language it had never heard of.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/lang-registry.sh"
#   lang_registry_init "/path/a/pack.yml" "/path/b/pack.yml"
#   lang_for_file "src/main.dart"        → dart
#   lang_capability dart test_commands   → flutter test
#   lang_all_extensions                  → dart\nphp\nts...
#   pack_dispatch_file "src/main.dart"   → runs every pack_validate_dart*
# =============================================================================

_LANG_REGISTRY_FILE=""
_LANG_REGISTRY_KNOWN_FILE=""
_LANG_REGISTRY_BUILDER=""

_lang_registry_builder() {
    if [[ -z "$_LANG_REGISTRY_BUILDER" ]]; then
        _LANG_REGISTRY_BUILDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lang_registry.py"
    fi
    printf '%s' "$_LANG_REGISTRY_BUILDER"
}

_lang_registry_cache_dir() {
    local base="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/craftsman}"
    mkdir -p "$base" 2>/dev/null || true
    printf '%s' "$base"
}

# The cache key is the set of manifests, so a project loading a different pack
# set gets a different file rather than a stale one.
_lang_registry_cache_key() {
    printf '%s\n' "$@" | cksum | tr -d ' \t' | cut -c1-16
}

# Rebuild when any manifest is newer than the cache. Parsing six manifests
# costs one python3 start (~40ms), which is most of the hook's 50ms budget, so
# the steady state has to be a file read.
_lang_registry_is_stale() {
    local cache="$1"
    shift
    [[ ! -f "$cache" ]] && return 0
    local manifest
    for manifest in "$@"; do
        [[ -f "$manifest" && "$manifest" -nt "$cache" ]] && return 0
    done
    return 1
}

_lang_registry_build_cache() {
    local label="$1"
    shift
    local cache_dir key cache
    cache_dir=$(_lang_registry_cache_dir)
    key=$(_lang_registry_cache_key "$@")
    cache="${cache_dir}/lang-${label}-${key}.tsv"

    if _lang_registry_is_stale "$cache" "$@"; then
        if command -v python3 >/dev/null 2>&1; then
            python3 "$(_lang_registry_builder)" "$@" > "${cache}.tmp" 2>/dev/null
            mv -f "${cache}.tmp" "$cache" 2>/dev/null || rm -f "${cache}.tmp"
        else
            # No python3: an empty registry disables every pack validator, and
            # a silent pass is exactly the failure mode this file exists to
            # remove. Say so once, on stderr, and keep the hook alive.
            echo "craftsman: python3 not found, no language was registered and no pack validator will run" >&2
            : > "$cache"
        fi
    fi
    printf '%s' "$cache"
}

# lang_registry_init <pack.yml> [<pack.yml> ...]
# The manifests of packs that passed the stack filter. This drives dispatch.
lang_registry_init() {
    # A second init with a different pack set must not serve the first set's
    # memoised answer.
    _LANG_FOR_FILE_KEY=""
    _LANG_FOR_FILE_VALUE=""

    [[ $# -eq 0 ]] && { _LANG_REGISTRY_FILE=""; return 0; }
    _LANG_REGISTRY_FILE=$(_lang_registry_build_cache "registry" "$@")
    # Exported so the Python tools (structural metrics, ratchet, hotspots,
    # codemap) read the same registry as the shell, rather than each carrying
    # its own list of extensions. They run as separate processes, so an
    # environment variable is the only channel they share.
    export CRAFTSMAN_LANG_REGISTRY="$_LANG_REGISTRY_FILE"
    return 0
}

# lang_registry_init_known <pack.yml> [<pack.yml> ...]
# Every installed pack's manifest, stack filter or not. This drives discovery.
#
# "No pack claims this file" and "a pack claims it but the project's stack
# excludes it" are different facts. A .php file under stack: react is a
# deliberate exclusion and a legitimate pass; a repository where nothing was
# recognised at all is a gate that never ran. Collapsing the two made
# `--config stack=react` on a PHP file exit 2 with "no source file was found".
lang_registry_init_known() {
    [[ $# -eq 0 ]] && { _LANG_REGISTRY_KNOWN_FILE=""; return 0; }
    _LANG_REGISTRY_KNOWN_FILE=$(_lang_registry_build_cache "known" "$@")
    return 0
}

# lang_extension_is_known <path> - some installed pack declares this extension,
# whether or not it is active for this project's stack.
lang_extension_is_known() {
    local file="$1"
    [[ -n "$_LANG_REGISTRY_KNOWN_FILE" && -f "$_LANG_REGISTRY_KNOWN_FILE" ]] || return 1
    local base extension
    base="${file##*/}"
    case "$base" in
        *.*) extension="${base##*.}" ;;
        *)   return 1 ;;
    esac
    awk -F'\t' -v ext="$extension" \
        '$2 == "extensions" && $3 == ext { found = 1; exit } END { exit !found }' \
        "$_LANG_REGISTRY_KNOWN_FILE" 2>/dev/null
}

_lang_registry_ready() {
    [[ -n "$_LANG_REGISTRY_FILE" && -f "$_LANG_REGISTRY_FILE" ]]
}

# lang_for_file <path> → language id, empty when no loaded pack claims it.
# Empty is a legitimate answer: a .go file with no Go pack is a deliberate
# exclusion, not a gap. Callers must not treat it as an error.
# One awk fork costs ~5ms and a single hook invocation asks this question five
# times (dispatch, static analysis, custom rules, metrics, ratchet), which is
# half the 50ms budget spent re-reading one line. Memoise the last answer: hooks
# process one file at a time, so a single-entry cache hits every time.
_LANG_FOR_FILE_KEY=""
_LANG_FOR_FILE_VALUE=""

lang_for_file() {
    local file="$1"
    _lang_registry_ready || return 0

    if [[ "$file" == "$_LANG_FOR_FILE_KEY" ]]; then
        printf '%s' "$_LANG_FOR_FILE_VALUE"
        return 0
    fi

    local base extension resolved=""
    base="${file##*/}"
    case "$base" in
        *.*) extension="${base##*.}" ;;
        *)   _LANG_FOR_FILE_KEY="$file"; _LANG_FOR_FILE_VALUE=""; return 0 ;;
    esac
    resolved=$(awk -F'\t' -v ext="$extension" \
        '$2 == "extensions" && $3 == ext { print $1; exit }' \
        "$_LANG_REGISTRY_FILE" 2>/dev/null)

    _LANG_FOR_FILE_KEY="$file"
    _LANG_FOR_FILE_VALUE="$resolved"
    printf '%s' "$resolved"
}

# lang_capability <language> <capability> → one value per line
lang_capability() {
    local language="$1" capability="$2"
    _lang_registry_ready || return 0
    awk -F'\t' -v lang="$language" -v cap="$capability" \
        '$1 == lang && $2 == cap { print $3 }' \
        "$_LANG_REGISTRY_FILE" 2>/dev/null
}

# lang_all_capability <capability> → every value across every language
lang_all_capability() {
    local capability="$1"
    _lang_registry_ready || return 0
    awk -F'\t' -v cap="$capability" '$2 == cap { print $3 }' \
        "$_LANG_REGISTRY_FILE" 2>/dev/null | sort -u
}

lang_all_extensions() {
    lang_all_capability "extensions"
}

# Every extension any installed pack declares, stack filter or not. This is the
# set a directory walk must visit: excluding a file at walk time is
# indistinguishable, downstream, from the file not existing.
lang_all_known_extensions() {
    [[ -n "$_LANG_REGISTRY_KNOWN_FILE" && -f "$_LANG_REGISTRY_KNOWN_FILE" ]] || return 0
    awk -F'\t' '$2 == "extensions" { print $3 }' \
        "$_LANG_REGISTRY_KNOWN_FILE" 2>/dev/null | sort -u
}

lang_registered() {
    _lang_registry_ready || return 0
    awk -F'\t' '{ print $1 }' "$_LANG_REGISTRY_FILE" 2>/dev/null | sort -u
}

# config_lang_enabled <language> - a language is enabled when a pack compatible
# with the project's stack contributed it. The stack filter already ran in
# _pack_stack_compatible at load time, so presence in the registry IS the gate.
# This replaces one hand-written predicate per language.
config_lang_enabled() {
    local language="$1"
    [[ -z "$language" ]] && return 1
    lang_registered | grep -qx "$language"
}

# Validator functions are discovered by prefix rather than declared a second
# time in the manifest. A pack shipping pack_validate_php, _php_layers,
# _php_persistence and _php_security gets all four called, and a manifest that
# drifts from its scripts is not possible because there is nothing to drift.
_lang_validator_functions() {
    local language="$1"
    declare -F 2>/dev/null \
        | awk '{ print $3 }' \
        | grep -E "^pack_validate_${language}(_[a-z_]+)?$" \
        | sort
}

# pack_dispatch_file <path> - run every validator the loaded packs provide for
# this file's language. Returns 0 when no pack claims the file.
pack_dispatch_file() {
    local file="$1"
    local language
    language=$(lang_for_file "$file")
    [[ -z "$language" ]] && return 0
    config_lang_enabled "$language" || return 0

    local validator
    while IFS= read -r validator; do
        [[ -z "$validator" ]] && continue
        "$validator" "$file"
    done <<< "$(_lang_validator_functions "$language")"
    return 0
}

# pack_dispatch_static_analysis <path> - same contract for pack_sa_<language>.
pack_dispatch_static_analysis() {
    local file="$1"
    local language
    language=$(lang_for_file "$file")
    [[ -z "$language" ]] && return 0
    local func="pack_sa_${language}"
    if type "$func" &>/dev/null 2>&1; then
        "$func" "$file"
    fi
    return 0
}
