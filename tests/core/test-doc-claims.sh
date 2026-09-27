#!/usr/bin/env bash
# =============================================================================
# Every published claim about the gate is the claim the code makes.
#
# A claims audit of 4.9.0 found fourteen sentences the code contradicted. Nine
# were fixed with the code they described; the five here had no owner, because
# nothing compares a document to its subject. Each check below reads the code
# first and the document second, so the document is what has to move.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Documented claims against the code ==="

# -----------------------------------------------------------------------------
# 1. The Level 2/3 budget is the one static-analysis.sh applies.
# -----------------------------------------------------------------------------
# "<2s" was published in four files while the analysers ran under a 15s per
# file / 30s per project budget. static-analysis.sh:15-22 says in its own
# comment that 2 seconds is below the cold start of the tools it runs.
BUDGET_FILE=$(grep -oE 'CRAFTSMAN_SA_BUDGET_FILE:-[0-9]+' "$ROOT_DIR/hooks/lib/static-analysis.sh" | head -1 | grep -oE '[0-9]+$')
BUDGET_PROJECT=$(grep -oE 'CRAFTSMAN_SA_BUDGET_PROJECT:-[0-9]+' "$ROOT_DIR/hooks/lib/static-analysis.sh" | head -1 | grep -oE '[0-9]+$')
if [[ -n "$BUDGET_FILE" && -n "$BUDGET_PROJECT" ]]; then
    log_pass "static analysis budgets read from the code: ${BUDGET_FILE}s per file, ${BUDGET_PROJECT}s per project"
else
    log_fail "static analysis budgets could be read" "got file='${BUDGET_FILE}' project='${BUDGET_PROJECT}'"
fi

stale_latency=$(grep -rnE '\| *(2|3) *\|.*\| *<? *2 *s' "$ROOT_DIR/docs" 2>/dev/null || true)
stale_latency+=$(grep -rnE 'Level (2|3)[^.]{0,60}<2s' "$ROOT_DIR/docs" "$ROOT_DIR/README.md" "$ROOT_DIR/CLAUDE.md" "$ROOT_DIR/FAQ.md" 2>/dev/null || true)
if [[ -z "$stale_latency" ]]; then
    log_pass "no document gives Level 2 or 3 a latency the analyser budget contradicts"
else
    log_fail "no document gives Level 2 or 3 a latency the analyser budget contradicts" "$stale_latency"
fi

# -----------------------------------------------------------------------------
# 2. SECURITY.md names every CRAFTSMAN_* switch the code reads.
# -----------------------------------------------------------------------------
# The document told an auditor which environment variables the plugin may read.
# It listed nine of the eighteen the code reads, which is worse than listing
# none: the reader stops looking.
missing_env=""
while IFS= read -r var; do
    grep -q "$var" "$ROOT_DIR/SECURITY.md" || missing_env+="$var "
done < <(grep -rhoE 'CRAFTSMAN_[A-Z_]+' "$ROOT_DIR/hooks" "$ROOT_DIR/ci" "$ROOT_DIR/packs" \
            --include='*.sh' --include='*.py' 2>/dev/null | sort -u)
if [[ -z "$missing_env" ]]; then
    log_pass "SECURITY.md names every CRAFTSMAN_* variable the code reads"
else
    log_fail "SECURITY.md names every CRAFTSMAN_* variable the code reads" "missing: $missing_env"
fi

# -----------------------------------------------------------------------------
# 3. A hook that warns is not documented as a gate.
# -----------------------------------------------------------------------------
# pre-push-verify.sh prints a warning and exits 0 on an unverified session.
# SECURITY.md's hook table said "Gates `git push`", which is the one line an
# auditor would rely on to believe an unverified push cannot happen.
if grep -q 'Warning only - do not block the push' "$ROOT_DIR/hooks/pre-push-verify.sh"; then
    if grep -qE '`pre-push-verify\.sh`.*Gates `git push`' "$ROOT_DIR/SECURITY.md"; then
        log_fail "pre-push-verify.sh is documented as what it is" \
            "the script warns and exits 0, SECURITY.md says it gates the push"
    else
        log_pass "pre-push-verify.sh is documented as a warning, which is what it does"
    fi
