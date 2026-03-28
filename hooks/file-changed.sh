#!/usr/bin/env bash
# =============================================================================
# FileChanged Monitoring Hook for Claude Code
# Lightweight Level 1 regex validation on file changes.
# Complements Write/Edit hooks — covers external changes (IDE, git).
#
# TRIGGERS: FileChanged
# EXIT CODES: 0 always (non-blocking, monitoring only)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/metrics-db.sh"

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

# Init metrics (idempotent)
metrics_init 2>/dev/null || true

FILE_PATTERN=$(metrics_file_pattern "$FILE_PATH")
ISSUES=""
ISSUE_COUNT=0

add_issue() {
    local rule="$1"
    local message="$2"
    ISSUES="${ISSUES}${rule}: ${message}\n"
    ((ISSUE_COUNT++)) || true
    metrics_record_violation "$rule" "$FILE_PATTERN" "warning" 0 0 2>/dev/null || true
}

# Level 1: Regex checks (<50ms, same rules as post-write-check)
if [[ "$EXT" == "php" ]] && config_php_enabled; then
    if ! grep -q "declare(strict_types=1)" "$FILE_PATH" 2>/dev/null; then
        if grep -qE "(class |interface |trait |enum )" "$FILE_PATH" 2>/dev/null; then
            add_issue "PHP001" "Missing declare(strict_types=1)"
        fi
    fi

    if grep -q "^class " "$FILE_PATH" 2>/dev/null; then
        if ! grep -q "final class" "$FILE_PATH" 2>/dev/null; then
            if ! grep -qE "(interface |trait |abstract class )" "$FILE_PATH" 2>/dev/null; then
                add_issue "PHP002" "Class should be final"
            fi
        fi
    fi

    if grep -qE "public function set[A-Z]" "$FILE_PATH" 2>/dev/null; then
        add_issue "PHP003" "Public setter found"
    fi

    if grep -q "new DateTime()" "$FILE_PATH" 2>/dev/null; then
        add_issue "PHP004" "new DateTime() found"
    fi

    # Layer checks for PHP
    if [[ "$FILE_PATH" == *"/Domain/"* ]] || grep -qE "namespace\s+App\\\\Domain" "$FILE_PATH" 2>/dev/null; then
        if grep -qE "use\s+App\\\\Infrastructure" "$FILE_PATH" 2>/dev/null; then
            add_issue "LAYER001" "Domain imports Infrastructure"
        fi
        if grep -qE "use\s+App\\\\Presentation" "$FILE_PATH" 2>/dev/null; then
            add_issue "LAYER002" "Domain imports Presentation"
        fi
    fi
    if [[ "$FILE_PATH" == *"/Application/"* ]] || grep -qE "namespace\s+App\\\\Application" "$FILE_PATH" 2>/dev/null; then
        if grep -qE "use\s+App\\\\Presentation" "$FILE_PATH" 2>/dev/null; then
            add_issue "LAYER003" "Application imports Presentation"
        fi
    fi
fi

if [[ "$EXT" == "ts" || "$EXT" == "tsx" ]] && config_ts_enabled; then
    if grep -qE ": any[^a-zA-Z]|<any>|: any$" "$FILE_PATH" 2>/dev/null; then
        add_issue "TS001" "'any' type found"
    fi

    if grep -q "export default" "$FILE_PATH" 2>/dev/null; then
        add_issue "TS002" "Default export found"
    fi

    if grep -qE "[a-zA-Z0-9_\)]+\![^=\.]" "$FILE_PATH" 2>/dev/null; then
        add_issue "TS003" "Non-null assertion (!) found"
    fi

    if [[ "$FILE_PATH" == *"/domain/"* ]]; then
        if grep -qE "from\s+['\"].*infrastructure" "$FILE_PATH" 2>/dev/null; then
            add_issue "LAYER001" "domain imports infrastructure"
        fi
    fi
fi

# Output only if issues found
if [[ $ISSUE_COUNT -gt 0 ]]; then
    rel_path="${FILE_PATH#$PWD/}"
    jq -n --arg fp "$rel_path" --arg issues "$(echo -e "$ISSUES")" --arg count "$ISSUE_COUNT" '{
        systemMessage: ("FileChanged: " + $fp + " — " + $count + " issue(s) detected:\n" + $issues + "Not blocking — use Write/Edit for enforcement.")
    }'
fi

exit 0
