#!/bin/bash
# Bias Detection Script for Claude Code Hooks
# Detects common cognitive biases and warns the user

# Read the prompt from stdin (JSON format from Claude Code)
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "$INPUT")

# If we couldn't parse JSON, use the raw input
if [ -z "$PROMPT" ]; then
    PROMPT="$INPUT"
fi

# Acceleration bias patterns (rushing to code without thinking)
ACCELERATION_PATTERNS="(vite|rapide|rapidement|pas le temps|no time|just do it|code direct|skip|quick|hurry|asap|urgent)"

# Scope creep patterns (adding features beyond scope)
SCOPE_CREEP_PATTERNS="(et aussi|tant qu'on y est|ajoutons|en plus|while we're at it|also add|let's also|and also)"

# Over-optimization patterns (premature abstraction)
OVER_OPT_PATTERNS="(abstraire|généraliser|generalize|abstract|make it configurable|future-proof)"

# Check for acceleration bias
if echo "$PROMPT" | grep -iE "$ACCELERATION_PATTERNS" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  BIAS DETECTED: Acceleration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "You're rushing. Consider:"
    echo "  • What behavior is expected?"
    echo "  • Should we use /craftsman:design first?"
    echo "  • What test would verify this works?"
    echo ""
fi

# Check for scope creep
if echo "$PROMPT" | grep -iE "$SCOPE_CREEP_PATTERNS" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  BIAS DETECTED: Scope Creep"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Adding features beyond scope. Consider:"
    echo "  • Is this in the original requirement?"
    echo "  • Should this be a separate task?"
    echo "  • YAGNI: You Aren't Gonna Need It"
    echo ""
fi

# Check for over-optimization
if echo "$PROMPT" | grep -iE "$OVER_OPT_PATTERNS" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  BIAS DETECTED: Over-Optimization"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Premature abstraction detected. Consider:"
    echo "  • Do we have 3+ use cases for this abstraction?"
    echo "  • Make it work, make it right, THEN make it fast"
    echo "  • Simple concrete code > complex abstraction"
    echo ""
fi

# Always exit 0 (warning only, don't block)
exit 0
