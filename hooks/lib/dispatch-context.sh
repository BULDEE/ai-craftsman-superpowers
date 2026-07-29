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

echo "# Dispatch Context (generated - do not re-derive any of this)"

# --- Resolved doctrine -------------------------------------------------------
# Rendered from the rules engine, so a project .craft-config.yml override is
# reflected here. Directory-level overrides still resolve per-file at write
# time; the hooks remain the enforcement point.
if [[ -f "${PLUGIN_ROOT}/ci/doctrine-export.sh" ]] && command -v rules_severity >/dev/null 2>&1; then
    source "${PLUGIN_ROOT}/ci/doctrine-export.sh" 2>/dev/null || true
    if command -v _doctrine_body >/dev/null 2>&1; then
        _doctrine_body 2>/dev/null || true
    fi
fi

# --- Codemap (cached) --------------------------------------------------------
# Regenerated only when the repository HEAD moved since the cache was written;
# codemap.py itself never caches (ADR-0022), callers do.
CODEMAP_SCRIPT="${LIB_DIR}/codemap.py"
if command -v python3 >/dev/null 2>&1 && [[ -f "$CODEMAP_SCRIPT" ]]; then
    CACHE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"
    PROJECT_KEY=$(pwd | shasum 2>/dev/null | cut -c1-12) || PROJECT_KEY="default"
    CACHE_FILE="${CACHE_DIR}/codemap-${PROJECT_KEY}.md"
    HEAD_REF=$(git rev-parse HEAD 2>/dev/null || echo "no-git")

    CACHED_REF=""
    [[ -f "$CACHE_FILE" ]] && CACHED_REF=$(head -1 "$CACHE_FILE" 2>/dev/null)

    if [[ "$CACHED_REF" == "<!-- ${HEAD_REF} -->" ]]; then
        echo ""
        tail -n +2 "$CACHE_FILE" 2>/dev/null || true
    else
        CODEMAP=$(python3 "$CODEMAP_SCRIPT" . 2>/dev/null | head -40) || CODEMAP=""
        if [[ -n "$CODEMAP" ]]; then
            echo ""
            printf '%s\n' "$CODEMAP"
            mkdir -p "$CACHE_DIR" 2>/dev/null && \
                printf '<!-- %s -->\n%s\n' "$HEAD_REF" "$CODEMAP" > "$CACHE_FILE" 2>/dev/null || true
        fi
    fi
fi

# --- Hotspots ----------------------------------------------------------------
if command -v python3 >/dev/null 2>&1 && [[ -f "${LIB_DIR}/hotspot_analysis.py" ]]; then
    HOTSPOTS=$(python3 "${LIB_DIR}/hotspot_analysis.py" --top 5 2>/dev/null) || HOTSPOTS=""
    if [[ -n "$HOTSPOTS" ]]; then
        echo ""
        echo "## Hotspots (complexity x churn - touch these with extra care)"
        echo ""
        printf '%s\n' "$HOTSPOTS"
    fi
fi

# --- Correction trends -------------------------------------------------------
# What this project's humans keep fixing: do not reintroduce these patterns.
if command -v metrics_correction_trends >/dev/null 2>&1; then
    TRENDS=$(metrics_correction_trends 2>/dev/null) || TRENDS=""
    if [[ -n "$TRENDS" ]]; then
        echo ""
        echo "## Correction trends (recently fixed here - do not reintroduce)"
        echo ""
        printf '%s\n' "$TRENDS"
    fi
fi

exit 0
