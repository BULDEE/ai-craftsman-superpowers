#!/usr/bin/env bash
# =============================================================================
# Pre-Write/Edit Validation Hook for Claude Code
# Validates BEFORE file is written: layer imports, path conventions.
#
# TRIGGERS: PreToolUse for Write and Edit tools
# EXIT CODES: 0 = allow, 2 = block with reason
# =============================================================================
set -uo pipefail

# Fail-open trap: if hook crashes, allow the write
trap 'echo "WARNING: pre-write-check.sh failed at line $LINENO" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
FILE_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

# Exit silently if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Only check source files
EXT="${FILE_PATH##*.}"
case "$EXT" in
    php|ts|tsx) ;;
    *) exit 0 ;;
esac

VIOLATIONS=""
VIOLATION_COUNT=0

add_violation() {
    VIOLATIONS="${VIOLATIONS}$1\n"
    ((VIOLATION_COUNT++)) || true
}

# =============================================================================
# Layer Validation on Content (before write)
# =============================================================================

if config_php_enabled; then
    # PHP: Domain must not import Infrastructure
    if [[ "$FILE_PATH" == *"/Domain/"* ]] && [[ "$EXT" == "php" ]]; then
        if echo "$FILE_CONTENT" | grep -qE "use\s+App\\\\Infrastructure" 2>/dev/null; then
            add_violation "LAYER001: Domain imports Infrastructure - DDD layer violation"
        fi
        if echo "$FILE_CONTENT" | grep -qE "use\s+App\\\\Presentation" 2>/dev/null; then
            add_violation "LAYER002: Domain imports Presentation - DDD layer violation"
        fi
    fi

    # Also check namespace in content (catches when path doesn't contain /Domain/)
    if [[ "$EXT" == "php" ]] && echo "$FILE_CONTENT" | grep -qE "namespace\s+App\\\\Domain" 2>/dev/null; then
        if echo "$FILE_CONTENT" | grep -qE "use\s+App\\\\Infrastructure" 2>/dev/null; then
            # Avoid duplicate if already caught by path check
            if [[ "$FILE_PATH" != *"/Domain/"* ]]; then
                add_violation "LAYER001: Domain imports Infrastructure - DDD layer violation (detected via namespace)"
            fi
        fi
    fi

    # PHP: Application must not import Presentation
    if [[ "$FILE_PATH" == *"/Application/"* ]] && [[ "$EXT" == "php" ]]; then
        if echo "$FILE_CONTENT" | grep -qE "use\s+App\\\\Presentation" 2>/dev/null; then
            add_violation "LAYER003: Application imports Presentation - DDD layer violation"
        fi
    fi

    # PHP: strict_types must be present in class files
    if [[ "$EXT" == "php" ]] && [[ -n "$FILE_CONTENT" ]]; then
        if ! echo "$FILE_CONTENT" | grep -q "declare(strict_types=1)" 2>/dev/null; then
            if echo "$FILE_CONTENT" | grep -qE "(class |interface |trait |enum )" 2>/dev/null; then
                add_violation "PHP001: Missing declare(strict_types=1) in class file"
            fi
        fi
    fi
fi

if config_ts_enabled; then
    # TypeScript: domain must not import infrastructure
    if [[ "$FILE_PATH" == *"/domain/"* ]] && [[ "$EXT" == "ts" || "$EXT" == "tsx" ]]; then
        if echo "$FILE_CONTENT" | grep -qE "from\s+['\"].*infrastructure" 2>/dev/null; then
            add_violation "LAYER001: domain imports infrastructure - layer violation"
        fi
    fi
fi

# =============================================================================
# Auto-fix (ADR-0018): a Write missing only strict_types is corrected in
# place via updatedInput instead of blocking. The violation is still
# surfaced as additionalContext so the correction learning loop keeps its
# signal.
# =============================================================================

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [[ $VIOLATION_COUNT -eq 1 && "$TOOL_NAME" == "Write" && "$EXT" == "php" ]] \
   && [[ "$VIOLATIONS" == PHP001* ]] \
   && echo "$FILE_CONTENT" | head -1 | grep -q "^<?php" 2>/dev/null; then
    FIXED_CONTENT=$(printf '%s\n' "$FILE_CONTENT" | awk 'NR==1 && $0 ~ /^<\?php/ {print; print ""; print "declare(strict_types=1);"; next} {print}')
    echo "$INPUT" | jq --arg content "$FIXED_CONTENT" \
    '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: (.tool_input | .content = $content),
            additionalContext: "PHP001 auto-fixed: declare(strict_types=1) was missing and has been inserted after the <?php tag. Include it yourself in future PHP files."
        }
    }'
    exit 0
fi

# =============================================================================
# Output Decision
# =============================================================================

if [[ $VIOLATION_COUNT -gt 0 ]]; then
    # Check if ANY violation should block (iterate all, not just first)
    local_should_block=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rule="${line%%:*}"
        if config_should_block "$rule"; then
            local_should_block=true
            break
        fi
    done <<< "$(echo -e "$VIOLATIONS")"

    if [[ "$local_should_block" == true ]]; then
        # Human-readable message on stderr (shown in Claude Code UI)
        echo "🚫 BLOCKED by AI Craftsman - ${VIOLATION_COUNT} violation(s) detected before write:" >&2
        while IFS= read -r vline; do
            [[ -n "$vline" ]] && echo "  ✗ $vline" >&2
        done <<< "$(echo -e "$VIOLATIONS")"
        echo "Fix these before writing. Use // craftsman-ignore: <RULE_ID> to suppress." >&2

        # Structured JSON on stdout (consumed by Claude AI)
        jq -n --arg v "$(echo -e "$VIOLATIONS")" \
               --arg c "$VIOLATION_COUNT" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                additionalContext: ("BLOCKED before write: " + $c + " violation(s):\n" + $v + "\nFix the code before writing.")
            }
        }'
        exit 2
    else
        # See session-start.sh: systemMessage is user-facing only, so a warning
        # sent on that channel alone never reaches the model it is meant to steer.
        jq -n --arg v "$(echo -e "$VIOLATIONS")" \
               --arg c "$VIOLATION_COUNT" \
        '(("PRE-WRITE WARNING: " + $c + " issue(s) detected:\n" + $v)) as $body
         | {
            systemMessage: $body,
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                additionalContext: $body
            }
        }'
        exit 0
    fi
fi

exit 0
