#!/usr/bin/env bash
# =============================================================================
# craftsman-ci - CI-compatible quality gate
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

VERSION="4.8.1"

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
    echo "craftsman-ci v${VERSION} - CI mode (${CI_PROVIDER})" >&2

    # Build args for adapter_run
    CI_RUN_ARGS=()
    [[ -n "$CI_CONFIG" ]] && CI_RUN_ARGS+=(--config "$CI_CONFIG")
    CI_RUN_ARGS+=("${CI_SCAN_PATHS[@]}")

    # mktemp, not PID: a predictable name in shared /tmp lets a co-tenant on a
    # CI runner pre-create or race the file that decides the gate result.
    local_report=$(mktemp "${TMPDIR:-/tmp}/craftsman-report-XXXXXX") || local_report="/tmp/craftsman-report-$$.json"
    adapter_run "$local_report" "${CI_RUN_ARGS[@]}"

    adapter_annotate "$local_report"
    adapter_comment "$local_report"
    adapter_exit "$local_report"
    exit_code=$?
    rm -f "$local_report"
    exit "$exit_code"
fi

if [[ "${1:-}" == "export" ]]; then
    shift
    EXPORT_TARGET="agents-md"
    if [[ "${1:-}" == "--target" ]]; then
        EXPORT_TARGET="${2:-agents-md}"
    fi
    # The doctrine is rendered FROM the rules engine, so it must be resolved
    # first: without it every rule falls back to its default severity and the
    # exported files would contradict what the gate actually enforces.
    EXPORT_PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
    if [[ -f "$EXPORT_PLUGIN_ROOT/hooks/lib/config.sh" ]]; then
        source "$EXPORT_PLUGIN_ROOT/hooks/lib/config.sh"
    fi
    if [[ -f "$EXPORT_PLUGIN_ROOT/hooks/lib/rules-engine.sh" ]]; then
        source "$EXPORT_PLUGIN_ROOT/hooks/lib/rules-engine.sh"
        rules_init "$PWD" "${HOME:-}" 2>/dev/null || true
    fi
    # Rule ids, wording and grouping live in the rule registry, which the pack
    # loader builds. Without this the Rules section renders empty, which reads
    # as "nothing is enforced".
    if [[ -f "$EXPORT_PLUGIN_ROOT/hooks/lib/pack-loader.sh" ]]; then
        source "$EXPORT_PLUGIN_ROOT/hooks/lib/pack-loader.sh"
        pack_loader_init 2>/dev/null || true
    fi
    source "${SCRIPT_DIR}/doctrine-export.sh"
    doctrine_export "$EXPORT_TARGET"
    exit $?
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
craftsman-ci v${VERSION} - Craftsman Quality Gate

Usage:
  craftsman-ci [--format json|text] [--config FILE] [paths...]
  craftsman-ci ci [--provider github|gitlab|bitbucket|generic] [--config FILE] [paths...]
  craftsman-ci init [--provider github|gitlab|bitbucket|jenkins]
  craftsman-ci export [--target agents-md|cursor|copilot|all]

Subcommands:
  ci        Run full CI adapter lifecycle (scan, annotate, comment, exit)
  init      Generate CI template for the specified provider
  export    Render the active rules as agent instruction files (AGENTS.md and friends)

Options:
  --format json|text    Output format (default: text)
  --config FILE         Path to .craft-config.yml (default: auto-detect)
  --provider PROVIDER   CI provider (ci: auto-detect, init: github)
  paths...              Paths to scan (default: src/)

Exit codes:
  0  Clean - no violations, no warnings
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
# Shared library loading (single source of truth with hooks)
# =============================================================================
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Provide defaults for Claude Code-specific env vars (standalone mode)
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}"
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/craftsman}"

# Source shared libraries if available (plugin context)
PACKS_AVAILABLE=false
RULES_ENGINE_AVAILABLE=false
SA_AVAILABLE=false

