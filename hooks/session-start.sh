#!/usr/bin/env bash
# =============================================================================
# Session Start Hook for Claude Code
# Loads project context and outputs active profile as systemMessage.
#
# TRIGGERS: SessionStart
# EXIT CODES: 0 always (non-blocking, informational)
# =============================================================================
set -uo pipefail

# The Haiku verification subprocess (haiku-verify.sh, `claude -p`) is a
# session to Claude Code and fires this hook. Without this line every
# verification restarted the REAL session's clock and deleted its write and
# violation counters, and on a live database 1460 of 1599 sessions in 30 days
# had no write at all: they were verifiers, not sessions. The recursion guard
# the verifier sets is the signal. The subprocess is also launched with hooks
# disabled; this is the lock on this side of the door.
[[ -n "${CRAFTSMAN_HEADLESS_VERIFY:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/session-files.sh"
INPUT=$(cat 2>/dev/null) || INPUT=""
session_files_bind "$INPUT"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/metrics-db.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"
source "${SCRIPT_DIR}/lib/healthcheck.sh"
source "${SCRIPT_DIR}/lib/routing-table.sh"
source "${SCRIPT_DIR}/lib/hook-events.sh"

_init_packs() {
    pack_loader_init
    pack_sync_symlinks

    local loaded
    loaded=$(pack_loaded)
    if [[ -n "$loaded" ]]; then
        local pack_list
        pack_list=$(echo "$loaded" | tr '\n' ', ' | sed 's/,$//')
        echo "PACKS:${pack_list}"
    else
        echo "PACKS:none"
    fi
}

# Python3 availability check - skip python-dependent features if missing
HAS_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAS_PYTHON3=false

# Init metrics DB (idempotent, non-blocking)
if $HAS_PYTHON3; then
    metrics_init 2>/dev/null || echo "WARNING: Metrics DB init failed" >&2
fi

# Write the canonical session-state path to a stable bridge file so that
# skills running via the Bash tool (where CLAUDE_PLUGIN_DATA is unavailable)
# can find the same state file that hooks use.
# The bridge file is intentionally placed outside the plugin data directory
# so it is independent of the plugin slug and survives renames.
# The bridge is Claude Code's: its skills run in the Bash tool and read it.
# Another host starting later must not repoint it at its own data directory,
# or a Claude skill's set-verified lands where that Claude session's hooks
# never look (review of 421ca76, F6).
_session_host="$CRAFTSMAN_SESSION_HOST"
SESSION_STATE_PATH="${METRICS_DB_DIR:+${METRICS_DB_DIR}/session-state.json}"
_writes_claude_bridge() { [[ "$_session_host" == "claude-code" || "$_session_host" == "unknown" ]]; }
session_files_register
_writes_claude_bridge && { printf '%s' "$SESSION_STATE_PATH" > "${HOME}/.claude/craftsman-session-state-path" 2>/dev/null || true; }

# Same bridge for the metrics database. Without it the reporting skills fall
# back to the plugin-slug-less default and read a database no hook has written
# since the slug changed: /craftsman:metrics reported 114 violations while the
# live database held 14222, and concluded the hooks had stopped writing.
METRICS_DB_PATH="$METRICS_DB"
_writes_claude_bridge && { printf '%s' "$METRICS_DB_PATH" > "${HOME}/.claude/craftsman-metrics-db-path" 2>/dev/null || true; }

# Record session start epoch. SessionEnd input has no duration field
# (only session_id/transcript_path/cwd/reason), so session-metrics.sh
# derives duration and its violation-count window from this marker.
_start_marker=$(session_file session-start-ts)
[[ -n "$_start_marker" ]] && { printf '%s' "$(date +%s)" > "$_start_marker" 2>/dev/null || true; }
# Sessions that ended without a SessionEnd (a crash, a kill) leave their files
# behind; a week later nobody will resume them.
session_files_sweep 7

# The per-session tallies restart with the session, like the timestamp above.
# SessionEnd removes them, but a crash between the two left them in place and
# the next session counted this one's violations as its own: two writes then
# one produced three. The duration is already measured from this line, so
# counting over any other window was incoherent regardless of the crash.
rm -f "$(session_file session-violations)" "$(session_file session-writes)" 2>/dev/null || true

# Generate a self-contained verify wrapper at a well-known path.
# Skills run via the Bash tool without CLAUDE_PLUGIN_ROOT, so they cannot
# locate session_state.py directly. This wrapper bakes in the resolved path
# at session start, making the verify skill a one-liner call.
if _writes_claude_bridge; then
cat > "${HOME}/.claude/craftsman-set-verified.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
exec python3 "${SCRIPT_DIR}/lib/session_state.py" set-verified
WRAPPER
chmod +x "${HOME}/.claude/craftsman-set-verified.sh" 2>/dev/null || true

# Same bridge pattern for the instinct pipeline (ADR-0020): /craftsman:metrics
# runs via the Bash tool without CLAUDE_PLUGIN_ROOT, so bake resolved paths in.
# The project is the git toplevel's physical path, hashed the way the hooks
# hash it (metrics_project_hash): a wrapper that hashed \$PWD answered "no
# instincts" from a subdirectory while SessionStart announced candidates.
cat > "${HOME}/.claude/craftsman-instincts.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
DB="$METRICS_DB"
source "${SCRIPT_DIR}/lib/metrics-db.sh" 2>/dev/null
PROJECT_HASH=\$(metrics_project_hash)
[[ -n "\${CRAFTSMAN_PRINT_PROJECT_HASH:-}" ]] && { printf '%s' "\$PROJECT_HASH"; exit 0; }
CMD="\${1:-candidates}"
shift 2>/dev/null || true
case "\$CMD" in
    approve|reject|global-candidates|promote)
        exec python3 "${SCRIPT_DIR}/lib/instincts.py" "\$CMD" "\$DB" "\$@"
        ;;
    *)
        exec python3 "${SCRIPT_DIR}/lib/instincts.py" "\$CMD" "\$DB" "\$PROJECT_HASH" "\$@"
        ;;
