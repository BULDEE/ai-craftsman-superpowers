#!/usr/bin/env bash
# =============================================================================
# Rule Registry - rule ids, wording and default severity, owned by the packs.
#
# ci/doctrine-export.sh held every id, group and sentence, and rules-engine.sh
# held the advisory defaults. A pack shipping DART001 had nowhere to declare any
# of it, so "the engine holds no list" was true of dispatch and false of
# doctrine.
#
# Same shape as lang-registry.sh: manifests compiled into one TSV, cached on
# disk, invalidated by mtime, queried with awk so bash 3.2 can read it.
#
# Usage:
#   rule_registry_init <core.yml> [<pack.yml> ...]
#   rule_text RULE           → the sentence, empty when unknown
#   rule_group RULE          → the doctrine section it belongs to
#   rule_default_severity R  → block|warn|ignore, empty when unknown
#   rule_owner RULE          → pack name, or "core"
#   rule_groups              → group names, in doctrine order
#   rules_in_group NAME      → rule ids of that group, declaration order
# =============================================================================

_RULE_REGISTRY_FILE=""

_rule_registry_builder() {
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rule_registry.py"
}

_rule_registry_is_stale() {
    local cache="$1"
    shift
    [[ ! -f "$cache" ]] && return 0
    local manifest
    for manifest in "$@"; do
        [[ -f "$manifest" && "$manifest" -nt "$cache" ]] && return 0
    done
    return 1
}

_rule_registry_compile() {
    local cache="$1"
    shift
    if command -v python3 >/dev/null 2>&1; then
        python3 "$(_rule_registry_builder)" "$@" > "${cache}.tmp" 2>/dev/null
        mv -f "${cache}.tmp" "$cache" 2>/dev/null || rm -f "${cache}.tmp"
        return 0
    fi
    # No python3 means no doctrine at all. Saying so once beats exporting an
    # empty rule set that reads as "nothing is enforced".
    echo "craftsman: python3 not found, no rule was registered" >&2
    : > "$cache"
}

rule_registry_init() {
    [[ $# -eq 0 ]] && { _RULE_REGISTRY_FILE=""; return 0; }

    local cache_dir key cache
    cache_dir="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/craftsman}"
    mkdir -p "$cache_dir" 2>/dev/null || true
    key=$(printf '%s\n' "$@" | cksum | tr -d ' \t' | cut -c1-16)
    cache="${cache_dir}/rule-registry-${key}.tsv"

    if _rule_registry_is_stale "$cache" "$@"; then
        _rule_registry_compile "$cache" "$@"
    fi

    _RULE_REGISTRY_FILE="$cache"
    export CRAFTSMAN_RULE_REGISTRY="$cache"
    return 0
}

# Build from what is on disk when no caller has initialised the registry.
#
# rules-engine.sh is sourced on its own by the export path, by tests and by any
# tool that only wants a severity. Depending on someone else having called
# pack_loader_init first would make rules_severity answer "block" for a rule its
# owner declared advisory, which is a silent behaviour change rather than a
# visible failure.
_rule_registry_autoinit() {
    local root sources=()
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [[ -f "$root/rules/core.yml" ]] && sources+=("$root/rules/core.yml")
    local manifest
    for manifest in "$root"/packs/*/pack.yml; do
        [[ -f "$manifest" ]] && sources+=("$manifest")
    done
    # External packs own rules too, and they are declared in the machine
    # owner's global config rather than found on disk under packs/.
    if type config_external_packs &>/dev/null 2>&1; then
        local ext_path
        while IFS= read -r ext_path; do
            [[ -z "$ext_path" ]] && continue
            [[ -f "$ext_path/pack.yml" ]] && sources+=("$ext_path/pack.yml")
        done <<< "$(config_external_packs 2>/dev/null)"
    fi
    [[ ${#sources[@]} -eq 0 ]] && return 1
    rule_registry_init "${sources[@]}"
}

_rule_registry_ready() {
    if [[ -z "$_RULE_REGISTRY_FILE" ]]; then
        _rule_registry_autoinit >/dev/null 2>&1 || return 1
    fi
    [[ -n "$_RULE_REGISTRY_FILE" && -f "$_RULE_REGISTRY_FILE" ]]
}

_rule_field() {
    local rule="$1" column="$2"
    _rule_registry_ready || return 0
    awk -F'\t' -v want="$rule" -v col="$column" \
        '$1 == want { print $col; exit }' "$_RULE_REGISTRY_FILE" 2>/dev/null
}

rule_group()            { _rule_field "$1" 2; }
rule_default_severity() { _rule_field "$1" 3; }
rule_owner()            { _rule_field "$1" 4; }
rule_text()             { _rule_field "$1" 5; }

rule_is_known() {
    [[ -n "$(rule_owner "$1")" ]]
}

# Every registered rule id. Callers that need to walk the doctrine should use
# this rather than reading the TSV, which also carries the group marker rows and
# is only built once _rule_registry_ready has run.
rule_ids() {
    _rule_registry_ready || return 0
    awk -F'\t' '$1 != "__group__" { print $1 }' "$_RULE_REGISTRY_FILE" 2>/dev/null
}

rule_groups() {
    _rule_registry_ready || return 0
    awk -F'\t' '$1 == "__group__" { print $2 "\t" $5 }' "$_RULE_REGISTRY_FILE" \
        2>/dev/null | sort -n | cut -f2
}

rules_in_group() {
    local group="$1"
    _rule_registry_ready || return 0
    awk -F'\t' -v want="$group" \
        '$1 != "__group__" && $2 == want { print $1 }' \
        "$_RULE_REGISTRY_FILE" 2>/dev/null
}
