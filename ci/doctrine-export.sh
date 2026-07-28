#!/usr/bin/env bash
# =============================================================================
# Doctrine Export - render the active rules as agent instruction files
#
# The rules engine stays the single source of truth. Other harnesses (Codex,
# Copilot, Cursor, Gemini, Antigravity) read plain instruction files, so the
# doctrine travels with the repository even where craftsman hooks cannot run.
# Enforcement still happens where it always did: hooks locally, craftsman-ci
# in the pipeline.
#
# Requires: rules_severity() from lib/rules-engine.sh (already sourced by
# craftsman-ci.sh), config_stack(), config_strictness().
# =============================================================================

# Every rule the engine can emit, grouped for reading. The list used to be four
# constants covering 15 of the 38 rules actually enforced, and three of those 15
# described the wrong rule: PHP003 was documented as "private constructor plus
# factory" while it enforces "no public setter", PHP004 as "no setters" while it
# enforces "no new DateTime()", TS002 as "readonly by default" while it enforces
# "no default export". A teammate read one rule here and was blocked by another.
# tests/ci/test-doctrine-export.sh fails when a rule the validators emit has no
# entry below, so the two cannot drift apart again.
#
# Analyser passthrough codes (PHPSTAN*, ESLINT*, DEPTRAC*) are deliberately
# absent: their text is whatever the external tool says, not doctrine.
DOCTRINE_GROUPS="PHP:PHP TypeScript:TS Python:PY Shell:SH Layers:LAYER Persistence:DB Security:SEC Structure:STRUCT Advisory:WARN"

DOCTRINE_RULES_PHP="PHP001 PHP002 PHP003 PHP004 PHP005"
DOCTRINE_RULES_TS="TS001 TS002 TS003"
DOCTRINE_RULES_PY="PY001 PY002 PY003 PY004 PY005"
DOCTRINE_RULES_SH="SH001 SH002 SH003 SH004 SH005"
DOCTRINE_RULES_LAYER="LAYER001 LAYER002 LAYER003 LAYER004"
DOCTRINE_RULES_DB="DB001 DB002 DB003"
DOCTRINE_RULES_SEC="SEC001 SEC002 SEC003"
DOCTRINE_RULES_STRUCT="GOD001 LOC001 NEST001 PARAM001 CTRL001 RATCHET001"
DOCTRINE_RULES_WARN="WARN-PHP001 WARN-TS001 WARN-PY001 WARN-SH001"

_doctrine_rule_text() {
    case "$1" in
        PHP001) echo "declare(strict_types=1) in every PHP file" ;;
        PHP002) echo "every class is final" ;;
        PHP003) echo "no public setter - use behavioral methods" ;;
        PHP004) echo "no new DateTime() - inject a Clock abstraction" ;;
        PHP005) echo "no empty catch block" ;;
        TS001) echo "no any - use a precise type or unknown" ;;
        TS002) echo "no default export - use named exports" ;;
        TS003) echo "no non-null assertion (!) - handle null explicitly" ;;
        PY001) echo "no one or two character names - use descriptive ones" ;;
        PY002) echo "a function past 30 lines is extracted" ;;
        PY003) echo "every public function declares its return type" ;;
        PY004) echo "no bare except - catch the exception you mean" ;;
        PY005) echo "no mutable default argument - default to None and assign" ;;
        SH001) echo "set -u in every executable script" ;;
        SH002) echo "a function past 30 lines is extracted" ;;
        SH003) echo "no single-character variable names outside loop conventions" ;;
        SH004) echo "no eval" ;;
        SH005) echo "quote every variable used in a file operation" ;;
        LAYER001) echo "Domain must not import Infrastructure" ;;
        LAYER002) echo "Domain must not import Presentation" ;;
        LAYER003) echo "Application must not import Presentation" ;;
        LAYER004) echo "no raw SQL or DQL inside Domain - persistence lives behind a repository interface" ;;
        DB001) echo "no SELECT * - name the columns you need" ;;
        DB002) echo "every migration up() has a tested down()" ;;
        DB003) echo "no query inside a loop - batch it or eager-load" ;;
        SEC001) echo "no hardcoded secret - read it from the environment or a vault" ;;
        SEC002) echo "never eval or shell out with a value you did not author" ;;
        SEC003) echo "no SQL built by concatenation or template literal - bind the parameters" ;;
        GOD001) echo "a class spanning too many lines carries too many responsibilities" ;;
        LOC001) echo "a function body past the limit is extracted" ;;
        NEST001) echo "control flow nested three levels deep - use guard clauses" ;;
        PARAM001) echo "more than three parameters - pass an object" ;;
        CTRL001) echo "a Controller performs no persistence - move it into an Application UseCase" ;;
        RATCHET001) echo "structural metrics may improve, never regress" ;;
        WARN-PHP001|WARN-TS001|WARN-PY001) echo "four or more parameters - consider an object" ;;
        WARN-SH001) echo "a function assigns without declaring local" ;;
        *) echo "$1" ;;
    esac
}

