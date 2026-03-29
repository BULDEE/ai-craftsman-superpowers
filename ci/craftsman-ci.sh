#!/usr/bin/env bash
# =============================================================================
# craftsman-ci — CI-compatible quality gate
# Standalone bash CLI that enforces the same rules as post-write-check.sh.
# Works WITHOUT Claude Code installed.
#
# Usage: craftsman-ci [--format json|text] [--config .craft-config.yml] [paths...]
#
# Exit codes:
#   0 = clean (no violations, no warnings)
#   1 = warnings only
#   2 = violations found
# =============================================================================
set -o pipefail

VERSION="2.5.0"

# =============================================================================
# Defaults
# =============================================================================
FORMAT="text"
CONFIG_FILE=""
SCAN_PATHS=()
STRICTNESS="strict"
STACK="fullstack"

# =============================================================================
# Subcommand routing (must come before general argument parsing)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "ci" ]]; then
    shift
    # Parse ci-specific args
    CI_PROVIDER=""
    CI_CONFIG=""
    CI_SCAN_PATHS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider) CI_PROVIDER="$2"; shift 2 ;;
            --config)   CI_CONFIG="$2"; shift 2 ;;
            *)          CI_SCAN_PATHS+=("$1"); shift ;;
        esac
    done

    source "${SCRIPT_DIR}/adapters/adapter.sh"
    # adapter_load sources the provider file but runs in a subshell when
    # captured via $(...), so we call it twice: once to get the name, then
    # source the provider file directly in the current shell.
    CI_PROVIDER=$(adapter_load "${CI_PROVIDER:-}")
    adapter_load "${CI_PROVIDER}" >/dev/null
    echo "craftsman-ci v${VERSION} — CI mode (${CI_PROVIDER})" >&2

    # Build args for adapter_run
    CI_RUN_ARGS=()
    [[ -n "$CI_CONFIG" ]] && CI_RUN_ARGS+=(--config "$CI_CONFIG")
    CI_RUN_ARGS+=("${CI_SCAN_PATHS[@]}")

    local_report="/tmp/craftsman-report-$$.json"
    adapter_run "$local_report" "${CI_RUN_ARGS[@]}"

    adapter_annotate "$local_report"
    adapter_comment "$local_report"
    adapter_exit "$local_report"
    exit_code=$?
    rm -f "$local_report"
    exit "$exit_code"
fi

if [[ "${1:-}" == "init" ]]; then
    shift
    INIT_PROVIDER="github"
    if [[ "${1:-}" == "--provider" ]]; then
        INIT_PROVIDER="${2:-github}"
    fi

    TEMPLATE_DIR="${SCRIPT_DIR}/templates"
    case "$INIT_PROVIDER" in
        github)
            mkdir -p .github/workflows
            cp "$TEMPLATE_DIR/craftsman-quality-gate.yml" .github/workflows/craftsman-quality-gate.yml
            echo "Created .github/workflows/craftsman-quality-gate.yml"
            ;;
        gitlab)
            cp "$TEMPLATE_DIR/.gitlab-ci.craftsman.yml" .gitlab-ci.craftsman.yml
            echo "Created .gitlab-ci.craftsman.yml"
            echo "Include in your .gitlab-ci.yml: include: '.gitlab-ci.craftsman.yml'"
            ;;
        bitbucket)
            if [[ -f "bitbucket-pipelines.yml" ]]; then
                echo "bitbucket-pipelines.yml already exists. Merge manually from:"
                echo "  $TEMPLATE_DIR/bitbucket-pipelines.craftsman.yml"
            else
                cp "$TEMPLATE_DIR/bitbucket-pipelines.craftsman.yml" bitbucket-pipelines.yml
                echo "Created bitbucket-pipelines.yml"
            fi
            ;;
        jenkins)
            cp "$TEMPLATE_DIR/Jenkinsfile.craftsman" Jenkinsfile.craftsman
            echo "Created Jenkinsfile.craftsman"
            ;;
        *)
            echo "Unknown provider: $INIT_PROVIDER. Use: github, gitlab, bitbucket, jenkins" >&2
            exit 2
            ;;
    esac
    exit 0
fi

# =============================================================================
# Argument parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
craftsman-ci v${VERSION} — Craftsman Quality Gate

Usage:
  craftsman-ci [--format json|text] [--config FILE] [paths...]
  craftsman-ci ci [--provider github|gitlab|bitbucket|generic] [--config FILE] [paths...]
  craftsman-ci init [--provider github|gitlab|bitbucket|jenkins]

Subcommands:
  ci        Run full CI adapter lifecycle (scan, annotate, comment, exit)
  init      Generate CI template for the specified provider

