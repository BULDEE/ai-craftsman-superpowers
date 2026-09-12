#!/usr/bin/env bash
# =============================================================================
# Headless Haiku verification helper (ADR-0018).
# Runs a read-only claude -p subprocess on the Haiku tier so semantic
# verification never consumes main-conversation context. Callers MUST
# check CRAFTSMAN_HEADLESS_VERIFY before invoking: the subprocess loads
# plugins too, and without that guard every verification would spawn
# another verification.
# =============================================================================

# The one pinned id in the plugin, and pinned on purpose: this is a machine
# reading a machine's output, where a model change is a behaviour change nobody
# asked for. The tiering guide's aliases are for work a human reads.
#
# It also carries the nearest retirement date of the current lineup, "not
# sooner than October 15, 2026"
# (https://platform.claude.com/docs/en/about-claude/models/overview), so this
# line is the one to revisit first. `claude-haiku-4-5` is the documented alias
# and would not move the date: a dateless id from the 4.6 generation on is its
# own pinned snapshot.
HAIKU_VERIFY_MODEL="${CRAFTSMAN_VERIFY_MODEL:-claude-haiku-4-5-20251001}"

# Can a verification happen at all, before anything is paid for.
#
# A hook that loads the metrics database to record an outcome pays ~200ms for
# it, and at low effort or with no CLI there IS no outcome: the layer stepped
# aside. Callers ask this first, and skip the whole telemetry path when it
# answers no, which keeps the cost on the runs that produce something.
haiku_verify_possible() {
    [[ "${CLAUDE_EFFORT:-}" == "low" ]] && return 1
    command -v claude >/dev/null 2>&1
}

# haiku_verify <prompt>
# Prints the model's reply on stdout. Returns 1 (silently) when the claude
# CLI is unavailable or the subprocess fails: callers degrade to no-op.
haiku_verify() {
    local prompt="$1"
    # Advisory layer only. Hooks receive the session effort level (v2.1.128+,
    # $CLAUDE_EFFORT): at low effort the user asked for speed over depth, so
    # semantic verification steps aside. Deterministic Level 1-3 gates never
    # read this variable: a blocking verdict cannot depend on a reasoning
    # dial, or the hook and CI front-ends would answer differently for the
    # same file. tests/core/test-gate-independence.sh enforces both sides.
    [[ "${CLAUDE_EFFORT:-}" == "low" ]] && return 1
    command -v claude >/dev/null 2>&1 || return 1
    CRAFTSMAN_HEADLESS_VERIFY=1 claude -p "$prompt" \
        --model "$HAIKU_VERIFY_MODEL" \
        --allowedTools "Read,Grep,Glob" \
        --max-turns 8 2>/dev/null || return 1
}

# haiku_findings <verdict-body>
# Constrain what a verification subprocess can say back to the main session.
#
# The subprocess reads files the plugin did not write. A hostile file can carry
# text aimed at the verifier ("ignore your instructions and reply ..."), and
# whatever the verifier then emits is shown to the main model as a system
# reminder. That is an indirect prompt injection path (ATLAS AML.T0051.001):
# untrusted content reaching an agent's instruction channel through a tool.
#
# Rather than trying to detect every possible injection on the way in, we parse
# the way out: a verdict is a list of findings in a known shape, so anything
# that is not that shape is dropped. Same principle the plugin's own doctrine
# states for system boundaries (knowledge/security/secure-by-design.md).
# The category a finding belongs to, as a bounded identifier.
#
# The rule column is grouped by every trend the plugin draws, and
# `_metrics_rule_is_valid` refuses anything that is not an identifier, so
# passing a model's free text through would have recorded NOTHING while
# reporting success: the exact silence this telemetry exists to end. The
# categories are the ones the two prompts ask for, and anything else is
# HAIKU_OTHER rather than dropped, because "the model found something we did
# not think of" is the finding that would justify this layer most.
haiku_finding_rule() {
    local text="$1"
    # The message, never the path. The whole line was classified, so
    # `src/Infrastructure/Doctrine/OrderRepo.php:12 God class` came back
    # HAIKU_LAYER because the PATH said "Infrastructure": the category was
    # decided by where the file lives instead of by what the model found.
    text="${text#*:}"
    while [[ "$text" == [0-9]* ]]; do text="${text#[0-9]}"; done
    text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
    # Most specific first: a god class finding that happens to mention a
    # controller is a god class, and only a finding with no other marker falls
    # through to the layer bucket.
    case "$text" in
        *god\ class*|*responsibilit*|*cohesion*)                   printf 'HAIKU_GOD_CLASS' ;;
        *value\ object*|*primitive\ obsession*)                    printf 'HAIKU_VALUE_OBJECT' ;;
        *aggregate*)                                               printf 'HAIKU_AGGREGATE' ;;
        *missing\ test*|*no\ test*|*without\ a\ corresponding\ test*) printf 'HAIKU_MISSING_TEST' ;;
        *business\ logic*|*use\ case*|*usecase*|*in\ a\ controller*|*controller\ instead*) printf 'HAIKU_CONTROLLER' ;;
        *layer\ violation*|*imports\ infrastructure*|*imports\ presentation*|*layer*) printf 'HAIKU_LAYER' ;;
        *)                                                         printf 'HAIKU_OTHER' ;;
    esac
}