esac
WRAPPER
chmod +x "${HOME}/.claude/craftsman-instincts.sh" 2>/dev/null || true

# Codemap bridge (ADR-0022): cached by content hash of the tracked file list,
# refreshed here and consumed by review skills via dynamic context injection.
cat > "${HOME}/.claude/craftsman-codemap.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
DATA_DIR="${METRICS_DB_DIR}"
source "${SCRIPT_DIR}/lib/metrics-db.sh" 2>/dev/null
PROJECT_HASH=\$(metrics_project_hash)
CACHE="\${DATA_DIR}/codemap-\${PROJECT_HASH}"
HASH_FILE="\${CACHE}.hash"
CURRENT_HASH=\$(git ls-files 2>/dev/null | shasum | cut -d' ' -f1 || echo "no-git")
if [[ -f "\$CACHE" && -f "\$HASH_FILE" && "\$(cat "\$HASH_FILE" 2>/dev/null)" == "\$CURRENT_HASH" ]]; then
    cat "\$CACHE"
    exit 0
fi
mkdir -p "\$DATA_DIR" 2>/dev/null || true
python3 "${SCRIPT_DIR}/lib/codemap.py" "\$PWD" | tee "\$CACHE"
printf '%s' "\$CURRENT_HASH" > "\$HASH_FILE" 2>/dev/null || true
WRAPPER
chmod +x "${HOME}/.claude/craftsman-codemap.sh" 2>/dev/null || true

# Knowledge bridge (ADR-0024): deterministic OKF lookup for skills.
cat > "${HOME}/.claude/craftsman-knowledge.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
exec python3 "${SCRIPT_DIR}/lib/knowledge_lookup.py" "${SCRIPT_DIR}/../knowledge" "\$@"
WRAPPER
chmod +x "${HOME}/.claude/craftsman-knowledge.sh" 2>/dev/null || true

# Dashboard bridge: aggregates the metrics database into a local HTML report.
cat > "${HOME}/.claude/craftsman-dashboard.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
DB="$METRICS_DB"
exec python3 "${SCRIPT_DIR}/lib/dashboard.py" "\$DB" "\$@"
WRAPPER
chmod +x "${HOME}/.claude/craftsman-dashboard.sh" 2>/dev/null || true