else
    log_pass "pre-push-verify.sh blocks, and the documented wording may say so"
fi

# -----------------------------------------------------------------------------
# 4. Levels 2 and 3 are off until the machine owner trusts the project's tools.
# -----------------------------------------------------------------------------
# The network table said "Level 1-3 | On", and the same document says 250 lines
# further down that running the project's analysers is code execution and is
# off by default. Both cannot be true.
if grep -q 'config_trust_project_tools' "$ROOT_DIR/hooks/lib/static-analysis.sh"; then
    if grep -qE '\| *Regex \+ static analysis hooks \(Level 1-3\) *\| *On *\|' "$ROOT_DIR/SECURITY.md"; then
        log_fail "the network table matches the trust gate" \
            "Level 2/3 need trust_project_tools: true (off by default), the table says Level 1-3 On"
    else
        log_pass "the network table does not claim Levels 2 and 3 run by default"
    fi
else
    log_pass "static analysis is not gated on trust_project_tools"
fi

# -----------------------------------------------------------------------------
# 5. A model named for an agent is the model in its frontmatter.
# -----------------------------------------------------------------------------
LEAD_MODEL=$(grep -m1 '^model:' "$ROOT_DIR/agents/team-lead.md" | awk '{print $2}')
bad_model=$(grep -rniE 'team lead[^|]{0,12}: *(sonnet|opus|haiku)' "$ROOT_DIR/docs" 2>/dev/null \
    | grep -viE ": *${LEAD_MODEL}" || true)
if [[ -z "$bad_model" ]]; then
    log_pass "every document naming the team lead's model says ${LEAD_MODEL}"
else
    log_fail "every document naming the team lead's model says ${LEAD_MODEL}" "$bad_model"
fi