Options:
  --format json|text    Output format (default: text)
  --config FILE         Path to .craft-config.yml (default: auto-detect)
  --provider PROVIDER   CI provider (ci: auto-detect, init: github)
  paths...              Paths to scan (default: src/)

Exit codes:
  0  Clean — no violations, no warnings
  1  Warnings only
  2  Violations found
EOF
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
        *)
            SCAN_PATHS+=("$1")
            shift
            ;;
    esac
done

# =============================================================================
# Rules engine integration (optional — plugin context only)
# =============================================================================
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Source rules engine if available (plugin context)
if [[ -f "$PLUGIN_ROOT/hooks/lib/rules-engine.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/rules-engine.sh"
    RULES_ENGINE_AVAILABLE=true
else
    RULES_ENGINE_AVAILABLE=false
fi

# Load pack-specific rules if packs directory exists
if [[ -d "$PLUGIN_ROOT/packs" ]]; then
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
    source "${PLUGIN_ROOT}/hooks/lib/pack-loader.sh" 2>/dev/null || true
    pack_loader_init 2>/dev/null || true
fi

# Default scan path
if [[ ${#SCAN_PATHS[@]} -eq 0 ]]; then
    SCAN_PATHS=("src/")
fi

# =============================================================================
# Config resolution (mirrors lib/config.sh but self-contained)
# =============================================================================
_parse_yml_value() {
    local key="$1"
    local file="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"
}

_resolve_config() {
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
        # Use rules engine for config resolution (plugin context)
        local project_dir="$PWD"
        local global_dir="${HOME:-}"

        rules_init "$project_dir" "$global_dir"

        # If --config was passed explicitly, feed it to the rules engine
        # (rules_init only looks for .craft-config.yml by convention name)
        if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
            _rules_parse_config "$CONFIG_FILE" "project"
        fi

        # Sync STRICTNESS from engine
        STRICTNESS="$_RULES_STRICTNESS"

        # Stack: rules engine doesn't manage stack, so parse it ourselves
        local config_path=""
        if [[ -n "$CONFIG_FILE" ]]; then
            config_path="$CONFIG_FILE"
        elif [[ -f "$PWD/.craft-config.yml" ]]; then
            config_path="$PWD/.craft-config.yml"
        fi

        if [[ -n "$config_path" && -f "$config_path" ]]; then
            local yml_stack
            yml_stack=$(_parse_yml_value "stack" "$config_path")
            [[ -n "$yml_stack" ]] && STACK="$yml_stack"
        fi

        # Env var overrides
        [[ -n "${CLAUDE_PLUGIN_OPTION_strictness:-}" ]] && STRICTNESS="$CLAUDE_PLUGIN_OPTION_strictness"
        [[ -n "${CLAUDE_PLUGIN_OPTION_stack:-}" ]] && STACK="$CLAUDE_PLUGIN_OPTION_stack"
    else
        # Standalone mode: self-contained config parsing
        local config_path=""

        if [[ -n "$CONFIG_FILE" ]]; then
            config_path="$CONFIG_FILE"
        elif [[ -f "$PWD/.craft-config.yml" ]]; then
            config_path="$PWD/.craft-config.yml"
        fi

        if [[ -n "$config_path" && -f "$config_path" ]]; then
            local yml_strictness yml_stack
            yml_strictness=$(_parse_yml_value "strictness" "$config_path")
            yml_stack=$(_parse_yml_value "stack" "$config_path")

            [[ -n "$yml_strictness" ]] && STRICTNESS="$yml_strictness"
            [[ -n "$yml_stack" ]] && STACK="$yml_stack"
        fi

        # Env var overrides (same as hooks)
        [[ -n "${CLAUDE_PLUGIN_OPTION_strictness:-}" ]] && STRICTNESS="$CLAUDE_PLUGIN_OPTION_strictness"
        [[ -n "${CLAUDE_PLUGIN_OPTION_stack:-}" ]] && STACK="$CLAUDE_PLUGIN_OPTION_stack"
    fi
}

_php_enabled() {
    case "$STACK" in
        symfony|fullstack) return 0 ;;
        *) return 1 ;;
    esac
}

_ts_enabled() {
    case "$STACK" in
        react|fullstack) return 0 ;;
        *) return 1 ;;
    esac
}

_should_block() {
    local rule="$1"
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
        local sev
        sev=$(rules_severity "$rule")
        [[ "$sev" == "block" ]]
    else
        # Standalone fallback logic
        case "$rule" in
            WARN*|PHP005) return 1 ;;
        esac
        case "$STRICTNESS" in
            strict)   return 0 ;;
            moderate) [[ "$rule" == LAYER* ]] && return 0; return 1 ;;
            relaxed)  return 1 ;;
            *)        return 0 ;;
        esac
    fi
}

