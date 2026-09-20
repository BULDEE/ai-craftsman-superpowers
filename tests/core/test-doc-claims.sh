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
