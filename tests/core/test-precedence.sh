#!/usr/bin/env bash
# =============================================================================
# Level precedence tests - a rule a Level 2/3 analyser was declared owner of is
# DEFERRED, never dropped. The analyser emits directly; whatever it did not
# answer for comes back at the flush, with full severity resolution.
#
# Four failure modes are worse than the duplicate verdict this feature removes,
# and all four are asserted here rather than assumed:
#
#   1. Dropping the Level 1 finding when the analyser produced no verdict for
#      it - a timeout, a crash, or a config that turns the rule off. The defect
#      then disappears from both levels, in silence.
#   2. Dropping it because the binary exists on disk, without checking that
#      trust_project_tools lets it run.
#   3. Dropping every rule instead of the declared ones.
#   4. Letting a Level 2/3 verdict supersede itself, so the analyser falls
#      silent because the analyser is installed.
#
# Every assertion is paired with a control on the same harness, so a green
# result cannot be confused with a fixture that never ran.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
setup_test_env
backup_home_bridges

TMPDIR_BASE="/tmp/craftsman-precedence-$$"
PROJECT_DIR="$TMPDIR_BASE/project"
SRC_DIR="$PROJECT_DIR/src"
TOOL_DIR="$PROJECT_DIR/tools"
TOOL_PATH="$TOOL_DIR/craftsman-toycheck"
mkdir -p "$SRC_DIR" "$TOOL_DIR"

_ORIG_HOME="$HOME"
export HOME="$TMPDIR_BASE/home"
mkdir -p "$HOME/.claude"