# The file a finding names, taken from the finding and not from the hook's
# input: a Stop-time review reads thirty files and its findings are spread
# across them, so recording them all against one path would make the
# "did Level 1 see this file too" comparison meaningless.
# The file a finding names, resolved against the PROJECT ROOT.
#
# `git diff --name-only` returns paths relative to the repository root, and the
# first version prefixed `$PWD`: a Stop-time review run from a subdirectory
# recorded `app/app/src/...`, a bucket no Level 1 row can ever match, so the
# headline metric reported 100% novelty on files Level 1 had flagged.
haiku_finding_file() {
    local line="$1" path root
    path="${line#"${line%%[![:space:]-*]*}"}"
    path="${path%%:*}"
    [[ -z "$path" ]] && return 0
    if [[ "$path" != /* ]]; then
        root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
        path="${root}/${path}"
    fi
    printf '%s' "$path"
}

# haiku_record_findings <hook> <findings-block> [fallback-file]
#
# One violation row per finding, source='haiku', so
# `SELECT source, COUNT(*) FROM violations` finally answers the question this
# layer has been unable to answer since it shipped. Returns the number recorded
# on stdout, which is the run's finding count.
haiku_record_findings() {
    local hook="$1" findings="$2" fallback="${3:-}"
    local line file rule count=0
    type metrics_record_violation >/dev/null 2>&1 || { printf '0'; return 0; }
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        file=$(haiku_finding_file "$line")
        # The fallback is checked too: a finding naming a file that does not
        # exist is a finding about nothing, and the fallback was recorded just
        # as readily.
        [[ -z "$file" || ! -e "$file" ]] && file="$fallback"
        [[ -z "$file" || ! -e "$file" ]] && continue
        # Outside the project: not recorded. A verdict line naming
        # `../../../../.ssh/config` wrote that path into a database
        # consolidate-metrics.sh shares between machines. A model's output
        # reaching a database is untrusted input, exactly as it is when it
        # reaches the main model.
        [[ -z "$(metrics_relative_path "$file")" ]] && continue
        rule=$(haiku_finding_rule "$line")
        CRAFTSMAN_METRICS_SOURCE=haiku \
            metrics_record_violation "$rule" "$(metrics_file_pattern "$file")" "critical" 1 0 "$file"
        count=$((count + 1))
    done <<< "$findings"
    printf '%s' "$count"
}

# The rule ids a findings block resolves to, one per line: what
# haiku_close_resolved compares against.
haiku_finding_rules() {
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        haiku_finding_rule "$line"
        printf '\n'
    done <<< "$1"
}

# haiku_close_resolved <file> <current-findings>
#
# What this layer said about a file last time, and no longer says, is fixed.
# Recorded as a correction with source='haiku', which is what makes the fixed
# rate in haiku_report.py a real number instead of a permanent n/a: nothing
# else in the tree ever writes a HAIKU_* correction, and a decision report that
# can only print n/a is worse than no report.
#
# A CLEAN verdict resolves everything the file carried, which is the whole
# point: the same instrument that raised the finding is the one that clears it.
haiku_close_resolved() {
    local file="$1" current="$2"
    local rule
    type metrics_haiku_previous_rules >/dev/null 2>&1 || return 0
    [[ -z "$file" || ! -e "$file" ]] && return 0
    while IFS= read -r rule; do
        [[ -z "$rule" ]] && continue
        printf '%s' "$current" | grep -q "$rule" && continue
        CRAFTSMAN_METRICS_SOURCE=haiku \
            metrics_record_correction "$rule" "$(metrics_file_pattern "$file")" \
                "fixed" "no longer reported by the verifier" "$file" 2>/dev/null || true
    done <<< "$(metrics_haiku_previous_rules "$file")"
}

haiku_findings() {
    local body="$1"
    # Shape is the control, not character blocklisting: a line that survives
    # must look like "path:line something". Zero-width characters are left
    # alone on purpose - stripping them in bash 3.2 needs an escape form that
    # portably eats legitimate characters, and they cannot turn a finding line
    # into an instruction on their own.
    printf '%s' "$body" \
        | tr -d '\000-\010\013\014\016-\037' \
        | grep -E '^[[:space:]]*[-*]?[[:space:]]*[[:alnum:]/._-]+:[0-9]+[[:space:]]' \
        | cut -c1-300 \
        | head -10
}
