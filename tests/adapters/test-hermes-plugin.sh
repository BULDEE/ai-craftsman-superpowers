#!/usr/bin/env bash
# =============================================================================
# Native Hermes plugin (ADR-0029, CR-49/CR-50).
#
# The plugin is python driven by the Hermes gateway; these tests import the
# module the way Hermes does (register(ctx) with a fake ctx) and drive the
# handlers against a fixture repository. The metrics path runs with
# CRAFTSMAN_NO_SQLITE_CLI=1 on purpose: the Hermes image has no sqlite3
# binary, so the python fallback is the path that must hold.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-hermes-plugin.XXXXXX")
DATA="$WORK/data"
mkdir -p "$DATA" "$WORK/repo/src"
: > "$DATA/.legacy-adopted"

echo ""
echo "=== Hermes native plugin ==="

cd "$WORK/repo" && git init -q . 2>/dev/null
printf 'const ok = 1;\nexport { ok };\n' > src/Ok.ts
git add -A >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit -qm fixtures >/dev/null 2>&1

PYOUT="$WORK/driver.out"
CLAUDE_PLUGIN_DATA="$DATA" CRAFTSMAN_NO_SQLITE_CLI=1 REPO="$WORK/repo" ROOT="$ROOT_DIR" \
python3 - > "$PYOUT" 2>"$WORK/driver.err" <<'PYEOF'
import json, os, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
repo = os.environ["REPO"]
sys.path.insert(0, str(root))
import importlib.util
spec = importlib.util.spec_from_file_location("cp", root / "adapters" / "hermes" / "craftsman_plugin.py")
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)


class FakeCtx:
    def __init__(self):
        self.hooks, self.commands, self.skills = {}, {}, {}
    def get_config(self, key, default=None):
        return default
    def register_hook(self, event, cb):
        self.hooks[event] = cb
    def register_command(self, name, handler, description="", args_hint=""):
        self.commands[name] = handler
    def register_skill(self, name, path):
        self.skills[name] = path


def report(label, ok, detail=""):
    print(("ok " if ok else "not ok ") + label + ((" # " + detail) if detail and not ok else ""))


ctx = FakeCtx()
cp.register(ctx)
report("register wires pre_verify, pre_llm_call, /craftsman and the quality skill",
       set(ctx.hooks) == {"pre_verify", "pre_llm_call"}
       and "craftsman" in ctx.commands and "craftsman-quality" in ctx.skills,
       f"hooks={sorted(ctx.hooks)} cmds={sorted(ctx.commands)} skills={sorted(ctx.skills)}")

report("the six curated coding skills are registered alongside the doctrine",
       {"craftsman-refactor", "craftsman-legacy", "craftsman-debug",
        "craftsman-test", "craftsman-spec", "craftsman-design"} <= set(ctx.skills),
       f"skills={sorted(ctx.skills)}")

pre_verify = ctx.hooks["pre_verify"]

with open(os.path.join(repo, "src", "Bad.ts"), "w") as fh:
    fh.write("const bad: any = 1;\n")
directive = pre_verify(session_id="s1", coding=True, attempt=0, changed_paths=["src/Bad.ts"], cwd=repo)
report("a critical violation blocks the conclusion and names the rule",
       isinstance(directive, dict) and directive.get("decision") == "block" and "TS001" in str(directive.get("reason")),
       repr(directive))

report("a non-coding turn stays silent",
       pre_verify(session_id="s1", coding=False, attempt=0, changed_paths=[], cwd=repo) is None)

os.remove(os.path.join(repo, "src", "Bad.ts"))
directive2 = pre_verify(session_id="s1", coding=True, attempt=1, changed_paths=[], cwd=repo)
report("a fixed worktree releases the turn on the next attempt", directive2 is None, repr(directive2))