if [[ -f "$PLUGIN_ROOT/hooks/lib/config.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/config.sh"
fi

if [[ -f "$PLUGIN_ROOT/hooks/lib/rules-engine.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/rules-engine.sh"
    RULES_ENGINE_AVAILABLE=true
fi

if [[ -f "$PLUGIN_ROOT/hooks/lib/pack-loader.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/pack-loader.sh"
    PACKS_AVAILABLE=true
fi

if [[ -f "$PLUGIN_ROOT/hooks/lib/static-analysis.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/static-analysis.sh"
    SA_AVAILABLE=true
fi

# Level precedence is the same arbitration in both front-ends. Resolving it in
# one only would put the pipeline and the editor in disagreement on a project
# whose analysers are installed: green locally, red in CI, on a rule neither of
# them decided differently.
PRECEDENCE_AVAILABLE=false
if [[ -f "$PLUGIN_ROOT/hooks/lib/precedence.sh" ]]; then
    source "$PLUGIN_ROOT/hooks/lib/precedence.sh"
    PRECEDENCE_AVAILABLE=true
fi

# Init packs (discovers and sources pack validators + SA tools)
if [[ "$PACKS_AVAILABLE" == true && -d "$PLUGIN_ROOT/packs" ]]; then
    pack_loader_init 2>/dev/null || true
fi

# Default scan paths. "src/" alone was not a default, it was an assumption: a
# Laravel app/, a monorepo packages/, a Next.js app/ matched nothing, and the
# pipeline then reported clean having opened no file at all. Every common
# source root that actually exists is scanned; main() refuses to pass on an
# empty scan, so a layout not listed here fails loudly instead of silently.
if [[ ${#SCAN_PATHS[@]} -eq 0 ]]; then
    DEFAULT_SCAN_USED=true
    for _candidate in src app lib libs packages apps; do
        [[ -d "$_candidate" ]] && SCAN_PATHS+=("$_candidate/")
    done
    [[ ${#SCAN_PATHS[@]} -eq 0 ]] && SCAN_PATHS=(".")
fi

# =============================================================================
# Config resolution (mirrors lib/config.sh but self-contained)
# =============================================================================
_parse_yml_value() {
    local key="$1"
    local file="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"
}

# craftsman-ignore: SH002 - config resolution is inherently sequential, splitting would reduce readability
_resolve_config() {
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
        # Use rules engine for config resolution (plugin context)
        local project_dir="$PWD"
        local global_dir="${HOME:-}"

        # stderr is suppressed here for the same reason it is on pack_loader_init
        # and sa_analyze_file: the adapters redirect this command's stderr into
        # the JSON report file, so a single warning makes the report unparseable.
        # rules-engine warns on any malformed custom rule, and .craft-config.yml
        # is supplied by the repository under audit - so leaving stderr on let a
        # pull request corrupt its own report and take the gate green with it.
        rules_init "$project_dir" "$global_dir" 2>/dev/null

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

# block|warn|ignore for this rule on this file, the same three values the hook
# resolves. It used to be a boolean, which collapsed "ignore" into "warn": a
# directory that had switched a rule off still had every finding printed in the
# pipeline while the hook stayed silent on the same file.
_severity_for() {
    local rule="$1" file="${2:-}"
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
        # rules_severity_for_file, not rules_severity: the hooks honour a
        # directory-level .craft-rules.yml and CI did not, so a directory a
        # team had deliberately relaxed still failed the pipeline. That is the
        # drift this pipeline exists to not have.
        if [[ -n "$file" ]]; then
            # Absolute, because the walk up to the project root is what makes a
            # directory override apply. CI is handed paths relative to the
            # working directory, and a relative walk stops at "." without ever
            # reaching the root that holds the override.
            local abs_file="$file"
            [[ "$abs_file" != /* ]] && abs_file="$PWD/$file"
            rules_severity_for_file "$abs_file" "$rule"
        else
            rules_severity "$rule"
        fi
        return 0
    fi

    # Standalone fallback, used only when the rules engine could not be
    # sourced. This list must match _rules_is_advisory in
    # hooks/lib/rules-engine.sh; tests/ci/test-craftsman-ci.sh fails when
    # the two diverge.
    case "$rule" in
        WARN*|PHP005|NEST001|LOC001|GOD001|PARAM001|CTRL001|RATCHET001) echo "warn"; return 0 ;;
        TS002|TS003|PHP003) echo "warn"; return 0 ;;
        DB001|DB002|DB003|PY003|SH001|SH003|SH005) echo "warn"; return 0 ;;
    esac
    case "$STRICTNESS" in
        strict)   echo "block" ;;
        moderate) [[ "$rule" == LAYER* || "$rule" == SEC* ]] && echo "block" || echo "warn" ;;
        relaxed)  echo "warn" ;;
        *)        echo "block" ;;
    esac
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
FILES_DISCOVERED=0
FIND_PREDICATE=()

# Same funnel and same arbitration as the hook's add_violation: a finding a
# higher level claims is HELD here too, and scan_file flushes it once the
# analysers have had their say on that file.
#
# precedence.sh is optional (PRECEDENCE_AVAILABLE); with no library there is no
# deferral, so every Level 1 rule reports - which is the safe direction.
_add_violation() {
    local file="$1"
    local line="$2"
    local rule="$3"
    local message="$4"

    if [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_defers "$rule" "$file"; then
        precedence_hold "$rule" "$file" "$line" "$message"
        return 0
    fi

    local severity
    severity=$(_severity_for "$rule" "$file")

    # The hook drops an ignored rule before it reaches any output. CI has to do
    # the same or the two disagree on a file the team switched the rule off for.
    [[ "$severity" == "ignore" ]] && return 0

    # An empty answer means the resolver failed, not that the finding is minor.
    # Testing only for "block" turned any rules-engine failure into a pipeline
    # of warnings and a green build. Unknown resolves to block.
    case "$severity" in
        block|warn) ;;
        *)
            echo "craftsman-ci: severity unresolved for ${rule}, treating as block" >&2
            severity="block"
            ;;
    esac

    if [[ "$severity" == "block" ]]; then
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
# CI-compatible shims for pack validator API
# Pack validators (php-validator.sh, layer-validator.sh, etc.) call these
# functions which are normally provided by post-write-check.sh.
# These shims bridge the pack API to CI's violation storage arrays.
# =============================================================================
_CI_CURRENT_FILE=""
FILE_PATH=""
FILE_PATTERN=""

add_violation() {
    local rule="$1"
    local message="$2"
    local file="${3:-$_CI_CURRENT_FILE}"
    _add_violation "$file" "0" "$rule" "$message"
}

add_warning() {
    local rule="$1"
    local message="$2"
    _add_violation "$_CI_CURRENT_FILE" "0" "$rule" "$message"
}

line_has_ignore() {
    local line="$1"
    local rule="$2"
    echo "$line" | grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" 2>/dev/null
}

file_has_ignore() {
    local rule="$1"
    grep -qE "craftsman-ignore:\s*[^#]*\b${rule}\b" "$_CI_CURRENT_FILE" 2>/dev/null
}

metrics_record_violation() { :; }
metrics_file_pattern() { echo "$1"; }
metrics_init() { :; }

# The flush callback: a held finding no analyser answered for re-enters the
# funnel and is resolved, counted and reported like any other.
precedence_emit() {
    _add_violation "$2" "$3" "$1" "$4"
}

# The pipeline records no metrics - it is stateless by design and runs on a
# machine that is not the developer's. Defined rather than omitted so the two
# front-ends have the same shape and the difference is a decision on show,
# not an accident of what got implemented where.
precedence_note_superseded() {
    :
}

# Level 2/3 for one file. Its verdicts are emitted directly - never held,
# never superseded - and each code it reports is recorded as answered for, so
# the flush knows which held findings still need to come back.
_run_static_analysis() {
    local file="$1" sa_errors
    [[ "$SA_AVAILABLE" == true ]] || return 0
    sa_errors=$(sa_analyze_file "$file" 2>/dev/null) || true
    [[ -z "$sa_errors" ]] && return 0

    [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_higher_level_begin
    while IFS= read -r err_line; do
        [[ -z "$err_line" ]] && continue
        local sa_code sa_lineno sa_msg
        sa_code=$(echo "$err_line" | cut -d: -f1)
        sa_lineno=$(echo "$err_line" | cut -d: -f2)
        sa_msg=$(echo "$err_line" | cut -d: -f3-)
        sa_msg="${sa_msg#"${sa_msg%%[![:space:]]*}"}"
        [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_declare_covered "$sa_code"
        _add_violation "$file" "${sa_lineno:-0}" "$sa_code" "$sa_msg"
    done <<< "$sa_errors"
    [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_higher_level_end
    return 0
}

# =============================================================================
# File scanner - delegates to pack validators (single source of truth)
# =============================================================================
# craftsman-ignore: SH002 - scanner delegates to pack validators, splitting the dispatcher adds indirection
scan_file() {
    local file="$1"
    local ext="${file##*.}"

    local language=""
    [[ "$PACKS_AVAILABLE" == true ]] && language=$(lang_for_file "$file")

    # Discovered, as distinct from scanned. A file whose extension some
    # installed pack declares counts as discovered even when this project's
    # stack excludes that pack: that is a deliberate exclusion and a legitimate
    # pass. A repository where nothing was recognised at all is a gate that
    # never ran. Counting only php|ts|tsx here is what let one PHP file silence
    # this guard for every Python and Bash file in a mixed repository.
    if [[ "$PACKS_AVAILABLE" == true ]] && lang_extension_is_known "$file"; then
        FILES_DISCOVERED=$((FILES_DISCOVERED + 1))
    fi

    # Set globals for pack validator compatibility
    _CI_CURRENT_FILE="$file"
    FILE_PATH="$file"
    FILE_PATTERN="$file"

    [[ -z "$language" ]] && return 0

    # Per file, not per run: a verdict on one file answers for nothing in the
    # next, and a held finding must not survive into another file's flush.
    [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_reset
    pack_dispatch_file "$file"

    # Structural ratchet parity (ADR-0025): identical check to the hook.
    # CI never writes the baseline; the pipeline is read-only.
    if [[ -f "$PWD/.craftsman-baseline.json" ]] && command -v python3 >/dev/null 2>&1; then
        local ratchet_out ratchet_exit
        ratchet_exit=0
        ratchet_out=$(python3 "$PLUGIN_ROOT/hooks/lib/ratchet.py" check "$file" \
            --baseline "$PWD/.craftsman-baseline.json" 2>/dev/null) || ratchet_exit=$?
        if [[ $ratchet_exit -eq 1 && -n "$ratchet_out" ]]; then
            while IFS= read -r ratchet_line; do
                [[ -z "$ratchet_line" ]] && continue
                add_violation "RATCHET001" "structural regression: ${ratchet_line#RATCHET001 }" "$file"
            done <<< "$ratchet_out"
        fi
    fi

    # Static analysis Level 2/3 (PHPStan, ESLint, Deptrac, dependency-cruiser)
    _run_static_analysis "$file"

    # Custom rules from rules engine (plugin context only)
    if [[ "$RULES_ENGINE_AVAILABLE" == true ]]; then
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
                    # -e: repo-supplied pattern, see rules-engine.sh for the note
                    if echo "$fline" | grep -qE -e "$pattern" 2>/dev/null; then
                        _add_violation "$file" "$ln_num" "$rule_id" "$msg"
                        break
                    fi
                done < "$file"
            done <<< "$custom_rules"
        fi
    fi

    # Every emitter for this file has run. What no analyser answered for comes
    # back now, with the same severity resolution it would have had first time.
    [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_flush

    FILES_SCANNED=$((FILES_SCANNED + 1))
}

# Build find's -name predicate from the loaded packs' declared extensions.
#
# Fills the FIND_PREDICATE array. It used to return a string that the call site
# expanded unquoted, which meant `*.php` and its siblings were glob-expanded
# against the working directory before find ever saw them: one matching file at
# the repository root replaced a whole language with a single literal filename
# (deleting, for instance, every shell rule including SH004), and two aborted
# the walk outright with "unknown primary or operator". find then printed
# nothing and a dead scanner was indistinguishable from a clean tree.
#
# An array keeps every extension a separate argv element, so a pack manifest
# can never become argument structure. The conservative character class below
# stays as defence in depth rather than as the only barrier.
_find_name_predicate() {
    FIND_PREDICATE=()
    local extension
    if [[ "$PACKS_AVAILABLE" == true ]]; then
        while IFS= read -r extension; do
            [[ -z "$extension" ]] && continue
            [[ ! "$extension" =~ ^[A-Za-z0-9_+-]+$ ]] && continue
            [[ ${#FIND_PREDICATE[@]} -gt 0 ]] && FIND_PREDICATE+=(-o)
            FIND_PREDICATE+=(-name "*.${extension}")
        done <<< "$(lang_all_known_extensions)"
    fi

    # No pack, no language, nothing to walk. A predicate matching nothing keeps
    # find syntactically valid, and FILES_DISCOVERED staying at zero is what
    # makes the empty run report itself as "not a pass" rather than as green.
    if [[ ${#FIND_PREDICATE[@]} -eq 0 ]]; then
        FIND_PREDICATE=(-name "*.__craftsman_no_language__")
    fi
}

scan_paths() {
    local path
    for path in "${SCAN_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            scan_file "$path"
        elif [[ -d "$path" ]]; then
            _find_name_predicate
            # Dependency and build trees are not the project's code, and the
            # walk had no exclusions at all: harmless while the default was
            # src/, ruinous the moment a path resolves to the repository root.
            #
            # find's stderr is NOT discarded. Silencing it is what hid the
            # broken predicate above for the life of the pipeline; a walk that
            # complains has to reach the build log, and a walk that found
            # nothing is caught by the FILES_DISCOVERED guard in main().
            while IFS= read -r file; do
                scan_file "$file"
            done < <(find "$path" \
                \( -name vendor -o -name node_modules -o -name .git \
                   -o -name dist -o -name build -o -name var \) -prune -o \
                -type f \( "${FIND_PREDICATE[@]}" \) -print \
                | sort)
        fi
    done
}

# =============================================================================
# Output: text format
# =============================================================================
# craftsman-ignore: SH002 - text formatter is a single cohesive output block
output_text() {
    local total_violations=${#V_FILES[@]}
    local total_warnings=${#W_FILES[@]}

    echo "craftsman-ci v${VERSION} - Quality Gate"
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

# craftsman-ignore: SH002 - JSON formatter is a single cohesive output block
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
# Packs are sourced at startup, before --config and .craft-config.yml have been
# read, so that first load ran against the default stack. The stack filter is
# what decides which languages exist, so the registry has to be rebuilt once the
# real stack is known: otherwise `--config stack=symfony` still validates .ts,
# because the React pack was admitted before anyone knew it should not be.
_rebuild_registry_for_stack() {
    [[ "$PACKS_AVAILABLE" == true ]] || return 0
    [[ -d "$PLUGIN_ROOT/packs" ]] || return 0
    export CLAUDE_PLUGIN_OPTION_stack="$STACK"
    _pack_reset
    pack_loader_init 2>/dev/null || true
}

main() {
    _resolve_config
    _rebuild_registry_for_stack
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

    # A gate that opened no file has not passed, it has not run. Reporting
    # clean on files_scanned=0 is the failure mode secrets-scan.sh already
    # guards with assert_scanner_is_live, and this pipeline had no equivalent:
    # any repository whose sources sit outside the default roots got a green
    # build with nothing inspected.
    if [[ $FILES_DISCOVERED -eq 0 ]]; then
        {
            echo "craftsman-ci: no source file was found, so this is not a pass."
            echo "  scanned: ${SCAN_PATHS[*]}"
            echo "  stack:   ${STACK} (php=$(_php_enabled && echo on || echo off), ts=$(_ts_enabled && echo on || echo off))"
            echo "  Pass the source paths explicitly, or set stack: in .craft-config.yml."
        } >&2
        exit 2
    fi

    if [[ $total_violations -gt 0 ]]; then
        exit 2
    elif [[ $total_warnings -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main