# Conventions bridge (ADR-0022): used by /craftsman:setup
cat > "${HOME}/.claude/craftsman-conventions.sh" <<WRAPPER
#!/usr/bin/env bash
set -uo pipefail
exec python3 "${SCRIPT_DIR}/lib/conventions.py" "\${1:-analyze}" "\$PWD" "\${@:2}"
WRAPPER
chmod +x "${HOME}/.claude/craftsman-conventions.sh" 2>/dev/null || true
fi

# The languages present in the working directory, one per line, from the
# entry markers each pack declares (`entry_markers` in pack.yml). The engine
# used to look for composer.json and package.json by name, so a Go, Rust or
# Python project was "other" whatever its pack declared.
# Over the KNOWN registry (every installed pack), which the readers build
# from the manifests on disk: _init_packs runs in a subshell and its registry
# does not reach this shell.
detect_project_languages() {
    local language marker
    while IFS= read -r language; do
        [[ -z "$language" ]] && continue
        while IFS= read -r marker; do
            [[ -n "$marker" && -f "${PWD}/${marker}" ]] || continue
            printf '%s\n' "$language"
            break
        done <<< "$(lang_known_capability "$language" entry_markers)"
    done <<< "$(lang_known_registered)"
}

# The packs whose languages are present, by name. A stack setting that names
# one pack while another pack's language is here is worth a warning; the
# comparison is pack name to pack name, the only vocabulary both sides share.
detect_project_packs() {
    local language
    while IFS= read -r language; do
        [[ -z "$language" ]] && continue
        lang_known_pack_name "$language"
        echo
    done <<< "$(detect_project_languages)" | sort -u | grep -v '^$'
}
STRICTNESS=$(config_strictness)
STACK=$(config_stack)