_doctrine_emit_group() {
    local title="$1" rules="$2" rule severity
    local emitted=false
    for rule in $rules; do
        severity=$(rules_severity "$rule" 2>/dev/null || echo "block")
        [[ "$severity" == "ignore" ]] && continue
        if [[ "$emitted" == false ]]; then
            printf '\n### %s\n\n' "$title"
            emitted=true
        fi
        printf -- '- **%s** (%s): %s\n' "$rule" "$severity" "$(_doctrine_rule_text "$rule")"
    done
}

_doctrine_header() {
    local stack strictness
    stack=$(config_stack 2>/dev/null || echo "other")
    strictness=$(config_strictness 2>/dev/null || echo "strict")
    cat <<HEADER
<!-- Generated by craftsman-ci export. Do not edit: run 'craftsman-ci export' to regenerate. -->

# Engineering Doctrine

Stack: ${stack} | Enforcement: ${strictness}

These rules are enforced mechanically by the craftsman quality gate (locally on
every write, and in CI on every push). Code that violates a \`block\` rule is
rejected, so writing it costs a round trip.

## Architecture

Dependencies point inward: Domain imports nothing, Application imports Domain,
Infrastructure and Presentation import Domain and Application. Persistence lives
behind a repository interface owned by the Domain and implemented in
Infrastructure.

## Rules
HEADER
}

_doctrine_footer() {
    cat <<'FOOTER'

## Practice

- Design the domain before writing code; model behavior, not data bags.
- Write the failing test first; never modify a test to make it pass.
- Refactor only under a passing suite: run it before and after.
- Never claim completion without the command output that proves it.
- Suppress a rule inline only with `craftsman-ignore: <RULE_ID>` and a reason.
FOOTER
}

_doctrine_body() {
    _doctrine_header
    local pair title key rules
    for pair in $DOCTRINE_GROUPS; do
        title="${pair%%:*}"
        key="${pair##*:}"
        eval "rules=\"\$DOCTRINE_RULES_${key}\""
        _doctrine_emit_group "$title" "$rules"
    done
    _doctrine_footer
}

_doctrine_write_cursor() {
    mkdir -p .cursor/rules
    {
        printf -- '---\ndescription: Craftsman engineering doctrine\nalwaysApply: true\n---\n\n'
        printf '%s\n' "$1"
    } > .cursor/rules/craftsman.mdc
    echo "Created .cursor/rules/craftsman.mdc"
}

# doctrine_export <target> - writes the instruction file(s) for a harness.
doctrine_export() {
    local target="${1:-agents-md}"
    local body
    body=$(_doctrine_body)

    case "$target" in
        agents-md)
            printf '%s\n' "$body" > AGENTS.md
            echo "Created AGENTS.md (read by Codex, Copilot, Cursor, Gemini, and other agents)"
            ;;
        cursor)
            _doctrine_write_cursor "$body"
            ;;
        copilot)
            mkdir -p .github
            printf '%s\n' "$body" > .github/copilot-instructions.md
            echo "Created .github/copilot-instructions.md"
            ;;
        all)
            doctrine_export agents-md
            doctrine_export cursor
            doctrine_export copilot
            ;;
        *)
            echo "Unknown export target: $target. Use: agents-md, cursor, copilot, all" >&2
            return 2
            ;;
    esac
}