cleanup() {
    cd "$ROOT_DIR" || true
    export HOME="$_ORIG_HOME"
    restore_home_bridges
    cleanup_test_env
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

echo "=== Level Precedence Tests ==="

# --- Fixture pack -------------------------------------------------------------
# A language nothing else in the repository claims, so a green result cannot be
# inherited from PHP or TypeScript behaviour. Its validator raises two rules:
# TOY001 is declared owned by the analyser, TOY002 is not, which is what tells
# "the right rule was deferred" apart from "everything was dropped".
PACK_DIR="$TMPDIR_BASE/ext-toy"
mkdir -p "$PACK_DIR/hooks" "$PACK_DIR/static-analysis"

# The two messages are deliberately different: which one reaches the output is
# how these tests tell the level that answered. Asserting on the rule id alone
# cannot distinguish "the analyser reported it" from "the regex reported it".
L1_MESSAGE="the level 1 regex saw this"
L23_MESSAGE="the analyser answered for this"

cat > "$PACK_DIR/pack.yml" <<'YAML'
name: toy
version: "1.0.0"
description: "Precedence fixture pack"
compatibility:
  core: ">=2.6.0"
  stack: ["*"]
languages:
  - id: toy
    extensions: ["toy"]
    validators: ["hooks/toy-validator.sh"]
    static_analysis: ["static-analysis/toy-analyse.sh"]
    supersedes:
      - tools/craftsman-toycheck=TOY001
  # Declares a supersession and ships no Level 2/3 adapter. A manifest can be
  # wrong; the engine must not turn that into a coverage hole.
  - id: noadapter
    extensions: ["noadapter"]
    validators: ["hooks/toy-validator.sh"]
    supersedes:
      - tools/craftsman-toycheck=TOY003
rules:
  builtin: ["TOY001", "TOY002", "TOY003"]
hooks:
  validators: ["hooks/toy-validator.sh"]
static_analysis:
  tools: ["static-analysis/toy-analyse.sh"]
commands:
  scaffold_types: []
YAML

cat > "$PACK_DIR/hooks/toy-validator.sh" <<BASH
#!/usr/bin/env bash
pack_validate_toy() {
    local file="\$1"
    grep -q 'forbidden' "\$file" 2>/dev/null \\
        && add_violation "TOY001" "${L1_MESSAGE}"
    grep -q 'sloppy' "\$file" 2>/dev/null \\
        && add_violation "TOY002" "sloppy token - no analyser claims this rule"
    return 0
}

pack_validate_noadapter() {
    local file="\$1"
    grep -q 'forbidden' "\$file" 2>/dev/null \\
        && add_violation "TOY003" "forbidden token - claimed by a tool with no adapter"
    return 0
}
BASH

# CRAFTSMAN_TOY_VERDICT=silent models the cases that matter most: the analyser
# ran but produced no verdict for the rule it owns, because it timed out, it
# crashed, or its own config turns that rule off.
cat > "$PACK_DIR/static-analysis/toy-analyse.sh" <<BASH
#!/usr/bin/env bash
pack_sa_toy() {
    local file="\$1"
    [[ "\${CRAFTSMAN_TOY_VERDICT:-emit}" == "silent" ]] && return 0
    grep -q 'forbidden' "\$file" 2>/dev/null \\
        && echo "TOY001:1:${L23_MESSAGE}"
    return 0
}
BASH

cat > "$SRC_DIR/thing.toy" <<'TOY'
forbidden
sloppy
TOY

cat > "$SRC_DIR/thing.noadapter" <<'TOY'
forbidden
TOY

write_home_config() {
    local trust="$1"
    {
        echo "stack: fullstack"
        [[ "$trust" == "trusted" ]] && echo "trust_project_tools: true"
        echo "packs:"
        echo "  external:"
        echo "    - path: \"$PACK_DIR\""
    } > "$HOME/.claude/.craft-config.yml"
}

install_tool() {
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TOOL_PATH"
    chmod +x "$TOOL_PATH"
}

remove_tool() {
    rm -f "$TOOL_PATH"
}

hook_output() {
    local target="${1:-$SRC_DIR/thing.toy}"
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1
}

ci_output() {
    bash "$ROOT_DIR/ci/craftsman-ci.sh" src 2>&1
}

cd "$PROJECT_DIR" || exit 1

# =============================================================================
# Group A - the fixture reports both rules when no analyser is in play
# =============================================================================
echo ""
echo "--- A. Control: with no analyser, Level 1 reports everything ---"

write_home_config untrusted
remove_tool
BASELINE=$(hook_output)

if echo "$BASELINE" | grep -q "$L1_MESSAGE" && echo "$BASELINE" | grep -q 'TOY002'; then
    log_pass "control: the fixture pack reports TOY001 and TOY002 (harness is live)"
else
    log_fail "control: fixture pack does not report its rules" \
        "got '$(echo "$BASELINE" | tr '\n' ' ' | cut -c1-160)' - every assertion below is undetermined, not green"
fi

# =============================================================================
# Group B - the analyser answers for the rule it was declared owner of
# =============================================================================
echo ""
echo "--- B. An analyser that produces a verdict answers for its rule ---"

write_home_config trusted
install_tool
COVERED=$(hook_output)

if echo "$COVERED" | grep -q "$L1_MESSAGE"; then
    log_fail "the higher verdict replaces the Level 1 one" \
        "the Level 1 message is still in the output beside the analyser's - one defect, two verdicts, which is the duplication this feature exists to remove"
else
    log_pass "the Level 1 finding is not emitted when the analyser answered for it"
fi

if echo "$COVERED" | grep -q "$L23_MESSAGE"; then
    log_pass "a Level 2/3 verdict is never held: the analyser's own report comes out"
else
    log_fail "the analyser's verdict was swallowed" \
        "TOY001 was declared owned by tools/craftsman-toycheck and the analyser reports TOY001, so a shared funnel would let the verdict supersede itself and the file ends with no verdict at all"
fi

if echo "$COVERED" | grep -q 'TOY002'; then
    log_pass "TOY002, which no analyser claims, keeps reporting"
else
    log_fail "precedence is scoped to the declared rules" \
        "TOY002 disappeared too - the supersession is being applied to the whole language instead of the rules the manifest names"
fi

# =============================================================================
# Group C - THE flush. No verdict is not a clean verdict.
# =============================================================================
echo ""
echo "--- C. A claimed rule the analyser did not answer for comes back ---"

write_home_config trusted
install_tool
export CRAFTSMAN_TOY_VERDICT=silent
FLUSHED=$(hook_output)
unset CRAFTSMAN_TOY_VERDICT

if echo "$FLUSHED" | grep -q "$L23_MESSAGE"; then
    log_fail "control: the analyser was supposed to stay silent" \
        "it still reported - the flush assertion below would be meaningless"
elif echo "$FLUSHED" | grep -q "$L1_MESSAGE"; then
    log_pass "the held Level 1 finding is flushed when no higher verdict covers it"
else
    log_fail "a claimed rule vanished from both levels" \
        "the analyser produced no verdict for TOY001 and the Level 1 finding was not flushed either - a cold-start timeout or an analyser configured to ignore the rule now deletes the defect in silence, which is strictly worse than reporting it twice"
fi

# =============================================================================
# Group D - the flush resolves severity, it does not re-emit raw
# =============================================================================
echo ""
echo "--- D. A flushed finding goes through the rules engine ---"

# The control is the SAME run without the override, not merely "something was
# reported". An implementation that flushes nothing at all would satisfy the
# absence below without resolving any severity, and would look green here.
export CRAFTSMAN_TOY_VERDICT=silent
STRICT=$(hook_output)
printf 'rules:\n  TOY001: ignore\n' > "$SRC_DIR/.craft-rules.yml"
RELAXED=$(hook_output)
rm -f "$SRC_DIR/.craft-rules.yml"
unset CRAFTSMAN_TOY_VERDICT

if echo "$STRICT" | grep -q "$L1_MESSAGE"; then
    log_pass "control: the same run without the override does flush TOY001"

    if echo "$RELAXED" | grep -q "$L1_MESSAGE"; then
        log_fail "the flush bypasses severity resolution" \
            "src/.craft-rules.yml sets TOY001 to ignore and it was reported anyway - the flush is writing straight to the output instead of re-entering the funnel, so directory overrides stop applying to any deferred rule"
    else
        log_pass "a flushed rule set to ignore in .craft-rules.yml stays silent"
    fi
else
    log_fail "control: nothing was flushed even without the override" \
        "the ignore assertion below cannot tell a resolved severity from a flush that never ran"
fi

# =============================================================================
# Group E - a level that cannot speak cannot silence anything
#
# These three were the correctness cases of the earlier "drop the Level 1
# finding" design, and each was guarded by its own probe: trust_project_tools,
# the declared binary, a declared adapter. The flush answers all three from
# what actually arrived, so they are asserted here as outcomes and no longer as
# probes. A rule reaching the output is the requirement; which condition let it
# through is an implementation detail that must stay free to change.
# =============================================================================
echo ""
echo "--- E. Untrusted, uninstalled, or no adapter: the rule still reports ---"

export CRAFTSMAN_TOY_VERDICT=silent

write_home_config untrusted
install_tool
UNTRUSTED=$(hook_output)

if echo "$UNTRUSTED" | grep -q "$L1_MESSAGE"; then
    log_pass "TOY001 reports when trust_project_tools is off"
else
    log_fail "an analyser that is not permitted to run silenced a rule" \
        "sa_analyze_file refuses to run it, so nothing can ever answer for TOY001 - the file has no Level 1 and no Level 2/3, no coverage at all"
fi

write_home_config trusted
remove_tool
ABSENT=$(hook_output)

if echo "$ABSENT" | grep -q "$L1_MESSAGE"; then
    log_pass "TOY001 reports when the declared analyser is not installed"
else
    log_fail "an absent analyser silenced a rule" \
        "the regex net is gone on every machine that has not installed the tool"
fi

install_tool
NO_ADAPTER=$(hook_output "$SRC_DIR/thing.noadapter")

if echo "$NO_ADAPTER" | grep -q 'TOY003'; then
    log_pass "a supersession declared by a language shipping no analyser reports"
else
    log_fail "a supersession with nothing behind it silenced a rule" \
        "TOY003's language declares no static_analysis, so a typo in one manifest line deletes a rule and puts nothing in its place"
fi

unset CRAFTSMAN_TOY_VERDICT

# =============================================================================
# Group F - the verdict is the signal, not the manifest's tool name
# =============================================================================
echo ""
echo "--- F. A verdict answers for its rule even with the named tool absent ---"

write_home_config trusted
remove_tool
OTHER_PATH=$(hook_output)

if echo "$OTHER_PATH" | grep -q "$L23_MESSAGE"; then
    log_pass "control: the analyser reported although its declared binary is absent"

    if echo "$OTHER_PATH" | grep -q "$L1_MESSAGE"; then
        log_fail "the duplicate verdict is back" \
            "an adapter reporting through some path other than the binary the manifest names got its verdict AND the regex's - probing for the tool before deferring re-creates exactly the duplication this feature removes"
    else
        log_pass "the arriving verdict answers for the rule, whatever produced it"
    fi
else
    log_fail "control: the fixture analyser did not report" \
        "the assertion above is undetermined, not green"
fi

# =============================================================================
# Group G - the deferral is recorded, not forgotten
# =============================================================================
echo ""
echo "--- G. A deferred rule the analyser answered for leaves a trace ---"

METRICS_DB="${CLAUDE_PLUGIN_DATA}/metrics.db"
if command -v sqlite3 >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    write_home_config trusted
    install_tool
    hook_output >/dev/null

    OVERRIDDEN=$(sqlite3 "$METRICS_DB" \
        "SELECT COUNT(*) FROM corrections WHERE rule='TOY001' AND action='overridden';" 2>/dev/null || echo "0")

    if [[ "${OVERRIDDEN:-0}" -gt 0 ]]; then
        log_pass "the deferral is recorded as overridden, not as a rule that went away"
    else
        log_fail "a superseded rule leaves no trace in the metrics" \
            "add_violation returned before recording, so the rule drops out of the trends and the correction learning reads 'the developer fixed it' where the truth is 'another level answered for it'"
    fi
else
    log_pass "metrics trace skipped: sqlite3 or python3 unavailable"
fi

# =============================================================================
# Group H - a tool may not outrank its own verdicts, refused at compile time
# =============================================================================
echo ""
echo "--- H. Self-supersession is refused when the registry is built ---"

# Two shapes of the same loop, and they are refused at different widths. When
# the named tool IS the language's own adapter, every claim in the entry is
# self-referential. When a distinct tool claims its own code family, only that
# rule is: the rest of the entry is sound and must survive.
SELF_MANIFEST="$TMPDIR_BASE/self/pack.yml"
mkdir -p "$TMPDIR_BASE/self"
cat > "$SELF_MANIFEST" <<'YAML'
name: selfy
languages:
  - id: selfy
    extensions: ["selfy"]
    static_analysis: ["static-analysis/selfy-run.sh"]
    supersedes:
      - selfy-run=SELFY001
  - id: family
    extensions: ["family"]
    static_analysis: ["static-analysis/family-run.sh"]
    supersedes:
      - checker=CHECKER001,KEEP001
YAML

SELF_REGISTRY=$(python3 "$ROOT_DIR/hooks/lib/lang_registry.py" "$SELF_MANIFEST" 2>/dev/null)

if echo "$SELF_REGISTRY" | grep -q 'extensions'; then
    log_pass "control: the throwaway manifest was indexed"

    if echo "$SELF_REGISTRY" | grep -q 'SELFY001'; then
        log_fail "a tool may not supersede the level it belongs to" \
            "selfy-run is this language's own analyser and the registry kept its claim - the analyser would fall silent because the analyser is present"
    else
        log_pass "a claim by the language's own adapter never reaches the registry"
    fi

    if echo "$SELF_REGISTRY" | grep -q 'CHECKER001'; then
        log_fail "a tool may not supersede its own verdicts" \
            "checker kept its claim on CHECKER001, its own code family - the same silencing loop written in the rule column"
    else
        log_pass "a claim on the tool's own code family is refused"
    fi

    if echo "$SELF_REGISTRY" | grep -q 'KEEP001'; then
        log_pass "the sound claim in the same entry survives the refusal"
    else
        log_fail "the refusal is too wide" \
            "KEEP001 was dropped with CHECKER001 - one bad rule id in a list deletes the whole entry"
    fi
else
    log_fail "control: lang_registry.py produced nothing for the manifest" \
        "the refusal assertions are undetermined, not green"
fi

# =============================================================================
# Group I - the pipeline resolves precedence exactly as the hook does
# =============================================================================
echo ""
echo "--- I. Hook and CI agree, in both directions ---"

write_home_config untrusted
remove_tool
CI_BASELINE=$(ci_output)

if assert_produced_output "craftsman-ci" "$CI_BASELINE"; then
    if echo "$CI_BASELINE" | grep -q "$L1_MESSAGE"; then
        log_pass "control: CI reports TOY001 with no analyser in play"

        write_home_config trusted
        install_tool
        CI_COVERED=$(ci_output)

        if echo "$CI_COVERED" | grep -q "$L1_MESSAGE"; then
            log_fail "CI honours the deferral" \
                "CI still emits the Level 1 verdict while the hook does not - green locally and red in the pipeline, on a rule neither front-end decided differently"
        else
            log_pass "CI defers TOY001 under the same conditions the hook does"
        fi

        export CRAFTSMAN_TOY_VERDICT=silent
        CI_FLUSHED=$(ci_output)
        unset CRAFTSMAN_TOY_VERDICT

        if echo "$CI_FLUSHED" | grep -q "$L1_MESSAGE"; then
            log_pass "CI flushes what the analyser did not answer for"
        else
            log_fail "CI drops instead of deferring" \
                "the pipeline loses a defect the hook reports, so a push is greener than the editor was"
        fi

        if echo "$CI_COVERED" | grep -q 'TOY002'; then
            log_pass "CI keeps reporting TOY002, which no analyser claims"
        else
            log_fail "CI scopes precedence to the declared rules" \
                "TOY002 disappeared from the pipeline output too"
        fi
    else
        log_fail "control: CI reports nothing for the fixture language" \
            "the CI harness never validated src/thing.toy - the parity assertions are undetermined"
    fi
fi

# =============================================================================
# Group J - the manifest is the only place the pairing lives
# =============================================================================
echo ""
echo "--- J. No rule and no tool name is hardcoded in the engine ---"

# Comments are documentation and may name an analyser; executable lines may
# not. Stripping them is what tells "explained with an example" apart from
# "hardcoded", and grepping the whole file conflated the two.
PRECEDENCE_CODE=$(/usr/bin/grep -vE '^[[:space:]]*#' "$ROOT_DIR/hooks/lib/precedence.sh")

if [[ -z "$PRECEDENCE_CODE" ]]; then
    log_fail "could not read the precedence library" \
        "no executable line survived the comment filter - the assertions below would pass vacuously"
else
    log_pass "control: the precedence library has executable lines to inspect"

    if echo "$PRECEDENCE_CODE" | /usr/bin/grep -qE '\b(phpstan|deptrac|eslint|depcruise|pylint|ruff|shellcheck)\b'; then
        log_fail "the precedence logic names an analyser" \
            "an executable line in hooks/lib/precedence.sh names a tool - which analyser exists is a pack's knowledge, declared under supersedes:, not the engine's"
    else
        log_pass "no executable line names an analyser"
    fi

    if echo "$PRECEDENCE_CODE" | /usr/bin/grep -qE '\b[A-Z]{2,}[0-9]{3}\b'; then
        log_fail "the precedence logic names a rule" \
            "an executable line in hooks/lib/precedence.sh carries a rule id - the pairing of rule to tool belongs in a pack manifest"
    else
        log_pass "no executable line names a rule"
    fi
fi

test_summary
