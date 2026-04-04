#!/usr/bin/env bash
# =============================================================================
# Healthcheck Library — Plugin health verification functions
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/healthcheck.sh"
#   hc_run_all          # Run all checks, populate _HC_RESULTS array
#   hc_summary          # One-line summary for SessionStart
#   hc_full_report      # Full formatted report for /craftsman:healthcheck
# =============================================================================

declare -a _HC_RESULTS=()
_HC_PASS=0
_HC_TOTAL=0

_hc_record() {
    local name="$1" status="$2" message="$3"
    _HC_RESULTS+=("${name}|${status}|${message}")
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
        _hc_record "config" "warn" "missing — run /craftsman:setup"
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
    local db_path="${CLAUDE_PLUGIN_DATA:-/tmp}/metrics.db"
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

hc_check_ollama() {
    local packs
    packs=$(pack_loaded 2>/dev/null || echo "")

    if ! echo "$packs" | grep -q "ai-ml"; then
        return
    fi

    if curl -s --max-time 2 "http://localhost:11434/api/tags" >/dev/null 2>&1; then
        local model
        model=$(curl -s --max-time 2 "http://localhost:11434/api/tags" 2>/dev/null | python3 -c "import sys,json; models=json.load(sys.stdin).get('models',[]); print(models[0]['name'] if models else 'none')" 2>/dev/null || echo "unknown")
        _hc_record "ollama" "ok" "running (${model})"
    else
        _hc_record "ollama" "error" "not running — run: ollama serve"
    fi
}

hc_check_knowledge() {
    local packs
    packs=$(pack_loaded 2>/dev/null || echo "")

    if ! echo "$packs" | grep -q "ai-ml"; then
        return
    fi

    local kb_dir="${HOME}/.claude/ai-craftsman-superpowers/knowledge"
    local db_path="${kb_dir}/.index/knowledge.db"

    if [[ ! -f "$db_path" ]]; then
        db_path="${kb_dir}/knowledge.db"
    fi

    if [[ -f "$db_path" ]]; then
        local chunks sources
        chunks=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM chunks;" 2>/dev/null || echo "0")
        sources=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT source) FROM chunks;" 2>/dev/null || echo "0")

        if [[ "$chunks" -gt 0 ]]; then
            _hc_record "knowledge" "ok" "${chunks} chunks / ${sources} sources"
        else
            _hc_record "knowledge" "warn" "DB empty — run /craftsman:knowledge sync"
        fi
    else
        _hc_record "knowledge" "error" "DB missing — run /craftsman:knowledge sync"
    fi
}

# --- Aggregate ---

hc_run_all() {
    _HC_RESULTS=()
    _HC_PASS=0
    _HC_TOTAL=0

    hc_check_system_deps
    hc_check_node
    hc_check_config
    hc_check_packs
    hc_check_metrics_db
    hc_check_channels
    hc_check_ollama
    hc_check_knowledge
}

hc_summary() {
    hc_run_all

    local failures=""
    for result in "${_HC_RESULTS[@]}"; do
        local status="${result#*|}"
        status="${status%%|*}"
        if [[ "$status" != "ok" ]]; then
            local name="${result%%|*}"
            local msg="${result##*|}"
            failures="${failures}, ${name}: ${msg}"
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

    local json_items=""
    for result in "${_HC_RESULTS[@]}"; do
        local name="${result%%|*}"
        local rest="${result#*|}"
        local status="${rest%%|*}"
        local message="${rest#*|}"
        json_items="${json_items}, {\"name\": \"${name}\", \"status\": \"${status}\", \"message\": \"${message}\"}"
    done
    json_items="${json_items#, }"

    echo "[${json_items}]"
}
