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
report("register wires pre_verify, pre_llm_call, pre_tool_call, /craftsman and the quality skill",
       set(ctx.hooks) == {"pre_verify", "pre_llm_call", "pre_tool_call"}
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

# The write-time promise (#21): off by default, and when on, refuses only
# LAYER001 and SEC001-003 before the content reaches disk. Everything else,
# PHP001 included, still waits for the conclusion.
pre_tool_call = ctx.hooks["pre_tool_call"]
LAYERED = ("<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\n"
           "use App\\Infrastructure\\Repo;\nfinal class Order {}\n")
# A password literal, not a provider-shaped token: GitHub push protection
# refuses a commit carrying anything that looks like a real key, fixture or not.
SECRET = ("<?php\ndeclare(strict_types=1);\nfinal class Pay { private string $password = "
          "'correct-horse-battery-staple-9'; }\n")
os.makedirs(os.path.join(repo, "src", "Domain"), exist_ok=True)
off = pre_tool_call(tool_name="write_file",
                    args={"path": "src/Domain/Order.php", "content": LAYERED}, task_id="s1", cwd=repo)
report("the write gate is off by default: a LAYER001 write passes to the conclusion gate", off is None, repr(off))

cp._WRITE_GATE_ON = True
on = pre_tool_call(tool_name="write_file",
                   args={"path": "src/Domain/Order.php", "content": LAYERED}, task_id="s1", cwd=repo)
report("write_gate on: a Domain class importing Infrastructure is refused before it reaches disk",
       isinstance(on, dict) and on.get("action") == "block" and "LAYER001" in str(on.get("message")), repr(on))
report("and the file was not written", not os.path.exists(os.path.join(repo, "src", "Domain", "Order.php")))
secret = pre_tool_call(tool_name="write_file",
                       args={"path": "src/Pay.php", "content": SECRET}, task_id="s1", cwd=repo)
report("write_gate on: a hardcoded secret is refused before it reaches disk",
       isinstance(secret, dict) and secret.get("action") == "block" and "SEC001" in str(secret.get("message")), repr(secret))
loose = pre_tool_call(tool_name="write_file",
                      args={"path": "src/Loose.php", "content": "<?php\nclass Loose { public function setX($v) { $this->x = $v; } }\n"},
                      task_id="s1", cwd=repo)
report("write_gate on: PHP001, PHP002 and PHP003 still wait for the conclusion (not refused here)", loose is None, repr(loose))
report("write_gate on: a tool that is not a write passes untouched",
       pre_tool_call(tool_name="terminal", args={"command": "ls"}, task_id="s1", cwd=repo) is None)

# A patch is judged on the file as it WOULD be, not on the fragment.
with open(os.path.join(repo, "src", "Domain", "Clean.php"), "w") as fh:
    fh.write("<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nuse App\\Domain\\Money;\nfinal class Clean {}\n")
patched = pre_tool_call(tool_name="patch",
                        args={"path": "src/Domain/Clean.php", "old_string": "use App\\Domain\\Money;",
                              "new_string": "use App\\Infrastructure\\Db;"}, task_id="s1", cwd=repo)
report("write_gate on: a patch that would introduce LAYER001 is refused on the would-be file",
       isinstance(patched, dict) and patched.get("action") == "block" and "LAYER001" in str(patched.get("message")), repr(patched))
harmless = pre_tool_call(tool_name="patch",
                         args={"path": "src/Domain/Clean.php", "old_string": "final class Clean {}",
                               "new_string": "final class Clean { public function total(): int { return 1; } }"},
                         task_id="s1", cwd=repo)
report("write_gate on: a harmless patch passes", harmless is None, repr(harmless))

old_write_gate = cp._WRITE_GATE
cp._WRITE_GATE = Path("/nonexistent/write-gate.sh")
broken_write = pre_tool_call(tool_name="write_file", args={"path": "src/X.php", "content": "<?php\n"}, task_id="s1", cwd=repo)
cp._WRITE_GATE = old_write_gate
report("write_gate on: a gate that cannot launch refuses the write rather than passing silently",
       isinstance(broken_write, dict) and broken_write.get("action") == "block", repr(broken_write))
cp._WRITE_GATE_ON = False

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

# =============================================================================
# The write gate's shell wire (Path 1), driven the way Hermes drives it.
#
# The plugin-form assertions above hand the script `args` and a `cwd`. Hermes
# does neither on the shell wire: the tool arguments arrive under `tool_input`
# (agent/shell_hooks.py, _payload_fields), the cwd is the Hermes process's,
# and a plugin hook gets no cwd at all. The first version read `args` only,
# so every shell-hook write passed in silence, and it anchored on cwd, so a
# gateway session's first turn, judged from `/`, passed too.
# =============================================================================
echo ""
echo "--- write gate, shell wire and gateway mode ---"
GATE="$ROOT_DIR/adapters/hermes/pre-tool-call.sh"
WG="$WORK/gate-repo"
mkdir -p "$WG/src/Domain"
( cd "$WG" && git init -q ) >/dev/null 2>&1
LAYERED='<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nuse App\\Infrastructure\\Repo;\nfinal class Order {}\n'

wire() {
    # wire <json payload> [cwd to run from]; prints stdout|rc
    local out rc
    out=$( cd "${2:-$WG}" && printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$GATE" 2>/dev/null ); rc=$?
    printf '%s|%s' "$out" "$rc"
}

WIRE=$(wire "$(printf '{"hook_event_name":"pre_tool_call","tool_name":"write_file","tool_input":{"path":"%s/src/Domain/Order.php","content":"%s"},"session_id":"s1","cwd":"/","profile":"default","extra":{}}' "$WG" "$LAYERED")" /)
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q '"action": "block"' && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "the shell wire (tool_input, cwd of the Hermes process) refuses a LAYER001 write, exit 2"
else
    log_fail "the shell wire refuses a LAYER001 write" "$WIRE"
fi
WIRE=$(wire "$(printf '{"tool_name":"write_file","args":{"path":"%s/src/Domain/Order.php","content":"%s"}}' "$WG" "$LAYERED")" /)
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "gateway mode: no cwd at all and a process cwd of /, the workspace comes from the written path"
else
    log_fail "gateway mode: the workspace comes from the written path" "$WIRE"
fi
WIRE=$(wire "$(printf '{"tool_name":"write_file","args":{"path":"src/Domain/Order.php","content":"%s"},"cwd":"%s"}' "$LAYERED" "$WG")" /)
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "a relative path resolves against the cwd hint when one is given"
else
    log_fail "a relative path resolves against the cwd hint" "$WIRE"
fi

# The gated party does not reconfigure the gate: the same set pre-verify.sh
# refuses at the conclusion, and this test fails when the two drift.
# No comma inside braces in this payload: bash 3.2 brace-expands `{a, b}`
# even through a quoted command substitution, and the JSON arrived split.
WIRE=$(wire "$(printf '{"tool_name":"write_file","args":{"path":"%s/.craft-rules.yml","content":"rules: {SEC001: ignore}"}}' "$WG")")
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "gate's own configuration"; then
    log_pass "a write to .craft-rules.yml is refused: the gated party does not reconfigure the gate"
else
    log_fail "a write to .craft-rules.yml is refused" "$WIRE"
fi
WIRE=$(wire "$(printf '{"tool_name":"write_file","args":{"path":"%s/src/Domain/Order.php","content":"%s"}}' "$WG" "$LAYERED")")
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "and the LAYER001 write after it is still refused"
else
    log_fail "and the LAYER001 write after it is still refused" "$WIRE"
fi
for own in ".craft-config.yml" "adapters/hermes/pre-verify.sh" "ci/craftsman-ci.sh"; do
    if grep -qF "$own" "$ROOT_DIR/adapters/hermes/pre-verify.sh" \
        && python3 - "$ROOT_DIR/adapters/hermes/write_gate_place.py" "$own" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wgp", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.exit(0 if m._touches_gate(sys.argv[2]) else 1)
PY
    then
        log_pass "both gates refuse $own"
    else
        log_fail "both gates refuse $own" "the write gate and pre-verify.sh drifted"
    fi
done

# Hermes applies old_string through fuzzy strategies, so a patch whose text is
# not in the file may still apply: what it adds is judged rather than waved.
printf '<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nfinal class Clean {}\n' > "$WG/src/Domain/Clean.php"
WIRE=$(wire "$(printf '{"tool_name":"patch","args":{"path":"%s/src/Domain/Clean.php","old_string":"    final class Clean {}","new_string":"use App\\\\Infrastructure\\\\Db;\\nfinal class Clean {}"}}' "$WG")")
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "a patch whose old_string is not in the file (fuzzy match ahead) is judged on what it adds"
else
    log_fail "a patch whose old_string is not in the file is judged on what it adds" "$WIRE"
fi
WIRE=$(wire "$(printf '{"tool_name":"patch","args":{"mode":"patch","patch":"*** Begin Patch\\n*** Update File: %s/src/Domain/Clean.php\\n@@\\n-final class Clean {}\\n+use App\\\\Infrastructure\\\\Db;\\n+final class Clean {}\\n*** End Patch"}}' "$WG")")
if [[ "${WIRE##*|}" == "2" ]] && echo "${WIRE%|*}" | grep -q "LAYER001"; then
    log_pass "a V4A patch is judged on the lines it adds to each file"
else
    log_fail "a V4A patch is judged on the lines it adds" "$WIRE"
fi

# The bail needs no python3 and says which kind of failure it is.
WIRE=$( printf '{"tool_name":"write_file","args":{"path":"x.php","content":"<?php"}}' | CLAUDE_PLUGIN_ROOT=/nonexistent bash "$GATE" 2>/dev/null; echo "|$?" )
if [[ "${WIRE##*|}" == "2" ]] && printf '%s' "${WIRE%|*}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['action']=='block' and 'do not retry' in d['message'] else 1)"; then
    log_pass "missing infrastructure refuses with valid JSON, exit 2, and says not to retry"
else
    log_fail "missing infrastructure refuses with valid JSON and says not to retry" "$WIRE"
fi
if ! grep -q "python3 -c" <(sed -n '/^_block()/,/^}/p' "$GATE"); then
    log_pass "the block is written without python3, so python3 missing can be reported"
else
    log_fail "the block is written without python3" "_block calls python3"
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
