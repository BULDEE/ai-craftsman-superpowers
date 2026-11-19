#!/usr/bin/env bash
# =============================================================================
# Which plugin hooks Codex runs, read from its own trust record (CR-317).
#
# Codex runs a plugin hook only once its exact definition is trusted, keyed by
# its position in hooks.json. Measured on Codex 0.163.0 (2026-11-19): the
# approvals given on the 205717c manifest were never renewed, the handlers
# inserted since moved the git guard, the end-of-turn gate, the dismissal
# guard and the Bash write check onto keys trusted for another definition, and
# 9 of the 19 handlers Codex lists were skipped while the healthcheck said
# "trust is not measured here".
#
# The control is Codex itself: codex-0.163.0-hooks-list.tsv is what its
# app-server hooks/list returned for that manifest under that config.toml.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

FIX="$SCRIPT_DIR/../fixtures/codex-hook-trust"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-codex-trust.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$HOME" "$CLAUDE_PLUGIN_DATA" "$WORK/codex"
cp "$FIX/config.toml" "$WORK/codex/config.toml"
EVENTS=$(jq -r '.hosts.codex.events_loaded | join(",")' "$ROOT_DIR/hooks/host-capabilities.json")

_plugin() { # <dir> <manifest>: a plugin root as Codex installs it
    mkdir -p "$1/.codex-plugin" "$1/hooks"
    printf '{"name":"craftsman","hooks":"./hooks/hooks.json"}\n' > "$1/.codex-plugin/plugin.json"
    cp "$2" "$1/hooks/hooks.json"
    cp "$ROOT_DIR/hooks/host-capabilities.json" "$1/hooks/"
}
_plugin "$WORK/v4.18.0" "$FIX/hooks-v4.18.0.json"
_plugin "$WORK/approved" "$FIX/hooks-205717c.json"
_plugin "$WORK/codex/plugins/cache/another-market/craftsman/9.9.9" "$FIX/hooks-v4.18.0.json"

_same() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then log_pass "$1"; else log_fail "$1" "expected [$2], got [$3]"; fi
}

ROW_STATUS=""
ROW=""
_row() { # <plugin root> <CODEX_HOME>: the write-gate row a Codex session prints
    local out
    out=$(CODEX_HOME="$2" CRAFTSMAN_SESSION_HOST=codex CLAUDE_PLUGIN_ROOT="$1" bash -c '
        source "'"$ROOT_DIR"'/hooks/lib/config.sh"; source "'"$ROOT_DIR"'/hooks/lib/healthcheck.sh"
        hc_check_write_gate
        printf "%s\t%s\t%s\n" "${#_HC_STATUSES[@]}" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}"' 2>/dev/null)
    ROW_STATUS="$(cut -f1,2 <<< "$out")"
    ROW="$(cut -f3 <<< "$out")"
}

echo ""
echo "=== The record read as Codex reads it ==="
OURS=$(python3 "$ROOT_DIR/hooks/lib/codex_hook_trust.py" "$WORK/v4.18.0" "$WORK/codex/config.toml" "$EVENTS" | cut -f1,2 | sort)
CODEX=$(grep -v '^#' "$FIX/codex-0.163.0-hooks-list.tsv" | sort)
if [[ -n "$CODEX" && "$OURS" == "$CODEX" ]]; then
    log_pass "the 19 verdicts are the ones Codex 0.163.0 hooks/list returned: 10 trusted, 4 modified, 5 untrusted"
else
    log_fail "verdicts against Codex hooks/list" "$(diff <(echo "$OURS") <(echo "$CODEX") | head -8 | tr '\n' '|')"
fi
APPROVED=$(python3 "$ROOT_DIR/hooks/lib/codex_hook_trust.py" "$WORK/approved" "$WORK/codex/config.toml" "$EVENTS" | cut -f1 | sort | uniq -c | tr -s ' ')
_same "on the manifest they were given for, all 14 approvals hold" " 14 trusted" "$APPROVED"

echo ""
echo "=== The healthcheck row ==="
_row "$WORK/v4.18.0" "$WORK/codex"
if [[ "$ROW_STATUS" == $'1\twarn' && "$ROW" == "codex: 9 of 19 plugin hooks do not run until reviewed in /hooks: "* \
    && "$ROW" == *"end-of-turn-gate.sh (stop:0:0) changed since approval"* \
    && "$ROW" == *"git-bypass-guard.sh (pre_tool_use:1:0) changed since approval"* \
    && "$ROW" == *"pre-push-verify.sh (pre_tool_use:1:1) never approved"* ]]; then
    log_pass "after the update the row warns and names each hook Codex skips, and why"
else
    log_fail "row after the update" "[$ROW_STATUS] $ROW"
fi

_row "$WORK/approved" "$WORK/codex"
_same "every hook trusted: one ok row" $'1\tok' "$ROW_STATUS"
assert_contains "and it says where trust was read" "$ROW" "14 of 14 plugin hooks trusted in "

cp "$FIX/config.toml" "$WORK/disabled.toml"
printf '\n[hooks.state."craftsman@ai-craftsman-superpowers:hooks/hooks.json:session_start:0:0"]\nenabled = false\n' >> "$WORK/disabled.toml"
mkdir -p "$WORK/codex-disabled" && mv "$WORK/disabled.toml" "$WORK/codex-disabled/config.toml"
_row "$WORK/approved" "$WORK/codex-disabled"
assert_contains "a hook turned off in /hooks is named as disabled" "$ROW" "session-start.sh (session_start:0:0) disabled"

echo ""
echo "=== Whose approvals ==="
# The key carries the marketplace: the cache path Codex installed from wins
# over the [plugins] table, and no approval given under another name counts.
_row "$WORK/codex/plugins/cache/another-market/craftsman/9.9.9" "$WORK/codex"
assert_contains "installed from another marketplace, none of these approvals apply" "$ROW" "19 of 19 plugin hooks do not run"
mkdir -p "$WORK/empty-codex"
_row "$WORK/v4.18.0" "$WORK/empty-codex"
if [[ "$ROW_STATUS" == $'1\twarn' && "$ROW" == *"trust is not measured here"*"/hooks"* ]]; then
    log_pass "no config.toml and no cache layout: the plugin id is unknown, the row says trust is not measured"
else
    log_fail "unknown plugin id" "[$ROW_STATUS] $ROW"
fi

test_summary
