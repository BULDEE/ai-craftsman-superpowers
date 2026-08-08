#!/usr/bin/env bash
# =============================================================================
# Healthcheck Library - Plugin health verification functions
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/healthcheck.sh"
#   hc_run_all          # Run all checks, populate _HC_NAMES/_HC_STATUSES/_HC_MESSAGES arrays
#   hc_summary          # One-line summary for SessionStart
#   hc_full_report      # Full formatted report for /craftsman:healthcheck
# =============================================================================

declare -a _HC_NAMES=()
declare -a _HC_STATUSES=()
declare -a _HC_MESSAGES=()
_HC_PASS=0
_HC_TOTAL=0

_hc_record() {
    local name="$1" status="$2" message="$3"
    _HC_NAMES+=("$name")
    _HC_STATUSES+=("$status")
    _HC_MESSAGES+=("$message")
    (( _HC_TOTAL++ ))
    [[ "$status" == "ok" ]] && (( _HC_PASS++ ))
}

# --- Individual checks ---

hc_check_system_deps() {
    local missing=""
    command -v python3 >/dev/null 2>&1 || missing="${missing} python3"
    command -v jq >/dev/null 2>&1 || missing="${missing} jq"
    command -v sqlite3 >/dev/null 2>&1 || missing="${missing} sqlite3"

    if [[ -z "$missing" ]]; then
        _hc_record "system" "ok" "python3 jq sqlite3"
    else
        _hc_record "system" "error" "missing:${missing}"
    fi
}

hc_check_node() {
    if ! command -v node >/dev/null 2>&1; then
        _hc_record "node" "error" "missing"
        return
    fi

    local version
    version=$(node --version 2>/dev/null | sed 's/^v//')
    local major
    major=$(echo "$version" | cut -d. -f1)

    if [[ "$major" -ge 20 ]]; then
        _hc_record "node" "ok" "v${version}"
    else
        _hc_record "node" "warn" "v${version} (need >=20)"
    fi
}

hc_check_config() {
    if [[ -f "${HOME}/.claude/.craft-config.yml" ]] || [[ -f "${PWD}/.craft-config.yml" ]]; then
        _hc_record "config" "ok" ".craft-config.yml"
    else
        _hc_record "config" "warn" "missing - run /craftsman:setup"
    fi
}

hc_check_packs() {
    local loaded
    loaded=$(pack_loaded 2>/dev/null || echo "")

    if [[ -z "$loaded" ]]; then
        _hc_record "packs" "warn" "none loaded"
        return
    fi

    local pack_list
    pack_list=$(echo "$loaded" | tr '\n' ' ' | sed 's/ $//')
    _hc_record "packs" "ok" "$pack_list"
}

hc_check_metrics_db() {
    local db_path="${METRICS_DB:-${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}/metrics.db}"
    if [[ -f "$db_path" ]]; then
        local sessions violations
        sessions=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo "0")
        violations=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM violations;" 2>/dev/null || echo "0")
        _hc_record "metrics" "ok" "${sessions} sessions, ${violations} violations"
    else
        _hc_record "metrics" "warn" "DB not found"
    fi
}

hc_check_channels() {
    if type channel_health &>/dev/null 2>&1; then
        local sentry_health
        sentry_health=$(channel_health "sentry" 2>/dev/null || echo "unknown")
        _hc_record "channels" "ok" "sentry:${sentry_health}"
    else
        _hc_record "channels" "ok" "no channels configured"
    fi
}

