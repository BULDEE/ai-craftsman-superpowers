#!/usr/bin/env bash
# =============================================================================
# Dispatch Context - one call, everything an agent needs to start informed.
#
# Agents used to open with a self-guided scan of the repository: the old
# InstructionsLoaded hook ASKED each agent to rebuild a map the plugin had
# already computed, and per the platform contract that event is side-effects
# only, so the request never even reached them. Each agent burned turns
# rediscovering structure and never saw the resolved rules at all.
#
# This script is the replacement: agents run it as their FIRST action and get
# the resolved doctrine (same rules engine as hooks and CI - the agent is a
# front-end, parity applies), the cached codemap, the current hotspots and the
# correction trends. Deterministic output, one agent turn, no drift.
#
# Usage (from an agent body):
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/lib/dispatch-context.sh"
#
# Always exits 0: a broken context source degrades to a missing section,
# never to a failed dispatch.
# =============================================================================
set -uo pipefail
trap 'exit 0' ERR

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$LIB_DIR")"
PLUGIN_ROOT="$(dirname "$HOOKS_DIR")"

source "${LIB_DIR}/config.sh" 2>/dev/null || true
source "${LIB_DIR}/rules-engine.sh" 2>/dev/null || true
source "${LIB_DIR}/metrics-db.sh" 2>/dev/null || true

# --- Resolved doctrine -------------------------------------------------------
# Rendered from the rules engine, so a project .craft-config.yml override is
# reflected here. Directory-level overrides still resolve per-file at write
# time; the hooks remain the enforcement point.
emit_doctrine() {
    [[ -f "${PLUGIN_ROOT}/ci/doctrine-export.sh" ]] || return 0
    command -v rules_severity >/dev/null 2>&1 || return 0
    source "${PLUGIN_ROOT}/ci/doctrine-export.sh" 2>/dev/null || true
    if command -v _doctrine_body >/dev/null 2>&1; then
        _doctrine_body 2>/dev/null || true
    fi
}

# --- Codemap (cached) --------------------------------------------------------
# Regenerated only when the repository HEAD moved since the cache was written;
# codemap.py itself never caches (ADR-0022), callers do.
emit_codemap() {
    local codemap_script="${LIB_DIR}/codemap.py"
    command -v python3 >/dev/null 2>&1 || return 0
    [[ -f "$codemap_script" ]] || return 0

    local cache_dir="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
    local project_key cache_file head_ref cached_ref codemap
    project_key=$(pwd | shasum 2>/dev/null | cut -c1-12) || project_key="default"
    cache_file="${cache_dir}/codemap-${project_key}.md"
    head_ref=$(git rev-parse HEAD 2>/dev/null || echo "no-git")

    cached_ref=""
    [[ -f "$cache_file" ]] && cached_ref=$(head -1 "$cache_file" 2>/dev/null)

    if [[ "$cached_ref" == "<!-- ${head_ref} -->" ]]; then
        echo ""
        tail -n +2 "$cache_file" 2>/dev/null || true
        return 0
    fi

    codemap=$(python3 "$codemap_script" . 2>/dev/null | head -40) || codemap=""
    [[ -z "$codemap" ]] && return 0
    echo ""
    printf '%s\n' "$codemap"
    mkdir -p "$cache_dir" 2>/dev/null && \
        printf '<!-- %s -->\n%s\n' "$head_ref" "$codemap" > "$cache_file" 2>/dev/null || true
}

# --- Hotspots ----------------------------------------------------------------
emit_hotspots() {
    command -v python3 >/dev/null 2>&1 || return 0
    [[ -f "${LIB_DIR}/hotspot_analysis.py" ]] || return 0
    local hotspots
    hotspots=$(python3 "${LIB_DIR}/hotspot_analysis.py" --top 5 2>/dev/null) || hotspots=""
    [[ -z "$hotspots" ]] && return 0
    echo ""
    echo "## Hotspots (complexity x churn - touch these with extra care)"
    echo ""
    printf '%s\n' "$hotspots"
}

# --- Correction trends -------------------------------------------------------
# What this project's humans keep fixing: do not reintroduce these patterns.
emit_correction_trends() {
    command -v metrics_correction_trends >/dev/null 2>&1 || return 0
    local trends
    trends=$(metrics_correction_trends 2>/dev/null) || trends=""
    [[ -z "$trends" ]] && return 0
    echo ""
    echo "## Correction trends (recently fixed here - do not reintroduce)"
    echo ""
    printf '%s\n' "$trends"
}

echo "# Dispatch Context (generated - do not re-derive any of this)"
emit_doctrine
emit_codemap
emit_hotspots
emit_correction_trends

exit 0