# =============================================================================
# Violation storage
# Store violations in parallel arrays to avoid delimiter collisions.
# =============================================================================
V_FILES=()
V_LINES=()
V_RULES=()
V_MESSAGES=()
V_SEVERITIES=()

W_FILES=()
W_LINES=()
W_RULES=()
W_MESSAGES=()
W_SEVERITIES=()

FILES_SCANNED=0

_add_violation() {
    local file="$1"
    local line="$2"
    local rule="$3"
    local message="$4"

    if _should_block "$rule"; then
        V_FILES+=("$file")
        V_LINES+=("$line")
        V_RULES+=("$rule")
        V_MESSAGES+=("$message")
        V_SEVERITIES+=("error")
    else
        W_FILES+=("$file")
        W_LINES+=("$line")
        W_RULES+=("$rule")
        W_MESSAGES+=("$message")
        W_SEVERITIES+=("warning")
    fi
}

# =============================================================================
# Line number helpers
# =============================================================================
_find_line() {
    local file="$1"
    local pattern="$2"
    grep -n "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "0"
}

_find_line_e() {
    local file="$1"
    local pattern="$2"
    grep -nE "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "0"
}

# =============================================================================
# PHP Rules (mirrors post-write-check.sh exactly)
# =============================================================================
validate_php() {
    local file="$1"

    # PHP001: declare(strict_types=1) required
    if ! grep -q "declare(strict_types=1)" "$file" 2>/dev/null; then
        _add_violation "$file" "1" "PHP001" "Missing declare(strict_types=1)"
    fi

    # PHP002: Classes must be final (except interface/trait/abstract)
    if grep -q "^class " "$file" 2>/dev/null; then
        if ! grep -q "final class" "$file" 2>/dev/null; then
            if ! grep -qE "(interface |trait |abstract class )" "$file" 2>/dev/null; then
                local ln
                ln=$(_find_line_e "$file" "^class ")
                _add_violation "$file" "$ln" "PHP002" "Class should be final"
            fi
        fi
    fi

    # PHP003: No public setters
    local ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE "public function set[A-Z]" 2>/dev/null; then
            if ! echo "$line" | grep -qE "craftsman-ignore:\s*no-setter" 2>/dev/null; then
                _add_violation "$file" "$ln_num" "PHP003" "Public setter found — use behavioral methods"
            fi
        fi
    done < "$file"

    # PHP004: No new DateTime()
    if grep -q "new DateTime()" "$file" 2>/dev/null || grep -q 'new \\DateTime()' "$file" 2>/dev/null; then
        local ln
        ln=$(grep -n "new DateTime()" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
        [[ "$ln" == "0" ]] && ln=$(grep -n 'new \\DateTime()' "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
        _add_violation "$file" "$ln" "PHP004" "new DateTime() found — inject Clock instead"
    fi

    # PHP005: No empty catch blocks (always a warning via _should_block)
    if grep -A1 "catch" "$file" 2>/dev/null | grep -qE "^\s*\}\s*$" 2>/dev/null; then
        local ln
        ln=$(_find_line_e "$file" "catch")
        _add_violation "$file" "$ln" "PHP005" "Possible empty catch block"
    fi

    # WARN-PHP001: Max 3 parameters (always warning)
    if grep -qE "function\s+\w+\(([^,]+,){3,}" "$file" 2>/dev/null; then
        local ln
        ln=$(_find_line_e "$file" "function\s+\w+\(([^,]+,){3,}")
        _add_violation "$file" "$ln" "WARN-PHP001" "Method with 4+ parameters — consider refactoring to object"
    fi
}

# =============================================================================
# TypeScript Rules (mirrors post-write-check.sh exactly)
# =============================================================================
validate_typescript() {
    local file="$1"

    # TS001: No 'any' type (check per line for craftsman-ignore)
    local ln_num=0
    while IFS= read -r line; do
        ln_num=$((ln_num + 1))
        if echo "$line" | grep -qE ": any[^a-zA-Z]|<any>|: any$" 2>/dev/null; then
            if ! echo "$line" | grep -qE "craftsman-ignore:\s*no-any" 2>/dev/null; then
                _add_violation "$file" "$ln_num" "TS001" "'any' type found — use proper types or 'unknown'"
            fi
        fi
    done < "$file"

    # TS002: No default exports
    if grep -q "export default" "$file" 2>/dev/null; then
        local ln
        ln=$(grep -n "export default" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
        _add_violation "$file" "$ln" "TS002" "Default export found — use named exports"
    fi

    # TS003: No non-null assertion (!) — exclude != and !==
    if grep -qE "[a-zA-Z0-9_\)]+\![^=\.]" "$file" 2>/dev/null; then
        local ln
        ln=$(_find_line_e "$file" "[a-zA-Z0-9_\)]+\![^=\.]")
        _add_violation "$file" "$ln" "TS003" "Non-null assertion (!) found — handle null explicitly"
    fi

    # WARN-TS001: Max 3 parameters (always warning)
    if grep -qE "(function\s+\w+|=>)\s*\(([^,]+,){3,}" "$file" 2>/dev/null; then
        local ln
        ln=$(_find_line_e "$file" "(function\s+\w+|=>)\s*\(([^,]+,){3,}")
        _add_violation "$file" "$ln" "WARN-TS001" "Function with 4+ parameters — consider refactoring to object"
    fi
}

# =============================================================================
# Layer Rules (mirrors post-write-check.sh exactly)
# =============================================================================
validate_layers() {
    local file="$1"
    local ext="${file##*.}"

    local is_domain=false
    local is_application=false
    local is_domain_ts=false

    if [[ "$file" == *"/Domain/"* ]] || grep -qE "namespace\s+App\\\\Domain" "$file" 2>/dev/null; then
        is_domain=true
    fi
    if [[ "$file" == *"/Application/"* ]] || grep -qE "namespace\s+App\\\\Application" "$file" 2>/dev/null; then
        is_application=true
    fi
    if [[ "$file" == *"/domain/"* ]]; then
        is_domain_ts=true
    fi

    # Domain must not import Infrastructure
    if [[ "$is_domain" == true ]] && [[ "$ext" == "php" ]]; then
        if grep -qE "use\s+App\\\\Infrastructure" "$file" 2>/dev/null; then
            local ln
            ln=$(_find_line_e "$file" "use\s+App\\\\Infrastructure")
            _add_violation "$file" "$ln" "LAYER001" "Domain imports Infrastructure — DDD layer violation"
        fi
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            local ln
            ln=$(_find_line_e "$file" "use\s+App\\\\Presentation")
            _add_violation "$file" "$ln" "LAYER002" "Domain imports Presentation — DDD layer violation"
        fi
    fi

    # Application must not import Presentation
    if [[ "$is_application" == true ]] && [[ "$ext" == "php" ]]; then
        if grep -qE "use\s+App\\\\Presentation" "$file" 2>/dev/null; then
            local ln
            ln=$(_find_line_e "$file" "use\s+App\\\\Presentation")
            _add_violation "$file" "$ln" "LAYER003" "Application imports Presentation — DDD layer violation"
        fi
    fi

    # TypeScript: domain must not import infrastructure
    if [[ "$is_domain_ts" == true ]] && [[ "$ext" == "ts" || "$ext" == "tsx" ]]; then
        if grep -qE "from\s+['\"].*infrastructure" "$file" 2>/dev/null; then
            local ln
            ln=$(_find_line_e "$file" "from\s+['\"].*infrastructure")
            _add_violation "$file" "$ln" "LAYER001" "domain imports infrastructure — layer violation"
        fi
    fi
}

# =============================================================================
# File scanner
# =============================================================================
scan_file() {
    local file="$1"
    local ext="${file##*.}"

    case "$ext" in
        php)
            _php_enabled || return 0
            validate_php "$file"
            validate_layers "$file"
            ;;
        ts|tsx)
            _ts_enabled || return 0
            validate_typescript "$file"
            validate_layers "$file"
            ;;
        *)
            return 0
            ;;
    esac

    # Custom rules from rules engine (plugin context only)
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
        local language=""
        case "$ext" in
            php) language="php" ;;
            ts|tsx) language="typescript" ;;
        esac
        if [[ -n "$language" ]]; then
            local custom_rules
            custom_rules=$(rules_custom_list "$language")
            while IFS= read -r rule_id; do
                [[ -z "$rule_id" ]] && continue
                local pattern msg ln_num=0
                pattern=$(rules_pattern "$rule_id")
                msg=$(rules_message "$rule_id")
                [[ -z "$pattern" ]] && continue
                while IFS= read -r fline; do
                    ln_num=$((ln_num + 1))
                    if echo "$fline" | grep -qE "$pattern" 2>/dev/null; then
                        _add_violation "$file" "$ln_num" "$rule_id" "$msg"
                        break
                    fi
                done < "$file"
            done <<< "$custom_rules"
        fi
    fi

    FILES_SCANNED=$((FILES_SCANNED + 1))
}