# Build message. No "PHP rules: ON/OFF" beside the stack any more: since #35 a
# language pack validates its files whatever the stack says, and the banner
# printed OFF for a language whose files were being refused.
PACK_STATUS=$(_init_packs 2>/dev/null || echo "PACKS:error")
DETECTED_PACKS=$(detect_project_packs 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
MSG="Craftsman active | Stack: ${STACK}"
[[ -n "$DETECTED_PACKS" ]] && MSG="${MSG} | Detected: ${DETECTED_PACKS// /,}"
_metrics_status=unavailable
[[ -n "$METRICS_DB" && -f "$METRICS_DB" ]] && _metrics_status=initialized
MSG="${MSG} | Strictness: ${STRICTNESS} | Metrics: ${_metrics_status} | ${PACK_STATUS}"

# Correction learning: trends kept separate so the context budget can drop
# them first (ADR-0021 priority order)
CORRECTION_TRENDS=""
if $HAS_PYTHON3; then
    CORRECTION_TRENDS=$(metrics_correction_trends 2>/dev/null || true)
fi

# Instinct pipeline (ADR-0020): surface pending candidates without injecting
# their content; review happens in /craftsman:metrics.
PENDING_INSTINCTS=""
if $HAS_PYTHON3; then
    _pending=$(python3 "${SCRIPT_DIR}/lib/instincts.py" pending-count \
        "$METRICS_DB" \
        "$(metrics_project_hash)" 2>/dev/null || echo 0)
    if [[ "$_pending" =~ ^[0-9]+$ ]] && [[ "$_pending" -gt 0 ]]; then
        PENDING_INSTINCTS="Instincts: ${_pending} candidate(s) pending review - run /craftsman:metrics"
    fi
fi

# Skills approved before 4.9.1 went to .claude/skills/craftsman-learned/, a
# depth Claude Code never loads (see instincts.py). Name them and the move,
# rather than let an approved instinct stay a file nobody reads.
_LEGACY_LEARNED=0
for _d in "${PWD}/.claude/skills/craftsman-learned"/*/SKILL.md; do
    [[ -f "$_d" ]] && _LEGACY_LEARNED=$((_LEGACY_LEARNED + 1))
done
if [[ "$_LEGACY_LEARNED" -gt 0 ]]; then
    PENDING_INSTINCTS="${PENDING_INSTINCTS:+${PENDING_INSTINCTS} | }${_LEGACY_LEARNED} learned skill(s) at a depth Claude Code does not load: mv .claude/skills/craftsman-learned/* .claude/skills/"
fi

# Config mismatch warning
WARNINGS=""

# Validate hooks.json schema - catch unsupported events early
HOOKS_FILE="${SCRIPT_DIR}/hooks.json"
if [[ -f "$HOOKS_FILE" ]]; then
    SUPPORTED_EVENTS=$(hook_events_python_set)
    _unsupported=$(python3 -c "
import json, sys
supported = ${SUPPORTED_EVENTS}
try:
    data = json.load(open(sys.argv[1]))
    actual = set(data.get('hooks', {}).keys())
    bad = actual - supported
    if bad:
        print(','.join(sorted(bad)))
except Exception:
    pass
" "$HOOKS_FILE" 2>/dev/null)
    if [[ -n "$_unsupported" ]]; then
        WARNINGS="${WARNINGS} | SCHEMA WARNING: hooks.json contains unsupported events: ${_unsupported}. Remove them to avoid CI failures."
    fi
fi

# Every detected pack the stack does not name is worth a warning: a stack set
# to one pack while another pack's language is here is the mismatch. Under
# `fullstack` nothing is excluded, so nothing is reported.
OTHER_PACKS=""
if [[ -n "$DETECTED_PACKS" && "$STACK" != "fullstack" ]]; then
    for _pack in $DETECTED_PACKS; do
        [[ "$_pack" == "$STACK" ]] && continue
        OTHER_PACKS="${OTHER_PACKS:+$OTHER_PACKS, }${_pack}"
    done
    [[ -n "$OTHER_PACKS" ]] && WARNINGS="${WARNINGS} | Warning: config says '${STACK}' but this project carries ${OTHER_PACKS}. Run /craftsman:setup to update."
fi

# Auto-setup gate - check both global and project config
if [[ ! -f "${HOME}/.claude/.craft-config.yml" ]] && [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | First time? Run /craftsman:setup to configure your profile and project. The plugin works with defaults, but setup unlocks full customization."
elif [[ ! -f "${PWD}/.craft-config.yml" ]]; then
    WARNINGS="${WARNINGS} | No project .craft-config.yml found. Run /craftsman:setup to configure this project."
fi

# The global gate is refreshed only when its marker names this install.
# A missing gate is not created, and a gate that names another checkout
# is not adopted: that file is trusted by the host as soon as it exists.
hc_refresh_owned_gate 2>/dev/null || true

# Healthcheck summary
HC_SUMMARY=$(hc_summary 2>/dev/null || echo "Healthcheck: unavailable")
MSG="${MSG} | ${HC_SUMMARY}"

# Command routing table
ROUTING=$(routing_table 2>/dev/null || echo "")

# =============================================================================
# Context budget assembly (ADR-0021). Priority when over budget:
# core status + warnings > pending instincts > routing table > trends.
# Trends are dropped first, then the routing table is truncated.
# =============================================================================
BUDGET=$(config_session_start_max_chars)

assemble_msg() {
    local include_trends="$1" routing_text="$2"
    local out="${MSG}"
    [[ "$include_trends" == "yes" && -n "$CORRECTION_TRENDS" ]] && out="${out} | Learning: ${CORRECTION_TRENDS}"
    [[ -n "$PENDING_INSTINCTS" ]] && out="${out} | ${PENDING_INSTINCTS}"
    out="${out}${WARNINGS}"
    [[ -n "$routing_text" ]] && out="${out}

${routing_text}"
    printf '%s' "$out"
}

FULL=$(assemble_msg "yes" "$ROUTING")
if [[ "${#FULL}" -gt "$BUDGET" ]]; then
    FULL=$(assemble_msg "no" "$ROUTING")
fi
if [[ "${#FULL}" -gt "$BUDGET" ]]; then
    _head_len=$(( ${#FULL} - ${#ROUTING} ))
    _room=$(( BUDGET - _head_len ))
    [[ "$_room" -lt 0 ]] && _room=0
    FULL=$(assemble_msg "no" "$(printf '%s' "$ROUTING" | head -c "$_room")")
fi

# Both channels, because they reach different readers. `systemMessage` is
# defined as a warning shown to the user; only `additionalContext` enters
# Claude's context. Emitting the bootstrap as systemMessage alone printed the
# workshop profile, active packs and correction trends to the terminal and
# nowhere else - so "inject correction trends at session start", the first
# thing this plugin advertises, never reached the model at all.
jq -n --arg msg "$FULL" '{
    systemMessage: $msg,
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $msg
    }
}'

exit 0
