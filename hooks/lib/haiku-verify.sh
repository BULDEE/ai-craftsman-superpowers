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

# Which CLI answers a semantic review. The layer was `claude -p` and nothing
# else, so on a machine without that CLI it vanished in silence (audit CR-117,
# C8). The backend is a boundary: CRAFTSMAN_REVIEW_BACKEND, else
# `review: backend:` in the global .craft-config.yml, else auto (claude-cli
# when `claude` is on PATH, codex-cli when `codex` is, else none). A backend
# is a transport for one prompt and one reply; the prompts, the shape filter
# on the reply and the telemetry are shared, and the verdict of the
# deterministic gate never depends on any of this.
semantic_backend() {
    local backend="${CRAFTSMAN_REVIEW_BACKEND:-}"
    if [[ -z "$backend" ]] && type _config_resolve_nested >/dev/null 2>&1; then
        backend=$(_config_resolve_nested "review" "backend" "auto")
    fi
    case "${backend:-auto}" in
        claude-cli|codex-cli|none) printf '%s' "$backend" ;;
        *)
            if command -v claude >/dev/null 2>&1; then printf 'claude-cli'
            elif command -v codex >/dev/null 2>&1; then printf 'codex-cli'
            else printf 'none'; fi ;;
    esac
}

# The backend the last haiku_verify used, for the run row.
SEMANTIC_BACKEND_USED=""

# Can a verification happen at all, before anything is paid for.
#
# A hook that loads the metrics database to record an outcome pays ~200ms for
# it, and at low effort or with no CLI there IS no outcome: the layer stepped
# aside. Callers ask this first, and skip the whole telemetry path when it
# answers no, which keeps the cost on the runs that produce something.
haiku_verify_possible() {
    [[ "${CLAUDE_EFFORT:-}" == "low" ]] && return 1
    local backend
    backend=$(semantic_backend)
    # Remembered here, in the caller's shell: haiku_verify runs inside a
    # command substitution, and an assignment made there dies with it.
    SEMANTIC_BACKEND_USED="$backend"
    case "$backend" in
        claude-cli) command -v claude >/dev/null 2>&1 ;;
        codex-cli)  command -v codex >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# haiku_verify <prompt>
# Prints the model's reply on stdout. Returns 1 (silently) when the backend is
# unavailable or the subprocess fails: callers degrade to no-op.
haiku_verify() {
    local prompt="$1"
    # Advisory layer only. Hooks receive the session effort level (v2.1.128+,
    # $CLAUDE_EFFORT): at low effort the user asked for speed over depth, so
    # semantic verification steps aside. Deterministic Level 1-3 gates never
    # read this variable: a blocking verdict cannot depend on a reasoning
    # dial, or the hook and CI front-ends would answer differently for the
    # same file. tests/core/test-gate-independence.sh enforces both sides.
    [[ "${CLAUDE_EFFORT:-}" == "low" ]] && return 1
    SEMANTIC_BACKEND_USED=$(semantic_backend)
    case "$SEMANTIC_BACKEND_USED" in
        claude-cli) _semantic_claude_cli "$prompt" ;;
        codex-cli)  _semantic_codex_cli "$prompt" ;;
        *) return 1 ;;
    esac
}

_semantic_claude_cli() {
    command -v claude >/dev/null 2>&1 || return 1
    # The subprocess fires SessionStart and SessionEnd like any session, and
    # this plugin's two hooks used to reset and delete the REAL session's
    # state on every verification. The lock is CRAFTSMAN_HEADLESS_VERIFY, which
    # both hooks now honour. `disableAllHooks` here is a smaller thing than the
    # hooks page suggests: measured on 2.1.270, it silences user and project
    # hooks in the subprocess and NOT plugin hooks (a `claude -p` with this flag
    # and the unguarded 4.9.0 hooks still inserted a `sessions` row). It stays
    # because a verifier has no business running the operator's own hooks.
    # `--bare` would skip every hook but never reads OAuth, which is how most
    # operators are signed in.
    CRAFTSMAN_HEADLESS_VERIFY=1 claude -p "$1" \
        --model "$HAIKU_VERIFY_MODEL" \
        --allowedTools "Read,Grep,Glob" \
        --settings '{"disableAllHooks": true}' \
        --max-turns 8 2>/dev/null || return 1
}

# codex exec, read-only sandbox, no persisted session, the final message as
# the reply (`--json` is an event stream, not a verdict). The model is Codex's
# default unless CRAFTSMAN_VERIFY_MODEL_CODEX names one: the Claude model id
# above is not a name Codex knows. CRAFTSMAN_HEADLESS_VERIFY reaches the child
# Codex session's hooks through the environment it inherits whole
# (tests/fixtures/hosts/PROVENANCE.md), which is what keeps this plugin's own
# hooks in that session from recording a review as a session.
_semantic_codex_cli() {
    command -v codex >/dev/null 2>&1 || return 1
    local reply rc=0
    reply=$(mktemp "${TMPDIR:-/tmp}/craftsman-review.XXXXXX") || return 1
    CRAFTSMAN_HEADLESS_VERIFY=1 codex exec \
        --sandbox read-only --ephemeral --skip-git-repo-check \
        ${CRAFTSMAN_VERIFY_MODEL_CODEX:+-m "$CRAFTSMAN_VERIFY_MODEL_CODEX"} \
        --output-last-message "$reply" - <<< "$1" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -ne 0 || ! -s "$reply" ]]; then
        rm -f "$reply"
        return 1
    fi
    cat "$reply"
    rm -f "$reply"
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

# haiku_verdict_is_clean <verdict>: the exact token, and nothing else.
#
# The prompt asks for the single word CLEAN. Anything else that is not the
# findings token is a reply the layer cannot read: a refusal, a rate limit, an
# empty body, a truncated answer, a sentence with the word in it, an injected
# instruction. Every one of those used to be treated as CLEAN, recorded as a
# clean run and allowed to close the file's earlier findings as "fixed". A
# reply that says nothing is `unavailable`, the same outcome as no reply.
haiku_verdict_is_clean() {
    local verdict
    verdict=$(printf '%s' "$1" | tr -d '[:space:]')
    [[ "$verdict" == "CLEAN" ]]
}

# haiku_close_resolved <file> <current-findings>
#
# What this layer said about a file last time, and no longer says, is fixed.
# Recorded as a correction with source='haiku', which is what makes the fixed
# rate in haiku_report.py a real number instead of a permanent n/a: nothing
# else in the tree ever writes a HAIKU_* correction, and a decision report that
# can only print n/a is worse than no report.
#
# The same instrument that raised the finding is the one that clears it, and
# that is exactly why it may only do so when the FILE changed in between: the
# same content judged twice with two answers is the model's variance, and a
# fixed rate fed by variance measures nothing. The content hash recorded with
# the last run that found something is the witness.
haiku_close_resolved() {
    local file="$1" current="$2"
    local rule
    type metrics_haiku_previous_rules >/dev/null 2>&1 || return 0
    [[ -z "$file" || ! -e "$file" ]] && return 0
    if type metrics_haiku_last_finding_hash >/dev/null 2>&1; then
        local then_hash now_hash
        then_hash=$(metrics_haiku_last_finding_hash "$file")
        now_hash=$(metrics_content_hash "$file")
        [[ -n "$then_hash" && "$then_hash" == "$now_hash" ]] && return 0
    fi
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
