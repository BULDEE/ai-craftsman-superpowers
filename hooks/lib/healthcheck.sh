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

# This library names the host, so it brings the library that reads it rather
# than trusting its caller to have sourced it: skills/healthcheck/SKILL.md
# sources config.sh, pack-loader.sh and this file, and `host_detect` was
# undefined there, so a Claude Code session reported "unknown host" and
# "load status unknown" about itself (measured 2026-09-20).
_HC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
type host_detect >/dev/null 2>&1 || source "${_HC_LIB_DIR}/host.sh"

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

# The host this session runs under, and what the plugin can observe there.
# One number ("9/11") hid the loss of the main gate (research CR-131, R11);
# this row says, per capability, whether it is measured on this host. The
# facts are the captured ones (tests/fixtures/hosts/PROVENANCE.md): Codex
# sends no exit code for a shell command and ignores the `ask` decision,
# Claude Code sends both. `CRAFTSMAN_SESSION_HOST` is set by session-start.sh
# from its payload; a skill running later reads the environment instead.
# What the host can do is read from the matrix, never from a case per host:
# the case here knew Claude Code and Codex, and a Grok session (captured
# 2026-09-15) was reported "unknown host" while the same file already said
# what Copilot could not do. A host absent from the matrix is unqualified and
# said so; one present is described by what was measured for it.
hc_check_host() {
    local host="${CRAFTSMAN_SESSION_HOST:-}" capabilities="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/hooks/host-capabilities.json" row
    if [[ -z "$host" ]] && type host_detect >/dev/null 2>&1; then
        host=$(host_detect "")
    fi
    row=$(jq -r --arg h "$host" '
        .hosts[$h] // empty
        | [ $h + " " + (.version // "?"),
            (if .exit_code_observable then "test exit codes observable (verification loop live)" else "shell exit codes NOT observable (a test run grants and revokes nothing)" end),
            (if .ask_supported then "PreToolUse ask honoured" else "PreToolUse ask unsupported (gate config denied instead)" end),
            ("skills read from " + (.skills_dir // "?")) ]
        | .[0] + ": " + (.[1:] | join(", "))' "$capabilities" 2>/dev/null)
    if [[ -n "$row" ]]; then
        _hc_record "host" "ok" "$row"
    else
        _hc_record "host" "warn" "${host:-unknown} host: capabilities not qualified in hooks/host-capabilities.json; gates run, ask is treated as unsupported"
    fi
}

# Declared is not loaded, loaded is not triggered. hooks.json declares N
# handlers on M events; which of those events the host loads is measured per
# host in hooks/host-capabilities.json (Codex 0.154.0 loads 11 of the 12 kinds
# this plugin declares on: not TaskCompleted, PostToolUseFailure or
# FileChanged, audit CR-117 C10). A handler on an event the host does not load
# is named here with the function it carries, so a declaration ignored never
# counts as an active function. Triggered is this session's evidence only.
hc_check_hooks_declared() {
    local root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}" manifest capabilities host declared events missing
    manifest="$root/hooks/hooks.json"; capabilities="$root/hooks/host-capabilities.json"
    [[ -f "$manifest" ]] || { _hc_record "hooks" "error" "hooks.json missing"; return; }
    declared=$(jq '[.hooks[][] | .hooks[]] | length' "$manifest" 2>/dev/null || echo "?")
    events=$(jq -r '.hooks | keys | join(",")' "$manifest" 2>/dev/null)
    host="${CRAFTSMAN_SESSION_HOST:-}"
    [[ -z "$host" ]] && type host_detect >/dev/null 2>&1 && host=$(host_detect "")
    # No evidence is not "every event loads": an unknown host, or a host the
    # matrix does not record, is said so (review of 5cc64f4, F2).
    if [[ ! -f "$capabilities" ]] || ! jq -e --arg h "$host" '.hosts[$h]' "$capabilities" >/dev/null 2>&1; then
        _hc_record "hooks" "warn" "${declared} handlers declared on ${events}; which of them ${host:-this host} loads is not recorded in hooks/host-capabilities.json, so none is counted as active here"
        return
    fi
    missing=$(jq -r --arg h "$host" --slurpfile m "$manifest" '
        .event_functions as $f
        | (($m[0].hooks | keys) - .hosts[$h].events_loaded)
        | map(. + " (" + ($f[.] // "function not named") + ")")
        | join("; ")' "$capabilities" 2>/dev/null) || missing="__query_failed__"
    if [[ "$missing" == "__query_failed__" ]]; then
        _hc_record "hooks" "warn" "${declared} handlers declared; the capability query failed, loaded events unknown"
        return
    fi
    if [[ -n "$missing" ]]; then
        _hc_record "hooks" "warn" "${declared} handlers declared on ${events}; NOT loaded by ${host}: ${missing}. Trusted is the host's /hooks view, not measured here"
    else
        _hc_record "hooks" "ok" "${declared} handlers declared on ${events}; every event is one ${host:-this host} loads. Trusted is the host's /hooks view, not measured here"
    fi
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
    done <<< "$(lang_known_registered 2>/dev/null)"
}

hc_check_lsp() {
    local found hints=""
    found=$(_hc_installed_servers)
    if [[ -n "$found" ]]; then
        _hc_record "lsp" "ok" "level-1.5 active:${found}"
    else
        # The servers come from the packs' `lsp` capability, so a pack added
        # later names its own; the plugin side is Claude Code's official LSP
        # plugin for that server.
        hints="none installed - Level 1.5 inactive; install one of the language servers the packs declare ($(lang_all_known_capability lsp 2>/dev/null | tr '\n' ' ' | sed 's/ $//')) plus the official Claude Code LSP plugin for it"
        _hc_record "lsp" "warn" "$hints"
    fi
}

# How many skills a model can actually start (#48). Fifteen of twenty-two are
# locked with `disable-model-invocation: true` and start only when the user
# types them; a healthcheck that counted "22 skills" hid that the model can
# reach seven. Read from the frontmatter, the same authority the routing table
# reads, so the two numbers cannot disagree.
hc_check_skills() {
    local root skill total=0 invocable=0
    root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    for skill in "$root"/skills/*/SKILL.md; do
        [[ -f "$skill" ]] || continue
        total=$((total + 1))
        awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$skill" \
            | grep -q '^disable-model-invocation:[[:space:]]*true' && continue
        invocable=$((invocable + 1))
    done
    if [[ "$total" -eq 0 ]]; then
        _hc_record "skills" "warn" "none found"
        return
    fi
    _hc_record "skills" "ok" "${invocable} of ${total} model-invocable, $((total - invocable)) user-typed"
}

hc_run_all() {
    _HC_NAMES=()
    _HC_STATUSES=()
    _HC_MESSAGES=()
    _HC_PASS=0
    _HC_TOTAL=0

    hc_check_system_deps
    hc_check_node
    hc_check_host
    hc_check_hooks_declared
    hc_check_config
    hc_check_packs
    hc_check_skills
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
