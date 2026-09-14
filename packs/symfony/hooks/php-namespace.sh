#!/usr/bin/env bash
# =============================================================================
# The PHP root namespace, read from composer.json's psr-4 map.
#
# Sourced by layer-validator.sh, which is the only reader. It lived in
# hooks/lib/config.sh, where the engine carried a composer.json reader that no
# other language could use: a pack's knowledge of its own ecosystem belongs
# to the pack. Requires jq, as the validators do.
# craftsman-ignore: SH001
# =============================================================================

# The LAYER rules used to look for "App\Domain" and "App\Infrastructure"
# literally. "App" is the Symfony skeleton's default and nothing more: a
# project that renamed its root namespace, or a monorepo with several, got
# silent green from every layer rule. The root comes from composer.json's
# psr-4 map instead, preferring the entry that maps to src/.
_PHP_NS_ROOT_CACHE=""
_PHP_NS_ROOT_FOR=""

php_namespace_root() {
    local start_dir="${1:-$PWD}"
    if [[ "$_PHP_NS_ROOT_FOR" == "$start_dir" && -n "$_PHP_NS_ROOT_CACHE" ]]; then
        printf '%s' "$_PHP_NS_ROOT_CACHE"
        return 0
    fi

    local dir root=""
    dir="$(cd "$start_dir" 2>/dev/null && pwd)" || dir=""
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -f "$dir/composer.json" ]]; then
            root=$(_php_psr4_root "$dir/composer.json")
            break
        fi
        dir="$(dirname "$dir")"
    done

    [[ -n "$root" ]] || root="App"
    _PHP_NS_ROOT_FOR="$start_dir"
    _PHP_NS_ROOT_CACHE="$root"
    printf '%s' "$root"
}

_php_psr4_root() {
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