old_gate = cp._GATE
cp._GATE = Path("/nonexistent/craftsman-gate.sh")
broken = pre_verify(session_id="s2", coding=True, attempt=0, changed_paths=[], cwd=repo)
cp._GATE = old_gate
report("a gate that cannot launch blocks instead of passing silently",
       isinstance(broken, dict) and broken.get("decision") == "block" and "could not run" in str(broken.get("reason")),
       repr(broken))

inject = ctx.hooks["pre_llm_call"](session_id="s1", user_message="hi", is_first_turn=True)
report("first-turn injection carries the correction trends",
       isinstance(inject, dict) and "TS001" in inject.get("context", ""), repr(inject))
report("later turns inject nothing",
       ctx.hooks["pre_llm_call"](session_id="s1", user_message="hi", is_first_turn=False) is None)

# Gateway reality: the plugin process does not live in the agent's workspace.
# The trends query filters by project hash, so a workspace-blind cwd used to
# return nothing at all and the inject verb only worked in CLI mode.
os.chdir("/")
inject = ctx.hooks["pre_llm_call"](session_id="s-new", user_message="hi", is_first_turn=True)
report("injection survives a process cwd outside the workspace (gateway mode)",
       isinstance(inject, dict) and "TS001" in inject.get("context", ""), repr(inject))

os.chdir(repo)
report("/craftsman on a clean worktree says so", "clean worktree" in ctx.commands["craftsman"](""))
report("/craftsman status names the metrics database", "metrics.db" in ctx.commands["craftsman"]("status"))
PYEOF
PYRC=$?

# The driver prints one TAP line per assertion; they become suite results
# here so a failing handler fails the run instead of scrolling past.
while IFS= read -r line; do
    case "$line" in
        "ok "*)     log_pass "${line#ok }" ;;
        "not ok "*) log_fail "${line#not ok }" "$(tail -3 "$WORK/driver.err" 2>/dev/null | tr '\n' ' ')" ;;
    esac
done < "$PYOUT"
if [[ $PYRC -ne 0 ]]; then
    log_fail "python driver crashed" "exit $PYRC: $(tail -5 "$WORK/driver.err" 2>/dev/null | tr '\n' ' ')"
fi

DB="$DATA/metrics.db"
ROW=$(CRAFTSMAN_NO_SQLITE_CLI=1 python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$DB" \
    "SELECT rule, source FROM violations WHERE source='hermes' AND rule='TS001' LIMIT 1" 2>/dev/null)
if [[ "$ROW" == "TS001|hermes" ]]; then
    log_pass "the blocked violation was recorded with source=hermes"
else
    log_fail "violation not recorded" "got: ${ROW:-<empty>}"
fi
ROW=$(CRAFTSMAN_NO_SQLITE_CLI=1 python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$DB" \
    "SELECT rule, action, source, context FROM corrections WHERE source='hermes' LIMIT 1" 2>/dev/null)
if [[ "$ROW" == "TS001|fixed|hermes|hermes attempt 1" ]]; then
    log_pass "the fix between attempts was recorded as a correction"
else
    log_fail "correction not recorded" "got: ${ROW:-<empty>}"
fi

# The curated export is committed output: regenerating it must be clean and
# self-contained (no reference reaching back into knowledge/).
if bash "$ROOT_DIR/scripts/export-hermes-skills.sh" >/dev/null 2>&1 \
    && ! grep -rn "knowledge/" "$ROOT_DIR/adapters/hermes/skills" --include=SKILL.md >/dev/null 2>&1; then
    log_pass "skill export regenerates clean with no dead knowledge link"
else
    log_fail "skill export" "generator failed or left a knowledge/ link"
fi

if python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml,sys; m=yaml.safe_load(open('$ROOT_DIR/plugin.yaml')); sys.exit(0 if m['name']=='craftsman' and 'pre_verify' in m['provides_hooks'] else 1)"; then
        log_pass "plugin.yaml declares the craftsman plugin and its hooks"
    else
        log_fail "plugin.yaml invalid" "name or provides_hooks wrong"
    fi
else
    log_skip "plugin.yaml validation (pyyaml not installed)"
fi

cd / && rm -rf "$WORK"
test_summary