# -----------------------------------------------------------------------------
# 6. A rules table in the docs is complete or it is not a rules table.
# -----------------------------------------------------------------------------
# docs/ci-integration.md listed 13 rule ids as "the rules", with no SEC, PY, GO,
# RUST or SH rule among them, at a time when the registry compiled 66. A partial
# list presented as the list is read as the scope of the gate.
REGISTRY_COUNT=$(CLAUDE_PLUGIN_DATA="$(mktemp -d)" python3 "$ROOT_DIR/hooks/lib/rule_registry.py" \
    "$ROOT_DIR/rules/core.yml" "$ROOT_DIR"/packs/*/pack.yml 2>/dev/null | wc -l | tr -d ' ')
DOC_RULES=$(grep -cE '^\| `[A-Z]+[0-9-]*[A-Z0-9]*` \| ' "$ROOT_DIR/docs/ci-integration.md" 2>/dev/null | head -1)
DOC_RULES="${DOC_RULES:-0}"
if [[ "$DOC_RULES" -eq 0 || "$DOC_RULES" -ge "$REGISTRY_COUNT" ]]; then
    log_pass "docs/ci-integration.md lists no partial rules table (registry: ${REGISTRY_COUNT} rules)"
else
    log_fail "docs/ci-integration.md lists no partial rules table" \
        "the table carries ${DOC_RULES} rules, the registry compiles ${REGISTRY_COUNT}"
fi

# -----------------------------------------------------------------------------
# 7. An example never declares Level 2 active without consent and a run.
# -----------------------------------------------------------------------------
# examples/healthcheck/01-plugin-diagnostic.md went from "vendor/bin/phpstan
# found" to "Level 2: active, fully operational". sa_analyze_file returns
# before any analyser runs unless the machine owner set trust_project_tools in
# the global file, so on a fresh install that verdict was false (CR-178, M18).
# The example's own commands are run: the consent check against both answers,
# the probe through the gate's dispatcher with a stand-in phpstan.
DIAG="$ROOT_DIR/examples/healthcheck/01-plugin-diagnostic.md"
example_block() {
    awk -v label="$2" '!found && /^#/ && index($0, label){found=1; next}
        found && /^```bash/{code=1; next}
        code && /^```/{exit}
        code' "$1"
}
unconsented=$(grep -rlE 'Level 2[^|]*\*\*active\*\*' "$ROOT_DIR/examples" 2>/dev/null \
    | while IFS= read -r f; do grep -q 'trust_project_tools' "$f" || echo "${f#"$ROOT_DIR"/}"; done)
CONSENT_CMD=$(example_block "$DIAG" "Check the consent")
PROBE_CMD=$(example_block "$DIAG" "Observe a run")
L2_DIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-claims-l2.XXXXXX")
mkdir -p "$L2_DIR/home/.claude" "$L2_DIR/project/vendor/bin" "$L2_DIR/tmp"
printf '#!/bin/sh\necho "$2:4:Undefined variable: \\$total"\n' > "$L2_DIR/project/vendor/bin/phpstan"
chmod +x "$L2_DIR/project/vendor/bin/phpstan"
l2_run() {
    (cd "$L2_DIR/project" && HOME="$L2_DIR/home" TMPDIR="$L2_DIR/tmp" PATH="$ROOT_DIR/bin:$PATH" \
        bash -c "$1" 2>/dev/null | tr '\n' ' ')
}
CONSENT_OFF=$(l2_run "$CONSENT_CMD"); PROBE_OFF=$(l2_run "$PROBE_CMD")
printf 'v: 4\ntrust_project_tools: true\n' > "$L2_DIR/home/.claude/.craft-config.yml"
CONSENT_ON=$(l2_run "$CONSENT_CMD"); PROBE_ON=$(l2_run "$PROBE_CMD")
rm -rf "$L2_DIR"
if [[ -z "$unconsented" && -n "$CONSENT_CMD" && -n "$PROBE_CMD" \
      && "$CONSENT_OFF" == *"not trusted"* && "$CONSENT_ON" != *"not trusted"* && "$CONSENT_ON" == *trusted* \
      && "$PROBE_OFF" != *PHPSTAN* && "$PROBE_ON" == *PHPSTAN002* ]]; then
    log_pass "the diagnostic example checks consent and observes Level 2 run before calling it active"
else
    log_fail "Level 2 declared active without consent and an observed run" \
        "unconsented examples: '${unconsented}'; consent off/on: '${CONSENT_OFF}'/'${CONSENT_ON}'; probe off/on: '${PROBE_OFF}'/'${PROBE_ON}'"
fi

# -----------------------------------------------------------------------------
# 8. The pre-push hook is documented as the warning it is, the monitor as the
#    log tail it is, and ADR-0023 says so in an amendment.
# -----------------------------------------------------------------------------
# README, SECURITY.md and three guides said "CI and the pre-push gate catch"
# shell-written files, and ADR-0023 calls pre-push-verify.sh "the last
# deterministic gate" and announces phpstan/vitest watchers. The hook reads no
# file and always allows the push; monitors.json tails one log (CR-178, M17).
# The Hermes terminal gate, which does refuse a push, is described as such.
PUSH_HOOK="$ROOT_DIR/hooks/pre-push-verify.sh"
if grep -q 'Warning only - do not block the push' "$PUSH_HOOK" && ! grep -qE '^[^#]*exit 2' "$PUSH_HOOK"; then
    push_claims=$(grep -rniE 'pre-push gate|garde-fou pre-push|pre-push-verify\.sh` before the push|^# Blocks git push|Validate git push commands' \
        "$ROOT_DIR/README.md" "$ROOT_DIR/README.fr.md" "$ROOT_DIR/SECURITY.md" "$ROOT_DIR/docs/guides" \
        "$ROOT_DIR/docs/reference" "$PUSH_HOOK" 2>/dev/null | sed "s|$ROOT_DIR/||" || true)
    if [[ -z "$push_claims" ]]; then
        log_pass "no document calls the pre-push warning a gate that catches files"
    else
        log_fail "the pre-push hook warns and reads no file, documents call it a gate" "$(printf '%s' "$push_claims" | tr '\n' ' ' | cut -c1-600)"
    fi
else
    log_pass "pre-push-verify.sh blocks, and a gate is what the documents may call it"
fi

ADR23="$ROOT_DIR/docs/adr/0023-deterministic-verification-loop.md"
AMENDMENT=$(awk '/^## Amendment/{inside=1} inside' "$ADR23")
watchers_shipped=$(jq -r '.[].command' "$ROOT_DIR/monitors/monitors.json" 2>/dev/null | grep -ciE 'phpstan|vitest|--watch' || true)
if [[ "$watchers_shipped" -gt 0 ]] \
    || { [[ "$AMENDMENT" == *pre-push-verify.sh* && "$AMENDMENT" == *monitors.json* && "$AMENDMENT" == *session-writes* ]]; }; then
    log_pass "ADR-0023 carries an amendment for the push warning, the single monitor and the evidence it reads"
else
    log_fail "ADR-0023 amendment" "no '## Amendment' naming pre-push-verify.sh, monitors.json and the session-writes evidence"
fi

# A skill body is text handed to a model: the host expands nothing in it, and
# Claude Code 2.1.278 exports no CLAUDE_PLUGIN_ROOT to the Bash tool at all
# (measured: the tool sees CLAUDECODE and the session id). Five skills sourced
# their libraries through that variable, so /craftsman:healthcheck ran
# `source "/hooks/lib/config.sh"` and the model improvised a diagnosis.
ENV_IN_SKILLS=$(grep -ln 'CLAUDE_PLUGIN_ROOT}' "$ROOT_DIR"/skills/*/SKILL.md 2>/dev/null \
    | while IFS= read -r f; do
        # the prohibition is prose and wraps where it wraps: the check reads
        # the file as one line so a reflow does not turn it into a failure
        sed 's/^>[[:space:]]*//' "$f" | tr '\n' ' ' | tr -s ' ' \
            | grep -q 'Do not use `${CLAUDE_PLUGIN_ROOT}` in a skill body' || basename "$(dirname "$f")"
      done)
