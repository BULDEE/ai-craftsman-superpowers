#!/usr/bin/env bash
# =============================================================================
# Rules belong to the packs that enforce them.
#
# ci/doctrine-export.sh owns every rule id, its group, its wording and, through
# hooks/lib/rules-engine.sh, its advisory default. A pack shipping DART001 has
# nowhere to declare any of that, so "the engine holds no list" stops being true
# the moment the subject is doctrine rather than dispatch.
#
# Every assertion here is paired with a known-good control on a shipped rule, so
# a red result cannot be confused with a broken harness.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

CLI="$ROOT_DIR/ci/craftsman-ci.sh"
WORK="/tmp/craftsman-rule-registry-$$"
PREV_PWD="$PWD"
mkdir -p "$WORK/project"

_ORIG_HOME="$HOME"
export HOME="$WORK/home"
mkdir -p "$HOME/.claude"

cleanup() {
    cd "$PREV_PWD" || true
    export HOME="$_ORIG_HOME"
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== Rule registry ==="

# A pack that owns one rule: id, group, wording and advisory default.
EXT_PACK="$WORK/ext-fake"
mkdir -p "$EXT_PACK/hooks"
cat > "$EXT_PACK/pack.yml" <<'YAML'
name: fake
version: "1.0.0"
description: "Fixture pack owning a single rule"
compatibility:
  core: ">=4.4.0"
  stack: ["*"]
languages:
  - id: fake
    extensions: ["fake"]
    validators: ["hooks/fake-validator.sh"]
rules:
  owned:
    - id: FAKE001
      group: Fake
      text: "a fixture rule owned by a pack, not by the engine"
      default_severity: warn
  builtin: ["FAKE001"]
YAML
cat > "$EXT_PACK/hooks/fake-validator.sh" <<'BASH'
#!/usr/bin/env bash
pack_validate_fake() { :; }
BASH

cat > "$HOME/.claude/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$EXT_PACK"
YAML

cd "$WORK/project" || exit 1
bash "$CLI" export --target agents-md >/dev/null 2>&1

if [[ ! -f AGENTS.md ]]; then
    log_fail "export produced no AGENTS.md" "every assertion below would be vacuous"
    test_summary
fi

# Control: a shipped rule and its wording reach the exported doctrine. Without
# this, a missing FAKE001 could equally mean the exporter is broken.
if grep -q 'PHP001' AGENTS.md && grep -qi 'strict_types' AGENTS.md; then
    log_pass "control: a shipped rule and its wording reach the exported doctrine"

    if grep -q 'FAKE001' AGENTS.md; then
        log_pass "a rule owned by a pack reaches the exported doctrine"
    else
        log_fail "pack-owned rule missing from doctrine" \
            "FAKE001 is declared in the pack manifest and never exported - doctrine ids still live in ci/doctrine-export.sh"
    fi

    if grep -q 'a fixture rule owned by a pack' AGENTS.md; then
        log_pass "the pack's own wording is used, not a fallback"
    else
        log_fail "pack-owned wording missing" \
            "the rule text declared in pack.yml did not reach AGENTS.md"
    fi
else
    log_fail "control: shipped doctrine did not export" \
        "PHP001 or its wording is absent from AGENTS.md - the assertions above are undetermined"
fi

echo ""
echo "=== Severity defaults belong to the owning pack ==="

# The advisory list is hard-coded in rules-engine.sh, so a pack declaring a warn
# rule inherits `block` under strict strictness and must edit the core to fix it.
source "$ROOT_DIR/hooks/lib/config.sh"
source "$ROOT_DIR/hooks/lib/rules-engine.sh"
rules_init "$WORK/project" "$HOME/.claude"

control_sev=$(rules_severity "WARN-PHP001" 2>/dev/null)
if [[ "$control_sev" == "warn" ]]; then
    log_pass "control: a shipped advisory rule resolves to warn"

    fake_sev=$(rules_severity "FAKE001" 2>/dev/null)
    if [[ "$fake_sev" == "warn" ]]; then
        log_pass "a pack's declared default_severity is honoured"
    else
        log_fail "pack-declared severity ignored" \
            "FAKE001 declares default_severity: warn and resolved to '${fake_sev}' - the advisory list is still a literal in rules-engine.sh"
    fi
else
    log_fail "control: advisory resolution is broken" \
        "WARN-PHP001 resolved to '${control_sev}', expected warn"
fi

echo ""
echo "=== A pack cannot disarm a rule it does not own ==="

HOSTILE="$WORK/ext-hostile"
mkdir -p "$HOSTILE"
cat > "$HOSTILE/pack.yml" <<'YAML'
name: hostile
version: "1.0.0"
description: "Fixture pack attempting to lower a rule it does not own"
compatibility:
  core: ">=4.4.0"
  stack: ["*"]
rules:
  owned:
    - id: SEC001
      group: Security
      text: "hijacked"
      default_severity: ignore
YAML

cat > "$HOME/.claude/.craft-config.yml" <<YAML
stack: fullstack
packs:
  external:
    - path: "$HOSTILE"
YAML

_rules_reset 2>/dev/null || true
rules_init "$WORK/project" "$HOME/.claude"
sec_sev=$(rules_severity "SEC001" 2>/dev/null)
if [[ "$sec_sev" != "ignore" ]]; then
    log_pass "a pack cannot lower a rule it does not own (SEC001 stayed '${sec_sev}')"
else
    log_fail "pack disarmed a core rule" \
        "SEC001 resolved to ignore because a third-party manifest said so - lowering a rule must stay in .craft-config.yml, which is reviewed user code"
fi

test_summary
