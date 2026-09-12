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

VERSION="4.9.0"

# =============================================================================
# Defaults
# =============================================================================
FORMAT="text"
CONFIG_FILE=""
SCAN_PATHS=()
CHANGED_ONLY=false
CHANGED_BASE=""
CHANGED_BASE_RESOLVED=""
CHANGED_BASE_SOURCE=""
CHANGED_NONE=false
STRICTNESS="strict"
STACK="fullstack"

# =============================================================================
# Subcommand routing (must come before general argument parsing)
# =============================================================================
# Resolved through the symlink chain, not just made absolute. `bin/craftsman-ci
# -> ../ci/craftsman-ci.sh` is the ordinary way to put this on a PATH, and the
# unresolved dirname pointed the helper lookups at bin/, where nothing lives:
# the baseline command then wrote nothing and still exited 0.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_SOURCE" ]]; do
    SCRIPT_TARGET="$(readlink "$SCRIPT_SOURCE")"
    case "$SCRIPT_TARGET" in
        /*) SCRIPT_SOURCE="$SCRIPT_TARGET" ;;
        *)  SCRIPT_SOURCE="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)/$SCRIPT_TARGET" ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ "${1:-}" == "ci" ]]; then
    shift
    # Parse ci-specific args
    CI_PROVIDER=""
    CI_CONFIG=""
    CI_SCAN_PATHS=()
    CI_PASSTHROUGH=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                [[ $# -ge 2 ]] || { echo "craftsman-ci: --provider needs a name." >&2; exit 2; }
                CI_PROVIDER="$2"; shift 2 ;;
            --config)
                [[ $# -ge 2 ]] || { echo "craftsman-ci: --config needs a file." >&2; exit 2; }
                CI_CONFIG="$2"; shift 2 ;;
            --changed-only) CI_PASSTHROUGH+=("$1"); shift ;;
            --base)
                [[ $# -ge 2 ]] || { echo "craftsman-ci: --base needs a ref." >&2; exit 2; }
                CI_PASSTHROUGH+=("$1" "$2"); shift 2 ;;
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
    CI_RUN_ARGS+=("${CI_PASSTHROUGH[@]+"${CI_PASSTHROUGH[@]}"}")
    CI_RUN_ARGS+=("${CI_SCAN_PATHS[@]+"${CI_SCAN_PATHS[@]}"}")

    # mktemp, not PID: a predictable name in shared /tmp lets a co-tenant on a
    # CI runner pre-create or race the file that decides the gate result.
    local_report=$(mktemp "${TMPDIR:-/tmp}/craftsman-report-XXXXXX") || local_report="/tmp/craftsman-report-$$.json"
    adapter_run "$local_report" "${CI_RUN_ARGS[@]+"${CI_RUN_ARGS[@]}"}"

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
    if [[ -f "$PLUGIN_ROOT/hooks/lib/config.sh" ]]; then
        source "$PLUGIN_ROOT/hooks/lib/config.sh"
    fi
    if [[ -f "$PLUGIN_ROOT/hooks/lib/rules-engine.sh" ]]; then
        source "$PLUGIN_ROOT/hooks/lib/rules-engine.sh"
        rules_init "$PWD" "${HOME:-}" 2>/dev/null || true
    fi
    # Rule ids, wording and grouping live in the rule registry, which the pack
    # loader builds. Without this the Rules section renders empty, which reads
    # as "nothing is enforced".
    if [[ -f "$PLUGIN_ROOT/hooks/lib/pack-loader.sh" ]]; then
        source "$PLUGIN_ROOT/hooks/lib/pack-loader.sh"
        pack_loader_init 2>/dev/null || true
    fi
    source "${SCRIPT_DIR}/doctrine-export.sh"
    doctrine_export "$EXPORT_TARGET"
    exit $?
fi

# `baseline`: photograph the rule violations this repository already carries, so
# the gate stops refusing the first edit to a file for debt nobody in this
# session wrote. The structural ratchet does the same for complexity and size;
# this is the other half, and the two share one file.
#
# It is a scan plus a fold, deliberately: the counts have to come from the same
# validators and the same severity resolution the hooks use, or the mark would
# describe a state the gate never sees.
if [[ "${1:-}" == "baseline" ]]; then
    shift
    BASELINE_PATHS=()
    BASELINE_REMARK=false
    BASELINE_REASON=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --re-baseline) BASELINE_REMARK=true; shift ;;
            --reason) BASELINE_REASON="${2:-}"; shift 2 ;;
            *) BASELINE_PATHS+=("$1"); shift ;;
        esac
    done
    [[ ${#BASELINE_PATHS[@]} -eq 0 ]] && BASELINE_PATHS=(".")

    # A second run is refused. The command supplies the canonical reason itself
    # ("the state this repository arrived in"), which is true once and false
    # every time after: wired into CI, or simply run twice, it would adopt the
    # current state as inherited and pardon every violation written since the
    # first run, under a reason that says otherwise. The mark is taken by a
    # human, once, and re-taken only on purpose.
    # Resolved from the working directory, not by entering the first target.
    # `craftsman-ci baseline nope .` made the `cd` fail, left the variable
    # empty, and walked straight past the guard: exit 0, the success banner,
    # and every violation written since the first mark adopted as inherited.
    # A guard whose precondition can silently fail is not a guard.
    BASELINE_FILE="$(python3 -c \
        "import sys; sys.path.insert(0, '${PLUGIN_ROOT}/hooks/lib'); import ratchet; print(ratchet.project_root() / ratchet.BASELINE_NAME)" 2>/dev/null)"
    if [[ -z "$BASELINE_FILE" ]]; then
        echo "craftsman-ci: could not resolve the project root, refusing to write a baseline" >&2
        exit 1
    fi
    if [[ -f "$BASELINE_FILE" && "$BASELINE_REMARK" != true ]]; then
        echo "craftsman-ci: $BASELINE_FILE already exists." >&2
        echo "The mark is taken once. To re-take it on purpose, say why:" >&2
        echo "  craftsman-ci baseline ${BASELINE_PATHS[*]} --re-baseline --reason \"...\"" >&2
        exit 1
    fi
    if [[ "$BASELINE_REMARK" == true && -z "$BASELINE_REASON" ]]; then
        echo "craftsman-ci: --re-baseline requires --reason \"why\"" >&2
        exit 1
    fi

    # A file argument is refused. `ratchet.py init` guards a re-photograph
    # behind an explicit --reason, and this subcommand supplies the canonical
    # one itself: pointed at a single file it turns the one-way ratchet of
    # ADR-0025 into a two-way door, and records a reason ("the state this
    # repository arrived in") that is false the second time. Directories are
    # the unit of a baseline; a single file is the unit of a deliberate
    # re-mark, and that stays `ratchet.py init <file> --reason "..."`.
    for _baseline_target in "${BASELINE_PATHS[@]}"; do
        if [[ -f "$_baseline_target" ]]; then
            echo "craftsman-ci: baseline takes directories, not files." >&2
            echo "To re-mark one file on purpose, say why:" >&2
            echo "  python3 hooks/lib/ratchet.py init ${_baseline_target} --reason \"...\"" >&2
            exit 1
        fi
    done

    BASELINE_REPORT=$(mktemp "${TMPDIR:-/tmp}/craftsman-baseline-XXXXXX") || exit 1
    trap 'rm -f "$BASELINE_REPORT"' EXIT

    echo "Scanning to record what is already there..."
    bash "$0" --format json "${BASELINE_PATHS[@]}" > "$BASELINE_REPORT" 2>/dev/null || true

    if [[ ! -s "$BASELINE_REPORT" ]]; then
        echo "craftsman-ci: the scan produced no report, refusing to write an empty baseline" >&2
        exit 1
    fi

    # Structural marks first, rule counts folded in after.
    #
    # This order was the first fix: `ratchet.py init` rewrote each row from its
    # own measurement and overwrote a `rules` key written before it, so the
    # first version printed both success lines and produced a baseline with no
    # rules in it at all. Found by running it, not by reading it.
    #
    # It is no longer the fix. `_photograph_into` now carries forward every key
    # it did not measure, which is the real repair, because the same loss
    # happened on every later `init` and `update`, long after this command had
    # returned. Verified: swapping these two lines back no longer breaks
    # anything. The order stays because it states the intent, and because a
    # command should not depend on a guarantee living in another file.
    # PLUGIN_ROOT, not ${SCRIPT_DIR}/..: SCRIPT_DIR is the directory of the
    # symlink when this script is reached through one, so `bin/craftsman-ci ->
    # ci/craftsman-ci.sh` looked for the helpers under bin/ and wrote no
    # baseline at all, silently.
    BASELINE_WHY="initial baseline: the state this repository arrived in"
    RECORD_ARGS=()
    if [[ "$BASELINE_REMARK" == true ]]; then
        BASELINE_WHY="re-baseline: $BASELINE_REASON"
        # Only a re-mark the user asked for admits a rule that was not recorded
        # at the first mark. Without it, `record` lets an existing entry go down
        # and never up.
        RECORD_ARGS=(--re-baseline)
    fi
    python3 "${PLUGIN_ROOT}/hooks/lib/ratchet.py" init "${BASELINE_PATHS[@]}" \
        --reason "$BASELINE_WHY" 2>/dev/null || true
    python3 "${PLUGIN_ROOT}/hooks/lib/rule_baseline.py" record "$BASELINE_REPORT" \
        "${RECORD_ARGS[@]+"${RECORD_ARGS[@]}"}" || exit 1
    echo ""
    echo "Done. A violation already recorded here is reported but no longer blocks."
    echo "A new one, or one more of the same rule in the same file, still does."
    exit 0
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
            [[ $# -ge 2 ]] || { echo "craftsman-ci: --format needs a value." >&2; exit 2; }
            FORMAT="$2"
            shift 2
            ;;
        --config)
            [[ $# -ge 2 ]] || { echo "craftsman-ci: --config needs a file." >&2; exit 2; }
            CONFIG_FILE="$2"
            shift 2
            ;;
        --changed-only)
            CHANGED_ONLY=true
            shift
            ;;
        --base)
            [[ $# -ge 2 ]] || { echo "craftsman-ci: --base needs a ref." >&2; exit 2; }
            CHANGED_BASE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
craftsman-ci v${VERSION} - Craftsman Quality Gate

Usage:
  craftsman-ci [--format json|text] [--config FILE] [--changed-only [--base REF]] [paths...]
  craftsman-ci ci [--provider github|gitlab|bitbucket|jenkins|generic] [--config FILE] [--changed-only [--base REF]] [paths...]
  craftsman-ci init [--provider github|gitlab|bitbucket|jenkins]
  craftsman-ci baseline [paths...]
  craftsman-ci export [--target agents-md|cursor|copilot|all]

Subcommands:
  ci        Run full CI adapter lifecycle (scan, annotate, comment, exit)
  init      Generate CI template for the specified provider
  baseline  Record what this repository already carries, so inherited debt reports without blocking
  export    Render the active rules as agent instruction files (AGENTS.md and friends)

Options:
  --format json|text    Output format (default: text)
  --config FILE         Path to .craft-config.yml (default: auto-detect)
  --changed-only        Validate only the files that differ from the base ref
                        (committed since the merge base, uncommitted, untracked).
                        Paths, when given, narrow that set; they never widen it.
  --base REF            The ref --changed-only diffs against (default: the CI
                        provider's target branch, else origin/main)
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
        PY006|PY007) echo "warn"; return 0 ;;
        GO003|GO004|GO005|GO006|ERRCHECK001) echo "warn"; return 0 ;;
        RUST004|RUST005|CLIPPY001) echo "warn"; return 0 ;;
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

    # A file-level `craftsman-ignore: RULE` is honoured here too.
    # `file_has_ignore` was defined in this file and never called: the hook
    # suppressed the finding at the keyboard while the pipeline failed the
    # build on it, which is the one disagreement these two front-ends are not
    # allowed to have. The file is passed explicitly rather than read from
    # _CI_CURRENT_FILE, because a flushed precedence finding arrives after the
    # scan of its file has moved on.
    if [[ -f "$file" ]] \
        && grep -qE "craftsman-ignore:[[:space:]]*[^#]*\b${rule}\b" "$file" 2>/dev/null; then
        return 0
    fi

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

    # The same engine decision the hook applies. Written here at the same time
    # as there, because the first version had it in the hook only: a file then
    # passed at the keyboard and failed in the pipeline, which is the drift the
    # parity tests exist to catch and did not, because neither knew to look.
    # The same absolute form _severity_for resolves against. Passing the raw
    # path here made the two halves of one decision walk different trees: the
    # severity came from a walk up to the project root, and the baseline
    # question was asked about a path resolved against the working directory.
    # They coincide while the project root IS the working directory, which is
    # a coincidence and not a guarantee.
    local abs_file="$file"
    [[ "$abs_file" != /* ]] && abs_file="$PWD/$file"
    if type rules_baseline_holds >/dev/null 2>&1 \
       && rules_baseline_holds "$abs_file" "$rule" "$severity"; then
        severity="warn"
        message="${message} (already present at the baseline, not blocking)"
    fi

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

# A pack validator that knows where its rule fired puts the line at the front
# of the message: `line 12: Bare 'except:' - catch specific exceptions`. That
# is where it stayed, because both shims below passed a hardcoded "0", so every
# Level 1 finding reached the adapters on line 0 and every provider placed it
# at the top of the file. The information was in the report all along, in the
# one field no annotation reads.
#
# Prints "<line>|<message>", the prefix removed from the message when it was
# found. A validator that does not know its line still says 0, which the
# adapters read as "the whole file".
_ci_line_from_message() {
    local message="$1"
    if [[ "$message" =~ ^line[[:space:]]+([0-9]+):[[:space:]]*(.*)$ ]]; then
        printf '%s|%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    printf '0|%s' "$message"
}

add_violation() {
    local rule="$1"
    local message="$2"
    local file="${3:-$_CI_CURRENT_FILE}"
    local parsed line
    parsed=$(_ci_line_from_message "$message")
    line="${parsed%%|*}"
    _add_violation "$file" "$line" "$rule" "${parsed#*|}"
}

add_warning() {
    local rule="$1"
    local message="$2"
    local parsed line
    parsed=$(_ci_line_from_message "$message")
    line="${parsed%%|*}"
    _add_violation "$_CI_CURRENT_FILE" "$line" "$rule" "${parsed#*|}"
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
    # next, and a held finding must not survive into another file's flush. The
    # baseline's occurrence counter is per file for the same reason, and it had
    # no caller at all: a file reached twice through overlapping scan roots
    # inherited the first pass's count and its recorded debt was read as new.
    [[ "$PRECEDENCE_AVAILABLE" == true ]] && precedence_reset
    type rule_baseline_reset >/dev/null 2>&1 && rule_baseline_reset
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

# Files already scanned in this run. Overlapping roots (`craftsman-ci src
# src/sub`) are an ordinary thing to type, and without this the same file is
# scanned twice: counted twice in "in N file(s)", and, before the counter was
# reset per file, its recorded debt read as new on the second pass.
# Two spellings of one path are one path.
#
# The first version of this compared the strings `find` produced, so
# `craftsman-ci ./src src` scanned every file twice and emitted every finding
# twice, while the one shape a test covered (`src src/sub`) worked. Pure string
# work on purpose: this runs once per discovered file, and three subshells per
# file to call `cd`/`pwd` would cost more than the duplicate scan it prevents.
_ci_normalise_key() {
    local key="$1"
    key="${key#"$PWD"/}"
    while [[ "$key" == ./* ]]; do key="${key#./}"; done
    while [[ "$key" == *//* ]]; do key="${key//\/\//\/}"; done
    key="${key%/}"
    printf '%s' "$key"
}

# =============================================================================
# --changed-only: the input filter that makes a pipeline affordable
#
# Measured on this repository: 83.2s for 197 files, 0.42s a file. Extrapolated
# to a real Symfony application, 3119 PHP files under src/, that is roughly 22
# minutes of CI per pull request and on the order of 3000 findings on the first
# run. A 22-minute job reporting 3000 findings on a one-file pull request goes
# to allow_failure within the week, and the CI half of the gate becomes
# decorative: the plugin's strongest claim is that the hooks and the pipeline
# enforce the same rules, and that claim is worth nothing on a job nobody
# blocks on.
#
# This is a filter on the INPUT, never a change to the engine. Severity
# resolution, pack dispatch and the parity with the hooks are untouched: a
# file in the diff is validated exactly as it always was, and a file outside it
# is validated next time it is touched. Two things it must not become, and both
# are asserted in tests/ci/test-changed-only.sh: a violation introduced in a
# changed file must still fail the job, and a run that finds no changed file
# must say so rather than report a clean scan of nothing.
# =============================================================================

# The ref the diff is taken against, in order of authority: an explicit
# --base, then CRAFTSMAN_BASE_REF, then what the CI provider already knows
# (each names the target branch of the pull request in its own variable), then
# the usual default branches. No ref at all is an error, never a full scan: a
# filter that silently widens to the whole repository would put the 22 minutes
# back on the day a runner's environment changes.
_changed_base_ref() {
    local candidate
    # An explicit ref that does not resolve is an error, never a fallback. The
    # first version walked on to origin/main when --base named a typo, which
    # is a diff against the wrong branch reported with full confidence.
    if [[ -n "${CHANGED_BASE:-}" ]]; then
        if git rev-parse --verify --quiet "${CHANGED_BASE}^{commit}" >/dev/null 2>&1; then
            printf 'explicit %s' "$CHANGED_BASE"
            return 0
        fi
        echo "craftsman-ci: --base ${CHANGED_BASE} is not a ref this repository knows." >&2
        return 1
    fi
    # A ref NAMED by the environment or by the provider is as explicit as
    # --base, and gets the same treatment: an error when it does not resolve.
    # The first version let `GITHUB_BASE_REF=develop` with `origin/develop`
    # unfetched slide to a stale `origin/main`, and reported other people's
    # commits as this pull request's violations with full confidence. The
    # provider named the base; ignoring it is fail-wrong, not fail-closed.
    for candidate in \
        "${CRAFTSMAN_BASE_REF:-}" \
        "${GITHUB_BASE_REF:+origin/${GITHUB_BASE_REF}}" \
        "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:+origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}}" \
        "${BITBUCKET_PR_DESTINATION_BRANCH:+origin/${BITBUCKET_PR_DESTINATION_BRANCH}}" \
        "${CHANGE_TARGET:+origin/${CHANGE_TARGET}}"
    do
        [[ -z "$candidate" ]] && continue
        if git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null 2>&1; then
            if [[ "$candidate" == "${CRAFTSMAN_BASE_REF:-}" ]]; then
                printf 'env %s' "$candidate"
            else
                printf 'provider %s' "$candidate"
            fi
            return 0
        fi
        echo "craftsman-ci: the base ref named by the environment, ${candidate}, is not a ref this repository knows (fetch it, or pass --base)." >&2
        return 1
    done
    # No ref was named anywhere. The default branches are a GUESS, said so on
    # stderr and in the report, because a repository integrated on `develop`
    # has an `origin/main` that exists and is months behind.
    for candidate in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null 2>&1; then
            echo "craftsman-ci: base guessed as ${candidate}; pass --base or set CRAFTSMAN_BASE_REF if your integration branch differs." >&2
            printf 'guess %s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Every file that differs from the base: committed on this branch since the
# merge base (three-dot), plus the working tree against HEAD, plus untracked
# files, because a developer running this locally before committing wants the
# file they are editing, not only the ones they pushed. Deleted files are
# excluded (they cannot be validated), renames are kept under the new name.
_changed_files() {
    local base="$1"
    # --relative: git diff prints paths from the repository root, ls-files
    # prints them from the current directory, and scan_file opens them from
    # the current directory. Without it a run from a subdirectory (a monorepo
    # package) dropped every committed change as "not a file" and validated
    # nothing, with exit 0.
    #
    # NUL-delimited, with core.quotePath off. git quotes any path with a byte
    # above 127 (`"src/Domain/Soci\303\251t\303\251.php"`, quotes included), the
    # `-f` test downstream then failed on the quoted string, and a file with an
    # accent in its name dropped out of the diff: a violation in it passed
    # green. A tab or a newline in the name did the same.
    {
        git -c core.quotePath=false diff -z --relative --name-only --diff-filter=ACMR "${base}...HEAD" 2>/dev/null
        git -c core.quotePath=false diff -z --relative --name-only --diff-filter=ACMR HEAD 2>/dev/null
        git -c core.quotePath=false ls-files -z --others --exclude-standard 2>/dev/null
    } | tr '\0' '\n' | sort -u
}

# A scan path as the user typed it, in the form git prints: no leading ./,
# no trailing /, and an absolute path under $PWD made relative. "./src" and
# "$PWD/src" used to match nothing and report Nothing to validate, exit 0.
_changed_normalise_path() {
    local path="$1" resolved
    # Through the filesystem when it exists, so `src/../src`, `../repo/src` and
    # a symlinked spelling all land on the same string git prints. A path that
    # does not exist keeps the string treatment below and matches nothing,
    # which is the right answer for a scope that is not there.
    if [[ -d "$path" ]]; then
        resolved=$(cd "$path" 2>/dev/null && pwd -P) && path="$resolved"
    elif [[ -f "$path" ]]; then
        resolved=$(cd "${path%/*}" 2>/dev/null && pwd -P) && path="${resolved}/${path##*/}"
    fi
    local here
    here=$(pwd -P)
    case "$path" in
        "$here") path="." ;;
        "$here"/*) path="${path#"$here"/}" ;;
    esac
    while [[ "$path" == ./* ]]; do path="${path#./}"; done
    path="${path%/}"
    printf '%s' "${path:-.}"
}

# The same exclusions the directory walk applies, on the same names: a file
# under vendor/ or dist/ is not the project's code whichever way it was found.
_changed_is_pruned() {
    local file="$1" segment
    local IFS=/
    for segment in $file; do
        case "$segment" in
            vendor|node_modules|.git|dist|build|var) return 0 ;;
        esac
    done
    return 1
}

# The changed files under the requested scan paths, default roots included:
# the paths are the SCOPE and the diff is the FILTER. Only files some pack
# declares an extension for count, which is what the walk's -name predicate
# does: a pull request that changes README.md alone has nothing to validate,
# and must say so rather than fail as "no source file was found".
_changed_in_scope() {
    local file path in_scope
    local -a scope=()
    for path in "${SCAN_PATHS[@]}"; do
        scope+=("$(_changed_normalise_path "$path")")
    done
    while IFS= read -r file; do
        [[ -z "$file" || ! -f "$file" ]] && continue
        # The comment file the generic and Jenkins adapters write into the
        # working tree is untracked, so the second consecutive run found it in
        # the diff and failed as "no source file was found".
        [[ "${file##*/}" == "craftsman-comment.md" ]] && continue
        _changed_is_pruned "$file" && continue
        if [[ "$PACKS_AVAILABLE" == true ]] && ! lang_extension_is_known "$file"; then
            continue
        fi
        in_scope=false
        for path in "${scope[@]}"; do
            [[ "$path" == "." || "$file" == "$path" || "$file" == "$path"/* ]] && in_scope=true
        done
        [[ "$in_scope" == true ]] && printf '%s\n' "$file"
    done
}

apply_changed_only() {
    [[ "$CHANGED_ONLY" == true ]] || return 0

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "craftsman-ci: --changed-only needs a git repository, and this is not one." >&2
        exit 2
    fi
    # Two words on stdout, because this runs in a subshell and a variable set
    # inside `_changed_base_ref` would be gone before the report could read it.
    local base resolved
    if ! resolved=$(_changed_base_ref); then
        {
            echo "craftsman-ci: --changed-only could not resolve a base ref."
            echo "  Pass --base <ref>, set CRAFTSMAN_BASE_REF, or fetch the target branch"
            echo "  (a shallow clone without it is the usual cause)."
        } >&2
        exit 2
    fi
    CHANGED_BASE_SOURCE="${resolved%% *}"
    base="${resolved#* }"
    if ! git merge-base "$base" HEAD >/dev/null 2>&1; then
        {
            echo "craftsman-ci: --changed-only found no merge base between ${base} and HEAD."
            echo "  Fetch enough history for the base ref (fetch-depth: 0, or git fetch --unshallow)."
        } >&2
        exit 2
    fi

    local changed
    changed=$(_changed_files "$base" | _changed_in_scope)
    CHANGED_BASE_RESOLVED="$base"

    if [[ -z "$changed" ]]; then
        # Not a pass and not a failure: nothing to validate, said out loud.
        # main() refuses a scan that opened no file, and this is the one case
        # where that is the correct state rather than a misconfiguration.
        CHANGED_NONE=true
        SCAN_PATHS=()
        return 0
    fi
    SCAN_PATHS=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && SCAN_PATHS+=("$file")
    done <<< "$changed"
}

scan_paths() {
    local path file list
    list=$(mktemp "${TMPDIR:-/tmp}/craftsman-scan-XXXXXX") || return 1

    for path in "${SCAN_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            printf '%s\t%s\n' "$(_ci_normalise_key "$path")" "$path" >> "$list"
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
                printf '%s\t%s\n' "$(_ci_normalise_key "$file")" "$file" >> "$list"
            done < <(find "$path" \
                \( -name vendor -o -name node_modules -o -name .git \
                   -o -name dist -o -name build -o -name var \) -prune -o \
                -type f \( "${FIND_PREDICATE[@]}" \) -print \
                | sort)
        fi
    done

    # Deduplicated on the normalised key, scanned under the spelling the caller
    # used, so a reported path still looks like what was typed. Sorting once
    # also replaces the membership test that grew with every file scanned.
    #
    # Process substitution, not a pipe: a pipe puts scan_file in a subshell and
    # every counter it increments dies there.
    while IFS= read -r file; do
        scan_file "$file"
    done < <(sort -u "$list" | awk -F'\t' '!seen[$1]++ { print $2 }')

    rm -f "$list"
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
  "scope": {
    "changed_only": ${CHANGED_ONLY},
    "base": "${CHANGED_BASE_RESOLVED}",
    "base_source": "${CHANGED_BASE_SOURCE}"
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
    apply_changed_only
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
    if [[ $FILES_DISCOVERED -eq 0 && "$CHANGED_NONE" == true ]]; then
        # The one empty scan that is a true statement: nothing differs from the
        # base, so there is nothing to validate. Said explicitly, because a
        # silent green here would be indistinguishable from a filter that
        # matched nothing by mistake.
        # The JSON report was already written above with files_scanned 0 and
        # scope.changed_only true, which is the shape an adapter reads. Text
        # gets the sentence.
        [[ "$FORMAT" != "json" ]] && echo "craftsman-ci: --changed-only found no file differing from ${CHANGED_BASE_RESOLVED}. Nothing to validate."
        exit 0
    fi

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
