# ADR-0031: Function-Hook Mods as a Companion Surface, Never a Gate

## Status

Accepted.

## Date

2026-10-06

## Context

Claude Code 2.1.291 loads a second kind of plugin: a *mod*, a TypeScript
module of function hooks (`register(on, options)`) that runs inside the
Claude Code process. A mod can draw panes, a band above the prompt, toasts and
a status line entry, register slash commands and tools, call a model
(`$.model.complete`), run host commands by argv (`$.process.run`), and hook
tool calls, prompts and the system prompt. The surface is marked EARLY ACCESS:
its declaration file says it "may change between releases without notice".

Three gaps in this repository line up with what a mod offers:

1. **The human gate of ADR-0020 is never crossed (#45).** Six weeks after the
   loop shipped, this repository's own database held eight candidates and no
   review. The review lives in the middle of `/craftsman:metrics`, a
   text-only skill the model runs: the person reads a list, then types or asks
   for `instincts approve <id> ...`. A decision that needs a person is
   reached through two hops of prose.
2. **Every gesture costs a fork.** `tests/perf/test-hook-latency.sh --report`
   measures `post-write-check.sh` at a 776 ms median and `pre-write-check.sh`
   at 723 ms on the reference Linux machine, per Write or Edit. A mod pays no
   fork for what it decides in process.
3. **ADR-0018 stopped at a missing switch.** Native `agent`/`prompt` hooks
   had no per-plugin-option gating, so semantic verification became headless
   `claude -p` subprocesses. A mod receives its `userConfig` values in
   `register(on, options)`, which is that switch.

Against that, three facts constrain any adoption:

- **Four front-ends share one core** (ADR-0029). Codex, Grok and Hermes read
  this repository's `hooks/hooks.json` and the packs; none of them loads a mod.
  CI never will. Anything a mod decides alone is a verdict the other
  front-ends cannot reproduce.
- **The API moves.** A mod written against 2.1.291 may stop loading on a later
  build. The enforcement plugin must not stop with it.
- **`metrics.db` is the single system of record** (ADR-0029), written through
  `metrics-query.py` and `instincts.py`, never through ad hoc SQL.

## Decision

Mods are a companion surface for Claude Code: they show what the core knows
and carry a person's gestures back to it. They never hold a verdict.

1. **Separate plugin, opt-in install.** A mod lives in `mods/<name>/` with its
   own `.claude-plugin/plugin.json` and `hooks/hooks.json`
   (`{"modules": [...]}`), and is listed in `.claude-plugin/marketplace.json`
   as its own plugin. It never goes into the `craftsman` plugin's
   `hooks/hooks.json`: other hosts read that file, and an early-access module
   that fails to load must not take the enforcement plugin down with it.
2. **No verdict, no rule, no SQL in a mod.** A mod reads and writes through
   the core's existing entry points (`bin/craftsman-helper`,
   `hooks/lib/instincts.py`), by argv, with no shell. When a mod needs data the
   core only prints for humans, the core grows a machine-readable subcommand
   with its own test. The mod never parses prose and never opens `metrics.db`.
   Blocking a write stays the job of the command hooks, whose parity the suite
   enforces.
3. **A human gate stays human.** A decision that ADR-0020 (or any later ADR)
   reserves for a person is reachable from a mod only through a gesture the
   person makes: a Button they press or a command they type. A mod registers
   no tool and no agent type that reaches such a decision, so the model cannot
   approve its own instinct.
4. **Locating the core is explicit, not guessed.** A mod finds
   `craftsman-helper` from, in order: its `helper` option, the session binding
   `~/.claude/craftsman/sessions/<session id>.json` (its `root`, and its
   `data` passed on as `CRAFTSMAN_PLUGIN_DATA`), the repository layout
   (`<mod>/../../bin/craftsman-helper`), then `PATH`. If none answers, the mod
   names the places it tried. It never falls back to a database of its own
   choosing.
5. **Tested where the API can be tested.** Each mod ships `*.test.ts` files for
   `claude plugin test`. `tests/mods/test-mods.sh` always checks the repository
   rules that need no engine (the mod is listed in the marketplace, its
   `hooks.json` holds modules only, its sources hold no SQL and register no
   tool), and runs `claude plugin validate` and `claude plugin test` on every
   `mods/*` folder when a `claude` binary is present, saying so when it skips.

The first mod is `craftsman-cockpit`: `/instincts` opens a pane listing the
project's candidate instincts with their evidence, in the Wilson-bound order of
ADR-0020, with *Approve* and *Reject* buttons wired to `instincts.py approve`
and `reject`. Approved instincts are listed below the candidates, so what has
been codified is visible in the same place.

## Consequences

### Positive

- The ADR-0020 review becomes one command and one keypress, with the
  evidence on screen, instead of a paragraph of the metrics skill.
- The core gains a JSON view of the instinct queue (`instincts_review.py`,
  reached as `craftsman-helper instincts review`),
  usable by any front-end: the missing half of Hermes' `inject` verb
  (ADR-0029 amendment) needs the same data.
- Mods give the project a place to try the other openings (a status band, a
  toast in place of the `tail -F` monitor, an in-process ADR-0018 verifier)
  without touching the enforcement plugin.

### Negative

- A second plugin to install, document and version. Mitigation: its version
  lives only in its marketplace entry, which `scripts/bump-version.sh`
  already carries; the mod's own manifest declares none.
- An early-access dependency. Mitigation: nothing that blocks a write depends
  on it, and the suite runs the mod's tests against the installed build, so a
  breaking change shows as a red mod test, never as a missing gate.
- One more path to the helper. Mitigation: the lookup order is fixed here and
  the pane names every place it tried.

### Neutral

- The `craftsman` plugin's behaviour on Claude Code, Codex, Grok, Hermes and
  CI is unchanged by this ADR.

## Alternatives Considered

### Alternative 1: The module in the craftsman plugin's own hooks.json

One install and no lookup problem, since `$.plugin.root` would be the core.
Rejected: Codex, Grok and Hermes read that manifest, and an early-access
module that does not load would be reported against the enforcement plugin.

### Alternative 2: Port the Level 1 validators into a mod for latency

Removes the 700 ms per write. Rejected: the validators would exist twice, once
for Claude Code and once for everyone else. That is the fork ADR-0029 forbids,
and `tests/ci/test-craftsman-ci.sh` could no longer prove the two agree.

### Alternative 3: An MCP tool the model calls to approve an instinct

No UI to build. Rejected: it hands the model the decision ADR-0020 reserves
for a person.

## Re-evaluate if

- The function-hook API leaves early access and another host loads the same
  modules: a mod could then become an adapter under ADR-0029 rather than a
  companion.
- Claude Code adds option gating to native `agent`/`prompt` hooks, which
  makes an in-process ADR-0018 verifier unnecessary.

## References

- [ADR-0018: Native Prompt and Agent Hooks](./0018-native-prompt-agent-hooks.md)
- [ADR-0020: Instinct Promotion With Human Review](./0020-instinct-promotion-human-review.md)
- [ADR-0029: Host Adapter Contract](./0029-host-adapter-contract.md)
- Claude Code 2.1.291 function-hook declarations (the `claude-code` module,
  laid in a loaded mod at `.claude-plugin/types/claude-code/index.d.ts`)
