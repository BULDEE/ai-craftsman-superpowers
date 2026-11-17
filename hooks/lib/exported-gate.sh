#!/usr/bin/env bash
# =============================================================================
# Step aside for the exported gate (CR-310).
#
# Sourced first by every hook script. It does anything only when a host runs
# the hook from a plugin path (GROK_PLUGIN_ROOT and GROK_HOOK_EVENT set by Grok
# for a plugin hook, CRAFTSMAN_EXPORTED_GATE unset because the export marks its
# own handlers), so Claude Code pays one test. Grok 1.0.62 discovers the
# plugin Claude Code installed and runs its hooks, and runs the exported gate
# too: every hook ran twice, measured 2026-11-17. When a LIVE exported gate is
# there, the hook drains its input and exits 0, so the exported gate, which
# keeps the git guards and failClosed, is the one that judges.
#
# Live means the export's marker names a checkout that still holds the hooks:
# a gate file whose checkout is gone runs nothing, and stepping aside for it
# would leave the host with no gate at all.
# =============================================================================

[[ -n "${GROK_PLUGIN_ROOT:-}" && -n "${GROK_HOOK_EVENT:-}" && -z "${CRAFTSMAN_EXPORTED_GATE:-}" ]] || return 0

_exported_gate_live() { # <gate file>
    [[ -f "$1" ]] || return 1
    local root
    root=$(jq -r '.craftsman.root // empty' "$1" 2>/dev/null)
    [[ -n "$root" && -f "${root}/hooks/pre-write-check.sh" ]]
}

_exported_gate_rel=$(jq -r '.hosts.grok.gate_file // empty' \
    "$(dirname "${BASH_SOURCE[0]}")/../host-capabilities.json" 2>/dev/null)
if [[ -n "$_exported_gate_rel" ]]; then
    for _exported_gate in "${HOME}/${_exported_gate_rel}" "${GROK_WORKSPACE_ROOT:-$PWD}/${_exported_gate_rel}"; do
        _exported_gate_live "$_exported_gate" || continue
        cat >/dev/null 2>&1
        exit 0
    done
fi
unset _exported_gate _exported_gate_rel
