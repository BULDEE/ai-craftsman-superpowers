#!/usr/bin/env bash
# =============================================================================
# FileChanged Monitoring Hook for Claude Code
# Lightweight Level 1 regex validation on file changes.
# Complements Write/Edit hooks — covers external changes (IDE, git).
#
# FileChanged is a supported Claude Code hook type (verified 2026-04-04).
# Wired in hooks.json with matcher "*.php|*.ts|*.tsx" and async: true.
#
# TRIGGERS: FileChanged (async)
# EXIT CODES: 0 always (non-blocking, monitoring only)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/metrics-db.sh"
source "${SCRIPT_DIR}/lib/pack-loader.sh"

# Read file path from stdin JSON
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty' 2>/dev/null)

# Exit silently if no file path or file doesn't exist
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Only check source files
EXT="${FILE_PATH##*.}"
case "$EXT" in
    php|ts|tsx) ;;
    *) exit 0 ;;
esac

# Init metrics and pack loader
metrics_init 2>/dev/null || true

FILE_PATTERN=$(metrics_file_pattern "$FILE_PATH")
ISSUES=""
ISSUE_COUNT=0

add_issue() {
    local rule="$1"
    local message="$2"
    ISSUES="${ISSUES}${rule}: ${message}\n"
    ((ISSUE_COUNT++)) || true
    metrics_record_violation "$rule" "$FILE_PATTERN" "info" 0 0 2>/dev/null || true
}

# Provide add_violation/add_warning as aliases for pack validators
# In file-changed context, all violations are non-blocking issues
add_violation() { add_issue "$1" "$2"; }
add_warning() { add_issue "$1" "$2"; }
line_has_ignore() { return 1; }

# Initialize pack loader (sources validators from compatible packs)
pack_loader_init

# Level 1: Pack validators
case "$EXT" in
    php)
        if config_php_enabled; then
            pack_run_validators "$FILE_PATH" "php"
            pack_run_validators "$FILE_PATH" "php_layers"
        fi
        ;;
    ts|tsx)
        if config_ts_enabled; then
            pack_run_validators "$FILE_PATH" "typescript"
            pack_run_validators "$FILE_PATH" "typescript_layers"
        fi
        ;;
esac

# Output only if issues found
if [[ $ISSUE_COUNT -gt 0 ]]; then
    rel_path="${FILE_PATH#"$PWD"/}"
    jq -n --arg fp "$rel_path" --arg issues "$(echo -e "$ISSUES")" --arg count "$ISSUE_COUNT" '{
        systemMessage: ("FileChanged: " + $fp + " — " + $count + " issue(s) detected:\n" + $issues + "Not blocking — use Write/Edit for enforcement.")
    }'
fi

exit 0
