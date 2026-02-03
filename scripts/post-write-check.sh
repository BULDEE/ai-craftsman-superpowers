#!/bin/bash
# Post-Write Check Script for Claude Code Hooks
# Validates written files against coding standards

# Read the tool input from stdin (JSON format)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# If no file path, exit silently
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Get file extension
EXT="${FILE_PATH##*.}"

ISSUES_FOUND=0

# PHP file checks
if [ "$EXT" = "php" ]; then
    # Check for strict_types declaration
    if ! grep -q "declare(strict_types=1)" "$FILE_PATH" 2>/dev/null; then
        echo "⚠️  Missing: declare(strict_types=1) in $FILE_PATH"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for final class (excluding interfaces, traits, abstract)
    if grep -q "^class " "$FILE_PATH" 2>/dev/null; then
        if ! grep -q "final class" "$FILE_PATH" 2>/dev/null; then
            if ! grep -qE "(interface|trait|abstract class)" "$FILE_PATH" 2>/dev/null; then
                echo "⚠️  Missing: 'final' keyword on class in $FILE_PATH"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi
    fi

    # Check for public setters
    if grep -qE "public function set[A-Z]" "$FILE_PATH" 2>/dev/null; then
        echo "⚠️  Found: Public setter in $FILE_PATH (use behavioral methods instead)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for new DateTime() (should use Clock abstraction)
    if grep -q "new \\\\DateTime()" "$FILE_PATH" 2>/dev/null; then
        echo "⚠️  Found: new DateTime() in $FILE_PATH (inject Clock abstraction instead)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi

# TypeScript/JavaScript file checks
if [ "$EXT" = "ts" ] || [ "$EXT" = "tsx" ]; then
    # Check for 'any' type
    if grep -qE ": any[^a-zA-Z]|<any>" "$FILE_PATH" 2>/dev/null; then
        echo "⚠️  Found: 'any' type in $FILE_PATH (use proper types or 'unknown')"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for default export
    if grep -q "export default" "$FILE_PATH" 2>/dev/null; then
        echo "⚠️  Found: default export in $FILE_PATH (use named exports)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for non-null assertion
    if grep -qE "[a-zA-Z0-9_]+!" "$FILE_PATH" 2>/dev/null; then
        # Exclude != and !== comparisons
        if grep -qE "[a-zA-Z0-9_]+![^=]" "$FILE_PATH" 2>/dev/null; then
            echo "⚠️  Found: Non-null assertion (!) in $FILE_PATH (handle null explicitly)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
fi

# Summary
if [ $ISSUES_FOUND -gt 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 $ISSUES_FOUND issue(s) found. Consider fixing before commit."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Always exit 0 (warning only, don't block)
exit 0