hc_check_superpowers() {
    local sp_dir=""
    for d in "${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers"/* "${HOME}/.claude/plugins/superpowers"; do
        [[ -d "$d" ]] && sp_dir="$d" && break
    done

    if [[ -n "$sp_dir" ]]; then
        local version="unknown"
        if [[ -f "${sp_dir}/plugin.json" ]]; then
            version=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('version','?'))" "${sp_dir}/plugin.json" 2>/dev/null || echo "?")
        fi
        _hc_record "superpowers" "ok" "v${version} - synergy active"
    else
        _hc_record "superpowers" "ok" "not installed (optional)"
    fi
}

# /craftsman:team's native mode depends on an experimental env flag; without it
# the skill degrades to parallel subagent dispatch. Status is "ok" either way:
# absence is a mode, not a fault. The message tells the user which mode they get.
hc_check_agent_teams() {
    if [[ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]]; then
        _hc_record "agent-teams" "ok" "native teams enabled"
    else
        _hc_record "agent-teams" "ok" "env flag not set - /craftsman:team runs in degraded parallel mode"
    fi
}

hc_check_session_bridge() {
    local bridge="${HOME}/.claude/craftsman-session-state-path"

    if [[ ! -f "$bridge" ]]; then
        _hc_record "session-bridge" "warn" "missing - restart session to create"
        return
    fi

    local target
    target=$(< "$bridge")

    if [[ -z "$target" ]]; then
        _hc_record "session-bridge" "error" "empty - restart session to fix"
        return
    fi

    local target_dir
    target_dir=$(dirname "$target")

    if [[ ! -d "$target_dir" ]]; then
        _hc_record "session-bridge" "warn" "target dir missing: ${target_dir}"
        return
    fi

    _hc_record "session-bridge" "ok" "$target"
}

# --- Aggregate ---

# Level 1.5 semantic validation (ADR-0019, amended): report which language
# servers are installed. The plugin never installs one and never ships an
# .lsp.json - Claude Code spawns a declared server unconditionally and surfaces
# a plugin error when the binary is missing, so LSP wiring belongs to the
# official per-language plugins the user opts into.
# Which server serves which language is the packs' knowledge, not a literal list.
_hc_installed_servers() {
    local language server
    while IFS= read -r language; do
        server=$(lang_capability "$language" lsp 2>/dev/null)
        [[ -z "$server" ]] && continue
        command -v "$server" >/dev/null 2>&1 && printf ' %s(%s)' "$server" "$language"
    done <<< "$(lang_registered 2>/dev/null)"
}

hc_check_lsp() {
    local found hints=""
    found=$(_hc_installed_servers)
    if [[ -n "$found" ]]; then
        _hc_record "lsp" "ok" "level-1.5 active:${found}"
    else
        hints="none installed - Level 1.5 inactive; install the official LSP plugin for your stack (php-lsp, typescript-lsp, pyright-lsp, rust-analyzer-lsp) plus its server binary (PHP: npm i -g intelephense)"
        _hc_record "lsp" "warn" "$hints"
    fi
}

hc_run_all() {
    _HC_NAMES=()
    _HC_STATUSES=()
    _HC_MESSAGES=()
    _HC_PASS=0
    _HC_TOTAL=0

    hc_check_system_deps
    hc_check_node
    hc_check_config
    hc_check_packs
    hc_check_metrics_db
    hc_check_channels
    hc_check_lsp
    hc_check_superpowers
    hc_check_agent_teams
    hc_check_session_bridge
}

hc_summary() {
    hc_run_all

    local failures=""
    for i in "${!_HC_NAMES[@]}"; do
        if [[ "${_HC_STATUSES[$i]}" != "ok" ]]; then
            failures="${failures}, ${_HC_NAMES[$i]}: ${_HC_MESSAGES[$i]}"
        fi
    done

    if [[ -z "$failures" ]]; then
        echo "Healthcheck: ${_HC_PASS}/${_HC_TOTAL} ok"
    else
        failures="${failures#, }"
        echo "Healthcheck: ${_HC_PASS}/${_HC_TOTAL} (${failures})"
    fi
}

hc_json() {
    hc_run_all

    local json_array="[]"
    for i in "${!_HC_NAMES[@]}"; do
        json_array=$(echo "$json_array" | jq -c --arg n "${_HC_NAMES[$i]}" --arg s "${_HC_STATUSES[$i]}" --arg m "${_HC_MESSAGES[$i]}" '. + [{name: $n, status: $s, message: $m}]')
    done

    echo "$json_array"
}
