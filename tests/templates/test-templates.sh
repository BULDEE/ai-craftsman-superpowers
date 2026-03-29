#!/usr/bin/env bash
# =============================================================================
# test-templates.sh — Template syntax and structure validation
#
# Validates all pack templates for:
#   - Required sections (Mission, Context Files)
#   - PHP code blocks: declare(strict_types=1), final class, no setters
#   - TypeScript code blocks: no 'any' type, named exports
#   - Handlebars placeholder consistency
#   - No unresolved placeholders (TODO, TBD, FIXME)
#   - Version sync between plugin.json and marketplace.json
# =============================================================================
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

# =============================================================================
# Section 1: Template file discovery
# =============================================================================
echo "==================================="
echo " Template Validation Tests"
echo "==================================="

SYMFONY_TEMPLATES=()
REACT_TEMPLATES=()

while IFS= read -r f; do
    SYMFONY_TEMPLATES+=("$f")
done < <(find "$ROOT_DIR/symfony-pack/templates" -name "*.template.md" 2>/dev/null | sort)

while IFS= read -r f; do
    REACT_TEMPLATES+=("$f")
done < <(find "$ROOT_DIR/react-pack/templates" -name "*.template.md" 2>/dev/null | sort)

ALL_TEMPLATES=("${SYMFONY_TEMPLATES[@]}" "${REACT_TEMPLATES[@]}")

echo ""
echo "--- Section 1: Template Discovery ---"

