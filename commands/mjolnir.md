---
name: mjolnir
description: "Show Mjolnir companion status — session forge stats and a contextual replique from the Norse forge."
effort: quick
---

# /craftsman:mjolnir — Forge Status

Display session quality stats through the eyes of the Norse forge companion.

## Process

1. Read session state using the **Bash** tool:

```
bash -c '
BRIDGE="${HOME}/.claude/craftsman-session-state-path"
if [ -f "$BRIDGE" ]; then SF=$(cat "$BRIDGE"); else SF="${HOME}/.claude/plugins/data/craftsman/session-state.json"; fi
[ -f "$SF" ] && cat "$SF" || echo "{}"
'
```

2. Parse the JSON and extract:
   - `blocked_violations` — count of files with active violations
   - `patterns` — count of cross-file patterns
   - Total violation rules across all files
   - `verified` — whether session is verified

3. Present the forge report:

```
⚒ FORGE STATUS
━━━━━━━━━━━━━━━━━━━━━━
Blades tested:    <files with violations>
Flaws found:      <total violation rules>
Patterns:         <cross-file patterns>
Forge sealed:     <verified yes/no>
━━━━━━━━━━━━━━━━━━━━━━
⚒ Mjolnir: "<contextual replique>"
```

4. Choose the contextual replique based on state:
   - **0 violations + verified** → "The forge is silent. All steel holds."
   - **0 violations + not verified** → "Clean steel. Seal the forge."
   - **1-3 violations** → "Cracks remain."
   - **4+ violations** → "The anvil weeps."