scan_paths() {
    local path
    for path in "${SCAN_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            scan_file "$path"
        elif [[ -d "$path" ]]; then
            while IFS= read -r file; do
                scan_file "$file"
            done < <(find "$path" -type f \( -name "*.php" -o -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | sort)
        fi
    done
}

# =============================================================================
# Output: text format
# =============================================================================
output_text() {
    local total_violations=${#V_FILES[@]}
    local total_warnings=${#W_FILES[@]}

    echo "craftsman-ci v${VERSION} — Quality Gate"
    echo "==================================="
    echo "Config: ${STRICTNESS}, ${STACK}"
    echo ""

    if [[ $total_violations -eq 0 && $total_warnings -eq 0 ]]; then
        echo "No issues found in ${FILES_SCANNED} file(s)."
        return
    fi

    # Print violations grouped by file
    local current_file=""
    local i

    for i in "${!V_FILES[@]}"; do
        local file="${V_FILES[$i]}"
        local line="${V_LINES[$i]}"
        local rule="${V_RULES[$i]}"
        local message="${V_MESSAGES[$i]}"
        local severity="${V_SEVERITIES[$i]}"

        if [[ "$file" != "$current_file" ]]; then
            [[ -n "$current_file" ]] && echo ""
            echo "$file"
            current_file="$file"
        fi
        printf "  %s:0  %-8s  %-55s  %s\n" "$line" "$severity" "$message" "$rule"
    done

    for i in "${!W_FILES[@]}"; do
        local file="${W_FILES[$i]}"
        local line="${W_LINES[$i]}"
        local rule="${W_RULES[$i]}"
        local message="${W_MESSAGES[$i]}"
        local severity="${W_SEVERITIES[$i]}"

        if [[ "$file" != "$current_file" ]]; then
            [[ -n "$current_file" ]] && echo ""
            echo "$file"
            current_file="$file"
        fi
        printf "  %s:0  %-8s  %-55s  %s\n" "$line" "$severity" "$message" "$rule"
    done

    echo ""
    if [[ $total_violations -gt 0 ]]; then
        echo "x ${total_violations} violation(s), ${total_warnings} warning(s) in ${FILES_SCANNED} file(s)"
    else
        echo "! 0 violations, ${total_warnings} warning(s) in ${FILES_SCANNED} file(s)"
    fi
}

# =============================================================================
# Output: JSON format
# =============================================================================
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    echo "$s"
}

output_json() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

    local total_violations=${#V_FILES[@]}
    local total_warnings=${#W_FILES[@]}

    # Build violations JSON array
    local violations_json=""
    local first=true
    local i

    for i in "${!V_FILES[@]}"; do
        local file msg
        file=$(_json_escape "${V_FILES[$i]}")
        msg=$(_json_escape "${V_MESSAGES[$i]}")
        if [[ "$first" != "true" ]]; then
            violations_json="${violations_json},"
        fi
        violations_json="${violations_json}
    {\"rule\":\"${V_RULES[$i]}\",\"file\":\"${file}\",\"line\":${V_LINES[$i]},\"message\":\"${msg}\",\"severity\":\"critical\"}"
        first=false
    done

    for i in "${!W_FILES[@]}"; do
        local file msg
        file=$(_json_escape "${W_FILES[$i]}")
        msg=$(_json_escape "${W_MESSAGES[$i]}")
        if [[ "$first" != "true" ]]; then
            violations_json="${violations_json},"
        fi
        violations_json="${violations_json}
    {\"rule\":\"${W_RULES[$i]}\",\"file\":\"${file}\",\"line\":${W_LINES[$i]},\"message\":\"${msg}\",\"severity\":\"warning\"}"
        first=false
    done

    cat <<EOF
{
  "version": "${VERSION}",
  "timestamp": "${timestamp}",
  "config": {
    "strictness": "${STRICTNESS}",
    "stack": "${STACK}"
  },
  "summary": {
    "files_scanned": ${FILES_SCANNED},
    "violations": ${total_violations},
    "warnings": ${total_warnings}
  },
  "violations": [${violations_json}
  ]
}
EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    _resolve_config
    scan_paths

    case "$FORMAT" in
        json)  output_json ;;
        text)  output_text ;;
        *)
            echo "Unknown format: $FORMAT. Use json or text." >&2
            exit 2
            ;;
    esac

    local total_violations=${#V_FILES[@]}
    local total_warnings=${#W_FILES[@]}

    if [[ $total_violations -gt 0 ]]; then
        exit 2
    elif [[ $total_warnings -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main
