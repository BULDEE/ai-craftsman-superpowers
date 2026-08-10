#!/usr/bin/env bash
# =============================================================================
# The TypeScript analysers produce a verdict, and a clean file produces none.
#
# Nothing here asserts that the code path ran. That is precisely what the old
# suite asserted - `pack_sa_typescript` on a nonexistent file returns empty,
# and the rule-id mapper maps a hand-written string - and under it two defects
# lived from the first release:
#
#   1. `--format=compact`. ESLint 9.0.0 removed compact from core, so on every
#      ESLint 9 install the adapter asked for a formatter that does not exist.
#      stderr went to /dev/null, `|| true` flattened exit 2, and Level 2 for
#      TypeScript reported clean on every file it was supposed to inspect.
#   2. `--output-type err`. On a clean cruise dependency-cruiser 17 prints
#      "no dependency violations found" on stdout, and the line loop turned
#      that sentence into a blocking ESLINT003. The gate refused clean files
#      and quoted its own success message as the reason.
#
# So every assertion below is about what came out, each is paired with a
# control on the same harness, and the stubs refuse what the real tools refuse:
# an adapter that regresses to compact or to err gets the real tool's answer,
# not a stub that agrees with it.
#
# The replayed payloads are captured verbatim from ESLint 9.39.5 with
# typescript-eslint, and dependency-cruiser 17.4.3. The suite must stay
# offline, but a format invented here would only ever prove the parser matches
# its own fixture. Re-record with CRAFTSMAN_TEST_REAL_TOOLS=1 (see the tail).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
setup_test_env
backup_home_bridges

TMPDIR_BASE="/tmp/craftsman-eslint-$$"
mkdir -p "$TMPDIR_BASE/project"
# ESLint 9 flat config refuses a file outside the config base path, and says so
# as a severity 1 warning rather than an error. On macOS /tmp is a symlink to
# /private/tmp, so an unresolved path would make every analyser here answer
# "file ignored" and every absence assertion pass for the wrong reason.
PROJECT_DIR=$(cd "$TMPDIR_BASE/project" && pwd -P)
SRC_DIR="$PROJECT_DIR/src"
BIN_DIR="$PROJECT_DIR/node_modules/.bin"
mkdir -p "$SRC_DIR" "$BIN_DIR"

# The package markers are not decoration. The adapter this suite replaces
# reached dependency-cruiser through `npx depcruise` gated on this file, so
# without it the whole Level 3 path is skipped and the false-block assertion in
# group C would be armed against code that never ran - green, and proving
# nothing. npx resolves the local .bin first, so the stub answers either way.
mkdir -p "$PROJECT_DIR/node_modules/dependency-cruiser" "$PROJECT_DIR/node_modules/eslint"
printf '{"name":"dependency-cruiser","version":"17.4.3"}\n' \
    > "$PROJECT_DIR/node_modules/dependency-cruiser/package.json"
printf '{"name":"eslint","version":"9.39.5"}\n' \
    > "$PROJECT_DIR/node_modules/eslint/package.json"

_ORIG_HOME="$HOME"
export HOME="$TMPDIR_BASE/home"
mkdir -p "$HOME/.claude"
{
    echo "stack: fullstack"
    echo "trust_project_tools: true"
} > "$HOME/.claude/.craft-config.yml"