if [[ -z "$ENV_IN_SKILLS" ]]; then
    log_pass "no skill body resolves the plugin through an environment variable the Bash tool does not set"
else
    log_fail "skill bodies use CLAUDE_PLUGIN_ROOT" "$(printf '%s' "$ENV_IN_SKILLS" | tr '\n' ' ')"
fi

# The command those skills call resolves this installation from its own
# location, through a symlink too (the Bash tool's PATH entry is one).
CP_DIR=$(mktemp -d); CP_LINK="$CP_DIR/craftsman-path"
ln -sf "$ROOT_DIR/bin/craftsman-path" "$CP_LINK" 2>/dev/null
if [[ "$("$ROOT_DIR/bin/craftsman-path")" == "$ROOT_DIR" \
    && "$("$ROOT_DIR/bin/craftsman-path" hooks/lib/config.sh)" == "$ROOT_DIR/hooks/lib/config.sh" \
    && "$("$CP_LINK" hooks/lib)" == "$ROOT_DIR/hooks/lib" ]]; then
    log_pass "craftsman-path prints this installation's paths, called directly or through a symlink"
else
    log_fail "craftsman-path" "root=$("$ROOT_DIR/bin/craftsman-path") link=$("$CP_LINK" hooks/lib 2>&1)"
fi
rm -rf "$CP_DIR"

test_summary
