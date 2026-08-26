#!/usr/bin/env bash
# =============================================================================
# Prove the Hermes plugin end to end, no agent required.
#
# Builds a throwaway repository and plays two pre_verify turns through the
# actual plugin module, the same code path a Hermes gateway drives: a blocked
# violation, then the fix. Then shows the rows the learning loop recorded and
# the context a future session would be handed. Everything runs local; the
# only requirements are python3, bash and git, the same as the plugin itself.
#
#   bash examples/hermes-agent/demo.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-demo.XXXXXX")
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA" "$WORK/repo/src"
: > "$CLAUDE_PLUGIN_DATA/.legacy-adopted"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK/repo"
git init -q .
git -c user.email=demo@demo -c user.name=demo commit -q --allow-empty -m init

ROOT="$ROOT_DIR" REPO="$WORK/repo" python3 - <<'PYEOF'
import importlib.util
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
repo = os.environ["REPO"]
spec = importlib.util.spec_from_file_location(
    "craftsman_demo", root / "adapters" / "hermes" / "craftsman_plugin.py")
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)

print("== Turn 1: the agent writes a TypeScript file with 'any' and tries to conclude")
(Path(repo) / "src" / "config.ts").write_text("const config: any = {};\nexport { config };\n")
directive = plugin.on_pre_verify(session_id="demo", coding=True, attempt=0, cwd=repo)
print(json.dumps(directive, indent=2))

print("\n== Turn 2: the agent applies the fix the directive named, and concludes")
(Path(repo) / "src" / "config.ts").write_text(
    "type Config = Record<string, string>;\nconst config: Config = {};\nexport { config };\n")
directive = plugin.on_pre_verify(session_id="demo", coding=True, attempt=1, cwd=repo)
print("gate answer:", directive, "(None = the turn is released)")

print("\n== What a future session's first turn would be handed")
context = plugin.on_pre_llm_call(session_id="later", user_message="hi", is_first_turn=True)
print((context or {}).get("context", "(nothing yet)"))
PYEOF

echo ""
echo "== The rows the learning loop recorded (metrics.db, source=hermes)"
python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
    "SELECT 'violation', rule, severity FROM violations WHERE source='hermes'"
python3 "$ROOT_DIR/hooks/lib/metrics-query.py" --raw "$CLAUDE_PLUGIN_DATA/metrics.db" \
    "SELECT 'correction', rule, action, context FROM corrections WHERE source='hermes'"
echo ""
echo "Install for real: docs/guides/hermes-quickstart.md"