cleanup() {
    cd "$ROOT_DIR" || true
    export HOME="$_ORIG_HOME"
    restore_home_bridges
    cleanup_test_env
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

echo "=== TypeScript Level 2/3 verdicts ==="

# --- Fixtures -----------------------------------------------------------------
# Level 1 clean on purpose: no bare `: any`, no default export, no `!`. Whatever
# these files report can only have come from Level 2 or Level 3, which is what
# lets the assertions tell the two apart.
cat > "$SRC_DIR/bad.ts" <<'TS'
export const danger = (input: unknown): string => {
  const payload = input as any;
  return String(payload);
};
TS

cat > "$SRC_DIR/unused.ts" <<'TS'
export const compute = (): number => {
  const leftover = 42;
  return 1;
};
TS

cat > "$SRC_DIR/clean.ts" <<'TS'
export const clean = (): string => "ok";
TS

cat > "$SRC_DIR/a.ts" <<'TS'
import { b } from "./b";
export const a = (): string => b();
TS

cat > "$SRC_DIR/b.ts" <<'TS'
import { a } from "./a";
export const b = (): string => a();
TS

BAD_FILE="$SRC_DIR/bad.ts"
UNUSED_FILE="$SRC_DIR/unused.ts"
CLEAN_FILE="$SRC_DIR/clean.ts"
CYCLE_FILE="$SRC_DIR/a.ts"

ARGV_LOG="$PROJECT_DIR/argv.log"

# --- ESLint stub --------------------------------------------------------------
# Refuses every formatter ESLint 9 removed, with the message ESLint 9.39.5
# prints, on the stream it prints it on. A stub that answered whatever it was
# asked could not tell a working adapter from the broken one.
_eslint_stub_argv() {
    cat <<'STUB'
echo "eslint $*" >> "$ARGV_LOG"
FORMAT="stylish"
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --format=*) FORMAT="${1#--format=}" ;;
        -f) shift; FORMAT="${1:-}" ;;
        --*) : ;;
        *) TARGET="$1" ;;
    esac
    shift
done
STUB
}

_eslint_stub_formatter_guard() {
    cat <<'STUB'
case "$FORMAT" in
    checkstyle|compact|jslint-xml|junit|tap|unix|visualstudio)
        echo "The $FORMAT formatter is no longer part of core ESLint. Install it manually with \`npm install -D eslint-formatter-$FORMAT\`" >&2
        exit 2
        ;;
esac
if [[ "$FORMAT" != "json" ]]; then
    echo "stub: no recording for the $FORMAT formatter" >&2
    exit 2
fi
STUB
}

_eslint_stub_payloads() {
    cat <<'STUB'
case "$(basename "$TARGET")" in
    bad.ts)
        printf '[{"filePath":"%s","messages":[{"ruleId":"@typescript-eslint/no-explicit-any","severity":2,"message":"Unexpected any. Specify a different type.","line":2,"column":28,"nodeType":"TSAnyKeyword","messageId":"unexpectedAny","endLine":2,"endColumn":31}],"suppressedMessages":[],"errorCount":1,"fatalErrorCount":0,"warningCount":0}]\n' "$TARGET"
        exit 1 ;;
    unused.ts)
        printf '[{"filePath":"%s","messages":[{"ruleId":"@typescript-eslint/no-unused-vars","severity":2,"message":"'"'"'leftover'"'"' is assigned a value but never used.","line":2,"column":9,"nodeType":"Identifier","messageId":"unusedVar","endLine":2,"endColumn":17}],"suppressedMessages":[],"errorCount":1,"fatalErrorCount":0,"warningCount":0}]\n' "$TARGET"
        exit 1 ;;
    ignored.ts)
        printf '[{"filePath":"%s","messages":[{"ruleId":null,"fatal":false,"severity":1,"message":"File ignored because outside of base path.","nodeType":null}],"suppressedMessages":[],"errorCount":0,"fatalErrorCount":0,"warningCount":1}]\n' "$TARGET"
        exit 0 ;;
    *)
        printf '[{"filePath":"%s","messages":[],"suppressedMessages":[],"errorCount":0,"fatalErrorCount":0,"warningCount":0}]\n' "$TARGET"
        exit 0 ;;
esac
STUB
}

install_eslint_stub() {
    {
        printf '#!/usr/bin/env bash\n'
        _eslint_stub_argv
        _eslint_stub_formatter_guard
        _eslint_stub_payloads
    } > "$BIN_DIR/eslint"
    chmod +x "$BIN_DIR/eslint"
}

# --- dependency-cruiser stub --------------------------------------------------
# The `err` branch replays the prose that caused defect 2, so an adapter that
# regresses to it fails the clean-file assertion instead of quietly passing.
_depcruise_stub_argv() {
    cat <<'STUB'
echo "depcruise $*" >> "$ARGV_LOG"
OUTPUT_TYPE="err"
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-type) shift; OUTPUT_TYPE="${1:-}" ;;
        --output-type=*) OUTPUT_TYPE="${1#--output-type=}" ;;
        --*) : ;;
        *) TARGET="$1" ;;
    esac
    shift
