# The craftsman cockpit

A function-hook module that ships in the [craftsman](../../README.md) plugin
and runs on Claude Code 2.1.291 or later (ADR-0031). It shows what the core
knows and carries your decisions back to it. It never holds a verdict:
enforcement stays in the command hooks, which every host runs.

## What it draws

- **A line above the prompt**, once the session has something to report: the
  writes the gate judged, the blocks still open with their rule and file, the
  warnings, and what the tests say (red with the run, verified, a run that
  tested nothing, not run). It is redrawn after every write the hooks judge.
  Ctrl+X then Ctrl+A folds it away.
- **A line under each answer** that changed it, as in
  `craftsman: 3 writes, 1 blocked, 0 warnings · 1 open: LAYER001 Order.php · tests not run`.
  A turn that only read or talked leaves none.
- **`/instincts`**, a pane with the project's candidate instincts (ADR-0020),
  best supported first, each with its fix and rejection counts and its
  evidence. **Approve** writes the learned skill to
  `.claude/skills/learned-<rule>/`, and **Reject** keeps the candidate out until
  new evidence builds up. Only your keypress triggers them: the module
  registers no tool the model could call. `r` refreshes.

All three read `bin/craftsman-helper` under this plugin's own root
(`session status`, `instincts review|approve|reject`), with the session id and
the data directory the craftsman hooks bound for the session.

## Where it is declared

`.claude-plugin/plugin.json` names `hooks/claude-code.json`, which holds the
module and nothing else. Claude Code merges that file with `hooks/hooks.json`;
Codex and Grok read `hooks/hooks.json` from their own manifests and never see
the module. A module that fails to load leaves the command hooks running
(measured on 2.1.310: `hooks module did not load`, and the plugin's
SessionStart hook still ran).

The pane was tested on 2.1.291 and 2.1.304, the band and the receipt on
2.1.310; the mods documentation names no later floor for the events they use.
Events and methods can change between builds, so the module's tests run
against the installed one.

## Develop

```bash
claude --plugin-dir .         # load the plugin, module included, from disk
claude plugin validate .
claude plugin test .          # mods/cockpit/tests/*.test.ts
bash tests/mods/test-mods.sh
```

Before 4.14.0 the cockpit was a separate plugin, `craftsman-cockpit`. Its
marketplace entry is now an empty plugin so that updating it removes the old
module; uninstall it.
