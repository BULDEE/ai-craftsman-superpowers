# craftsman-cockpit

Companion panes for the [craftsman](../../README.md) plugin on Claude Code
(ADR-0031). A mod shows what the core knows and carries your decisions back
to it. It never holds a verdict: enforcement stays in the craftsman plugin.

## Instinct review

`/instincts` opens a pane with the project's candidate instincts (ADR-0020),
best supported first, each with its fix and rejection counts and its evidence.
**Approve** writes the learned skill to `.claude/skills/learned-<rule>/`, and
**Reject** keeps the candidate out until new evidence builds up. Both run
`craftsman-helper instincts approve|reject`. Only your keypress triggers them:
the mod registers no tool the model could call. `r` refreshes.

## Install

Requires the craftsman plugin and Claude Code 2.1.291 or later (function hooks
are early access).

```
/plugin install craftsman-cockpit@ai-craftsman-superpowers
```

The mod finds `craftsman-helper` from its `helper` option, the session binding
the craftsman hooks write, this repository's layout, then `PATH`. If none
works, the pane lists every place it tried.

## Develop

```bash
claude --plugin-dir mods/craftsman-cockpit    # load from disk
claude plugin validate mods/craftsman-cockpit
(cd mods/craftsman-cockpit && claude plugin test .)
bash tests/mods/test-mods.sh
```