done
CYCLE='{"type":"cycle","from":"src/a.ts","to":"src/b.ts","rule":{"severity":"error","name":"no-circular"}}'
VIOLATIONS="[]"
[[ "$(basename "$TARGET")" == "a.ts" ]] && VIOLATIONS="[$CYCLE]"
STUB
}

_depcruise_stub_payloads() {
    cat <<'STUB'
if [[ "$OUTPUT_TYPE" == "json" ]]; then
    printf '{"modules":[],"summary":{"violations":%s,"error":0,"warn":0,"info":0,"totalCruised":2}}\n' "$VIOLATIONS"
    [[ "$VIOLATIONS" == "[]" ]] && exit 0
    exit 1
fi
if [[ "$VIOLATIONS" == "[]" ]]; then
    printf '\n\xe2\x9c\x94 no dependency violations found (1 modules, 0 dependencies cruised)\n'
    exit 0
fi
printf '\n  error no-circular: src/a.ts \xe2\x86\x92 \n      src/b.ts \xe2\x86\x92\n      src/a.ts\n\nx 1 dependency violations (1 errors, 0 warnings). 2 modules, 2 dependencies cruised.\n'
exit 1
STUB
}

install_depcruise_stub() {
    {
        printf '#!/usr/bin/env bash\n'
        _depcruise_stub_argv
        _depcruise_stub_payloads
    } > "$BIN_DIR/depcruise"
    chmod +x "$BIN_DIR/depcruise"
}

export ARGV_LOG
install_eslint_stub
install_depcruise_stub
cd "$PROJECT_DIR" || exit 1

hook_output() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" 2>&1
}

hook_exit() {
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | bash "$ROOT_DIR/hooks/post-write-check.sh" >/dev/null 2>&1
    echo $?
}

# =============================================================================
# Group A - the guards themselves, seen refusing before anything relies on them
# =============================================================================
echo ""
echo "--- A. The stubs refuse what the real tools refuse ---"

STUB_COMPACT=$("$BIN_DIR/eslint" "$BAD_FILE" --format=compact 2>/dev/null)
if [[ -z "$STUB_COMPACT" ]]; then
    log_pass "the eslint stub answers a removed formatter with empty stdout"
else
    log_fail "the eslint stub accepted --format=compact" \
        "it would agree with a regressed adapter instead of catching it"
fi

STUB_ERR=$("$BIN_DIR/depcruise" "$CLEAN_FILE" --output-type err 2>/dev/null)
if echo "$STUB_ERR" | grep -q "no dependency violations found"; then
    log_pass "the depcruise stub still prints the prose that caused the false block"
else
    log_fail "the depcruise stub lost the err prose" \
        "the clean-file assertion below could no longer catch a regression to --output-type err"
fi

# =============================================================================
# Group B - the adapter answers
# =============================================================================
echo ""
echo "--- B. A real violation comes out under its own code ---"

SA_BUDGET_FILE_SECONDS=15
SA_BUDGET_PROJECT_SECONDS=30
sa_timeout() { shift; "$@"; }
source "$ROOT_DIR/packs/react/static-analysis/eslint.sh"

: > "$ARGV_LOG"
ADAPTER_BAD=$(pack_sa_typescript "$BAD_FILE" 2>/dev/null)

if assert_produced_file "eslint invocation" "$ARGV_LOG"; then
    log_pass "control: the analysers were invoked at all"

    if grep -q -- "--format=json" "$ARGV_LOG"; then
        log_pass "eslint is asked for the json formatter"
    else
        log_fail "eslint was not asked for a machine-readable formatter" \
            "got '$(head -1 "$ARGV_LOG")' - ESLint 9 removed compact, unix, tap and the rest from core, and a removed formatter fails on stderr where the adapter cannot see it"
    fi

    if grep -q -- "--output-type json" "$ARGV_LOG"; then
        log_pass "dependency-cruiser is asked for the json reporter"
    else
        log_fail "dependency-cruiser was not asked for the json reporter" \
            "got '$(grep depcruise "$ARGV_LOG" | head -1)' - the err reporter announces success in the same stream as the failures"
    fi