if [[ ${#SYMFONY_TEMPLATES[@]} -ge 3 ]]; then
    pass "Symfony pack has ${#SYMFONY_TEMPLATES[@]} templates (expected >= 3)"
else
    fail "Symfony pack has ${#SYMFONY_TEMPLATES[@]} templates (expected >= 3)"
fi

if [[ ${#REACT_TEMPLATES[@]} -ge 3 ]]; then
    pass "React pack has ${#REACT_TEMPLATES[@]} templates (expected >= 3)"
else
    fail "React pack has ${#REACT_TEMPLATES[@]} templates (expected >= 3)"
fi

# Expected template names
for expected in "bounded-context-backend" "crud-api" "event-sourced"; do
    if [[ -f "$ROOT_DIR/symfony-pack/templates/${expected}.template.md" ]]; then
        pass "Symfony template exists: ${expected}"
    else
        fail "Symfony template missing: ${expected}"
    fi
done

for expected in "bounded-context-frontend" "form-heavy" "dashboard-data"; do
    if [[ -f "$ROOT_DIR/react-pack/templates/${expected}.template.md" ]]; then
        pass "React template exists: ${expected}"
    else
        fail "React template missing: ${expected}"
    fi
done

# =============================================================================
# Section 2: Required sections
# =============================================================================
echo ""
echo "--- Section 2: Required Sections ---"

for template in "${ALL_TEMPLATES[@]}"; do
    name=$(basename "$template" .template.md)

    # Must have a top-level heading
    if grep -q "^# " "$template" 2>/dev/null; then
        pass "${name}: has top-level heading"
    else
        fail "${name}: missing top-level heading"
    fi

    # Must have Mission section
    if grep -q "^## Mission" "$template" 2>/dev/null; then
        pass "${name}: has Mission section"
    else
        fail "${name}: missing Mission section"
    fi

    # Must have Context Files section
    if grep -q "^## Context Files" "$template" 2>/dev/null; then
        pass "${name}: has Context Files section"
    else
        fail "${name}: missing Context Files section"
    fi
done

# =============================================================================
# Section 3: PHP code block validation (Symfony templates)
# =============================================================================
echo ""
echo "--- Section 3: PHP Code Block Validation ---"

for template in "${SYMFONY_TEMPLATES[@]}"; do
    name=$(basename "$template" .template.md)

    # Extract PHP code blocks
    php_blocks=$(awk '/^```php$/,/^```$/' "$template" 2>/dev/null)

    if [[ -z "$php_blocks" ]]; then
        warn "${name}: no PHP code blocks found"
        continue
    fi

    # Count PHP code blocks
    block_count=$(echo "$php_blocks" | grep -c "^declare(strict_types=1);" 2>/dev/null || echo "0")
    total_blocks=$(grep -c "^\`\`\`php" "$template" 2>/dev/null || echo "0")

    # Check declare(strict_types=1) in blocks that start with <?php
    php_open_count=$(echo "$php_blocks" | grep -c "<?php" 2>/dev/null || echo "0")
    strict_count=$(echo "$php_blocks" | grep -c "declare(strict_types=1)" 2>/dev/null || echo "0")

    if [[ "$php_open_count" -gt 0 && "$strict_count" -ge "$php_open_count" ]]; then
        pass "${name}: all PHP files have declare(strict_types=1)"
    elif [[ "$php_open_count" -eq 0 ]]; then
        pass "${name}: PHP snippets (no full files)"
    else
        fail "${name}: ${strict_count}/${php_open_count} PHP files have declare(strict_types=1)"
    fi

    # Check final class
    class_count=$(echo "$php_blocks" | grep -cE "^(final )?class " 2>/dev/null || echo "0")
    final_count=$(echo "$php_blocks" | grep -c "^final class\|^final readonly class" 2>/dev/null || echo "0")

    if [[ "$class_count" -gt 0 ]]; then
        if [[ "$final_count" -ge "$class_count" ]]; then
            pass "${name}: all classes are final (${final_count}/${class_count})"
        else
            fail "${name}: not all classes are final (${final_count}/${class_count})"
        fi
    fi

    # Check no public setters
    setter_count=$(echo "$php_blocks" | grep -E "public function set[A-Z]" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$setter_count" -eq 0 ]]; then
        pass "${name}: no public setters"
    else
        fail "${name}: found ${setter_count} public setter(s)"
    fi
done

# =============================================================================
# Section 4: TypeScript code block validation (React templates)
# =============================================================================
echo ""
echo "--- Section 4: TypeScript Code Block Validation ---"

for template in "${REACT_TEMPLATES[@]}"; do
    name=$(basename "$template" .template.md)

    # Extract TS/TSX code blocks
    ts_blocks=$(awk '/^```(tsx?|typescript)$/,/^```$/' "$template" 2>/dev/null)

    if [[ -z "$ts_blocks" ]]; then
        warn "${name}: no TypeScript code blocks found"
        continue
    fi

    # Check no 'any' type (excluding comments and strings)
    any_count=$(echo "$ts_blocks" | grep -E ": any[^a-zA-Z]|<any>|: any$" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$any_count" -eq 0 ]]; then
        pass "${name}: no 'any' types"
    else
        fail "${name}: found ${any_count} 'any' type usage(s)"
    fi

    # Check no default exports
    default_count=$(echo "$ts_blocks" | grep "export default" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$default_count" -eq 0 ]]; then
        pass "${name}: no default exports"
    else
        fail "${name}: found ${default_count} default export(s)"
    fi

    # Check no non-null assertions (exclude !== and !=)
    bang_count=$(echo "$ts_blocks" | grep -E "[a-zA-Z0-9_)]\![^=]" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$bang_count" -eq 0 ]]; then
        pass "${name}: no non-null assertions"
    else
        warn "${name}: found ${bang_count} potential non-null assertion(s)"
    fi
done

# =============================================================================
# Section 5: Handlebars placeholder validation
# =============================================================================
echo ""
echo "--- Section 5: Handlebars Placeholder Consistency ---"

for template in "${ALL_TEMPLATES[@]}"; do
    name=$(basename "$template" .template.md)

    # Extract all {{PLACEHOLDER}} patterns (exclude {{#each}}, {{/each}}, {{else}})
    placeholders=$(grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' "$template" 2>/dev/null | sort -u)

    if [[ -n "$placeholders" ]]; then
        count=$(echo "$placeholders" | wc -l | tr -d ' ')
        pass "${name}: uses ${count} unique Handlebars placeholder(s)"
    else
        warn "${name}: no Handlebars placeholders found"
    fi
done

# =============================================================================
# Section 6: No unresolved TODO/TBD/FIXME
# =============================================================================
echo ""
echo "--- Section 6: No Unresolved Placeholders ---"

for template in "${ALL_TEMPLATES[@]}"; do
    name=$(basename "$template" .template.md)

    # Check for TODO, TBD, FIXME, HACK, XXX (case insensitive, outside of code blocks describing what to avoid)
    unresolved=$(grep -niE "\b(TODO|TBD|FIXME|HACK|XXX)\b" "$template" 2>/dev/null | grep -v "Do NOT\|Anti-Pattern\|avoid\|never\|Don't" || true)

    if [[ -z "$unresolved" ]]; then
        pass "${name}: no unresolved TODO/TBD/FIXME"
    else
        count=$(echo "$unresolved" | wc -l | tr -d ' ')
        fail "${name}: found ${count} unresolved placeholder(s)"
    fi
done

# =============================================================================
# Section 7: Version sync (plugin.json vs marketplace.json)
# =============================================================================
echo ""
echo "--- Section 7: Version Sync ---"

plugin_version=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "")
marketplace_version=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/marketplace.json')).get('version', ''))" 2>/dev/null || echo "")

if [[ -n "$plugin_version" ]]; then
    pass "plugin.json version: ${plugin_version}"
else
    fail "plugin.json missing version field"
fi

if [[ -n "$marketplace_version" ]]; then
    pass "marketplace.json version: ${marketplace_version}"
else
    fail "marketplace.json missing version field"
fi

if [[ -n "$plugin_version" && -n "$marketplace_version" && "$plugin_version" == "$marketplace_version" ]]; then
    pass "Versions in sync: ${plugin_version}"
else
    fail "Version mismatch: plugin=${plugin_version} marketplace=${marketplace_version}"
fi

# Also check craftsman-ci.sh VERSION
ci_version=$(grep '^VERSION=' "$ROOT_DIR/ci/craftsman-ci.sh" 2>/dev/null | head -1 | cut -d'"' -f2)
if [[ -n "$ci_version" && "$ci_version" == "$plugin_version" ]]; then
    pass "craftsman-ci.sh VERSION in sync: ${ci_version}"
else
    fail "craftsman-ci.sh VERSION mismatch: ci=${ci_version} plugin=${plugin_version}"
fi

# =============================================================================
# Section 8: Scaffolder template selection
# =============================================================================
echo ""
echo "--- Section 8: Scaffolder Template Selection ---"

for cmd in entity usecase; do
    cmd_file="$ROOT_DIR/commands/${cmd}.md"
    if [[ -f "$cmd_file" ]]; then
        if grep -q "## Template Selection" "$cmd_file" 2>/dev/null; then
            pass "${cmd}.md: has Template Selection section"
        else
            fail "${cmd}.md: missing Template Selection section"
        fi

        # Check it references all 3 symfony templates
        for tpl in "bounded-context" "crud-api" "event-sourced"; do
            if grep -q "$tpl" "$cmd_file" 2>/dev/null; then
                pass "${cmd}.md: references ${tpl} template"
            else
                fail "${cmd}.md: missing reference to ${tpl} template"
            fi
        done
    else
        fail "${cmd}.md: command file not found"
    fi
done

for cmd in component hook; do
    cmd_file="$ROOT_DIR/commands/${cmd}.md"
    if [[ -f "$cmd_file" ]]; then
        if grep -q "## Template Selection" "$cmd_file" 2>/dev/null; then
            pass "${cmd}.md: has Template Selection section"
        else
            fail "${cmd}.md: missing Template Selection section"
        fi

        # Check it references all 3 react templates
        for tpl in "bounded-context" "form-heavy" "dashboard-data"; do
            if grep -q "$tpl" "$cmd_file" 2>/dev/null; then
                pass "${cmd}.md: references ${tpl} template"
            else
                fail "${cmd}.md: missing reference to ${tpl} template"
            fi
        done
    else
        fail "${cmd}.md: command file not found"
    fi
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==================================="
printf " ${GREEN}Passed:${NC} %d\n" "$PASSED"
printf " ${RED}Failed:${NC} %d\n" "$FAILED"
printf " ${YELLOW}Warnings:${NC} %d\n" "$WARNINGS"
echo "==================================="

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
