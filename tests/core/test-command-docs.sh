#!/usr/bin/env bash
# =============================================================================
# Every command a reader can type is documented where the README sends them.
#
# 4.11.0 shipped 22 skills and 15 example folders: agent-design, ci, loop,
# mlops, rag, scaffold and spec had none, while the README told readers that
# /examples "shows each command". The Grok install block showed the plugin
# install and not the gate, on a host that runs no plugin hook. Each check
# reads the code or the skill tree first and the document second.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Command documentation against the skill tree ==="

SKILLS=$(cd "$ROOT_DIR/skills" && for d in */; do [[ -f "$d/SKILL.md" ]] && echo "${d%/}"; done)

skill_is_locked() {
    awk 'NR==1 && $0=="---"{inside=1;next} inside && $0=="---"{exit} inside' "$ROOT_DIR/skills/$1/SKILL.md" \
        | grep -qE '^disable-model-invocation:[[:space:]]*true'
}

# -----------------------------------------------------------------------------
# 1. Every skill has a worked example that invokes it.
# -----------------------------------------------------------------------------
for skill in $SKILLS; do
    examples=$(find "$ROOT_DIR/examples/$skill" -maxdepth 1 -name '*.md' 2>/dev/null)
    if [[ -z "$examples" ]]; then
        log_fail "examples/$skill has a worked example" "no .md under examples/$skill"
        continue
    fi
    if grep -lqE "/craftsman:${skill}([^a-z-]|$)" $examples; then
        log_pass "examples/$skill invokes /craftsman:$skill"
    else
        log_fail "examples/$skill invokes /craftsman:$skill" "no example types the command"
    fi
done

# -----------------------------------------------------------------------------
# 2. No document names a command that does not exist.
# -----------------------------------------------------------------------------
# `/craftsman:name` is the placeholder the host sections use for "any skill".
unknown=""
while IFS= read -r ref; do
    name="${ref##*/craftsman:}"
    [[ "$name" == "name" ]] && continue
    [[ -f "$ROOT_DIR/skills/$name/SKILL.md" ]] || unknown+="$ref "
done < <(grep -rhoE '/craftsman:[a-z][a-z-]*' \
            "$ROOT_DIR/README.md" "$ROOT_DIR/README.fr.md" "$ROOT_DIR/COMMANDS-QUICK-REF.md" \
            "$ROOT_DIR/docs/guides" "$ROOT_DIR/examples" 2>/dev/null | sort -u)
if [[ -z "$unknown" ]]; then
    log_pass "every /craftsman:* reference in the READMEs, guides and examples names a shipped skill"
else
    log_fail "every /craftsman:* reference names a shipped skill" "unknown: $unknown"
fi

# -----------------------------------------------------------------------------
# 3. The quick reference lists every command and links its example.
# -----------------------------------------------------------------------------
missing_ref=""
missing_link=""
for skill in $SKILLS; do
    grep -qE "/craftsman:${skill}([^a-z-]|$)" "$ROOT_DIR/COMMANDS-QUICK-REF.md" || missing_ref+="$skill "
    grep -q "examples/${skill}/" "$ROOT_DIR/COMMANDS-QUICK-REF.md" || missing_link+="$skill "
done
if [[ -z "$missing_ref" ]]; then
    log_pass "COMMANDS-QUICK-REF.md lists every skill"
else
    log_fail "COMMANDS-QUICK-REF.md lists every skill" "missing: $missing_ref"
fi
if [[ -z "$missing_link" ]]; then
    log_pass "COMMANDS-QUICK-REF.md links every skill to its example"
else
    log_fail "COMMANDS-QUICK-REF.md links every skill to its example" "missing: $missing_link"
fi

# -----------------------------------------------------------------------------
# 4. The README states the invocation split the frontmatter declares.
# -----------------------------------------------------------------------------
LOCKED=0
OPEN_SET=""
for skill in $SKILLS; do
    if skill_is_locked "$skill"; then
        LOCKED=$((LOCKED + 1))
    else
        OPEN_SET+="$skill "
    fi
done
OPEN_COUNT=$(echo $OPEN_SET | wc -w | tr -d ' ')

claimed=$(python3 - "$ROOT_DIR/README.md" <<'PY'
import re, sys
words = {w: i for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen "
    "fourteen fifteen sixteen seventeen eighteen nineteen twenty".split())}
text = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
m = re.search(r"(\w+) commands start only when you type them; (\w+) \(([^)]*)\) may be started by the model", text)
if not m:
    print("unmatched")
    sys.exit(0)
names = sorted(re.findall(r"`([a-z-]+)`", m.group(3)))
print(words.get(m.group(1).lower(), -1), words.get(m.group(2).lower(), -1), " ".join(names))
PY
)
expected="$LOCKED $OPEN_COUNT $(echo $OPEN_SET | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$claimed" == "$expected" ]]; then
    log_pass "README.md states $LOCKED typed-only commands and names the $OPEN_COUNT model-invocable ones"
else
    log_fail "README.md states the invocation split the frontmatter declares" \
        "README says '$claimed', skills say '$expected'"
fi

# -----------------------------------------------------------------------------
# 5. A host that does not run plugin hooks has its gate command in both READMEs.
# -----------------------------------------------------------------------------
while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    for readme in README.md README.fr.md; do
        if grep -qE "craftsman-${host}-install|export --target ${host}-hooks" "$ROOT_DIR/$readme"; then
            log_pass "$readme gives the command that writes the ${host} gate"
        else
            log_fail "$readme gives the command that writes the ${host} gate" \
                "hooks/host-capabilities.json says ${host} does not run plugin hooks"
        fi
    done
done < <(jq -r '.hosts | to_entries[] | select(.value.plugin_hooks_executed == false) | .key' \
            "$ROOT_DIR/hooks/host-capabilities.json")

test_summary