fi

if assert_produced_output "pack_sa_typescript" "$ADAPTER_BAD"; then
    if echo "$ADAPTER_BAD" | grep -q '^ESLINT001:2:'; then
        log_pass "no-explicit-any is reported as ESLINT001 on its own line number"
    else
        log_fail "the eslint verdict did not survive parsing" \
            "got '$(echo "$ADAPTER_BAD" | tr '\n' ' ' | cut -c1-160)'"
    fi
fi

ADAPTER_UNUSED=$(pack_sa_typescript "$UNUSED_FILE" 2>/dev/null)
if echo "$ADAPTER_UNUSED" | grep -q '^ESLINT004:'; then
    log_pass "no-unused-vars is reported as ESLINT004"
else
    log_fail "the rule id was not mapped" \
        "got '$(echo "$ADAPTER_UNUSED" | tr '\n' ' ' | cut -c1-160)' - a mapping that only ever answers ESLINT001 sends the developer to the wrong rule"
fi

ADAPTER_CYCLE=$(pack_sa_typescript "$CYCLE_FILE" 2>/dev/null)
if echo "$ADAPTER_CYCLE" | grep -q '^ESLINT003:.*no-circular'; then
    log_pass "a dependency-cruiser violation is reported as ESLINT003, named"
else
    log_fail "the cruise verdict did not come out" \
        "got '$(echo "$ADAPTER_CYCLE" | tr '\n' ' ' | cut -c1-160)'"
fi

if echo "$ADAPTER_CYCLE" | grep -q 'src/a.ts -> src/b.ts'; then
    log_pass "the finding names both modules of the pair"
else
    log_fail "the cruise finding does not say which modules" \
        "a cruise walks the whole import graph from the edited file, so a finding that does not name its modules points at the wrong file"
fi

# =============================================================================
# Group C - and says nothing about a clean file
# =============================================================================
echo ""
echo "--- C. A clean file produces no finding at all ---"

ADAPTER_CLEAN=$(pack_sa_typescript "$CLEAN_FILE" 2>/dev/null)
if [[ -z "$ADAPTER_CLEAN" ]]; then
    log_pass "a clean file produces no Level 2/3 finding"
else
    log_fail "a clean file was reported as violating something" \
        "got '$(echo "$ADAPTER_CLEAN" | tr '\n' ' ' | cut -c1-160)' - the err reporter's success sentence used to arrive here as a blocking ESLINT003"
fi

cp "$SRC_DIR/clean.ts" "$SRC_DIR/ignored.ts"
ADAPTER_IGNORED=$(pack_sa_typescript "$SRC_DIR/ignored.ts" 2>/dev/null)
if [[ -z "$ADAPTER_IGNORED" ]]; then
    log_pass "an eslint severity 1 warning is not reported as a violation"
else
    log_fail "a warning was read as an error" \
        "got '$(echo "$ADAPTER_IGNORED" | tr '\n' ' ' | cut -c1-160)' - 'File ignored because outside of base path' is not a defect in the file"
fi

# =============================================================================
# Group D - and all of it reaches the hook
# =============================================================================
echo ""
echo "--- D. The verdict reaches the gate the developer actually meets ---"

HOOK_BAD=$(hook_output "$BAD_FILE")
if assert_produced_output "post-write-check" "$HOOK_BAD"; then
    if echo "$HOOK_BAD" | grep -q 'ESLINT001'; then
        log_pass "the eslint verdict reaches the hook output"
    else
        log_fail "the verdict was lost between the adapter and the hook" \
            "got '$(echo "$HOOK_BAD" | tr '\n' ' ' | cut -c1-200)'"
    fi
fi

if [[ "$(hook_exit "$BAD_FILE")" == "2" ]]; then
    log_pass "the hook reports it as blocking"
else
    log_fail "the hook did not report the eslint verdict" \
        "a Level 2 finding that changes no exit code is a finding nobody sees"
fi

HOOK_CYCLE=$(hook_output "$CYCLE_FILE")
if echo "$HOOK_CYCLE" | grep -q 'ESLINT003'; then
    log_pass "the cruise verdict reaches the hook output"
else
    log_fail "the Level 3 verdict was lost" \
        "got '$(echo "$HOOK_CYCLE" | tr '\n' ' ' | cut -c1-200)'"
fi

CLEAN_EXIT=$(hook_exit "$CLEAN_FILE")
if [[ "$CLEAN_EXIT" == "0" ]]; then
    log_pass "a clean file is not blocked"
else
    log_fail "the gate blocked a clean file" \
        "exit $CLEAN_EXIT on '$(hook_output "$CLEAN_FILE" | tr '\n' ' ' | cut -c1-200)' - this is the defect that shipped: dependency-cruiser's own success sentence, quoted back as the violation"
fi

# =============================================================================
# Group E - the recordings above are what the real tools actually print
# =============================================================================
# Opt-in because it installs from the network. Everything above replays these
# payloads; this is the leg that catches the next major changing the contract,
# and it is the one to run before re-recording a stub:
#
#   CRAFTSMAN_TEST_REAL_TOOLS=1 bash tests/packs/test-eslint-verdict.sh
echo ""
echo "--- E. Against the real ESLint and the real dependency-cruiser ---"

if [[ "${CRAFTSMAN_TEST_REAL_TOOLS:-0}" != "1" ]]; then
    echo "  - skipped (network): CRAFTSMAN_TEST_REAL_TOOLS=1 to install and run them"
elif ! command -v npm >/dev/null 2>&1; then
    echo "  - skipped: npm not on PATH"
else
    rm -f "$BIN_DIR/eslint" "$BIN_DIR/depcruise"
    printf '{"name":"craftsman-eslint-fixture","private":true}\n' > "$PROJECT_DIR/package.json"
    cat > "$PROJECT_DIR/eslint.config.mjs" <<'CONFIG'
import tseslint from 'typescript-eslint';
export default [...tseslint.configs.recommended];
CONFIG
    cat > "$PROJECT_DIR/.dependency-cruiser.cjs" <<'CONFIG'
module.exports = {
  forbidden: [{ name: "no-circular", severity: "error", from: {}, to: { circular: true } }],
  options: { doNotFollow: { path: "node_modules" }, tsPreCompilationDeps: true }
};
CONFIG
    npm install --no-audit --no-fund --silent \
        eslint@9 typescript-eslint typescript dependency-cruiser >/dev/null 2>&1

    if [[ ! -f "$BIN_DIR/eslint" ]]; then
        log_fail "real tools: install failed" "nothing was proven against a real analyser"
    else
        REAL_BAD=$(pack_sa_typescript "$BAD_FILE" 2>/dev/null)
        if echo "$REAL_BAD" | grep -q '^ESLINT001:'; then
            log_pass "real eslint $("$BIN_DIR/eslint" --version): the violation comes out as ESLINT001"
        else
            log_fail "real eslint produced no verdict" \
                "got '$REAL_BAD' - the formatter contract changed again, re-record the stub from this run"
        fi

        REAL_CLEAN=$(pack_sa_typescript "$CLEAN_FILE" 2>/dev/null)
        if [[ -z "$REAL_CLEAN" ]]; then
            log_pass "real tools: a clean file produces no finding"
        else
            log_fail "real tools: a clean file was reported" "got '$REAL_CLEAN'"
        fi

        REAL_CYCLE=$(pack_sa_typescript "$CYCLE_FILE" 2>/dev/null)
        if echo "$REAL_CYCLE" | grep -q '^ESLINT003:.*no-circular'; then
            log_pass "real dependency-cruiser: the cycle comes out as ESLINT003"
        else
            log_fail "real dependency-cruiser produced no verdict" "got '$REAL_CYCLE'"
        fi
    fi
fi

test_summary
