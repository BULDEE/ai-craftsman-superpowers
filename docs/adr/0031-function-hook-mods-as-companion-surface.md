# ADR-0031: Function-Hook Mods as a Companion Surface, Never a Gate

## Status

Accepted (amended 2026-10-20: the API left early access; amended 2026-10-24:
the module moves into the craftsman plugin. See the Amendments).

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

## Amendment (2026-10-20): the API left early access, the companion stays

The context above describes Claude Code 2.1.291, whose declarations carried
"EARLY ACCESS: this surface may change between releases without notice". The
public copy of those declarations (`mods/types/claude-code.d.ts`, written by
2.1.277) still does. The installed 2.1.304 binary holds no such string, the
mods documentation makes mods on by default from v2.1.287 and describes
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` as a flag of the early-access period that
later builds ignore. The surface is a released one.

What that changes:

- The first "Re-evaluate if" condition is half met: the API is out of early
  access, and no other host loads a hooks module. The companion decision
  stands on the second half alone, which ADR-0029 already states: a verdict
  the other front-ends cannot reproduce is not a verdict. Nothing in the
  Decision section moves.
- The "API moves" constraint is kept, downgraded from "may stop loading" to
  the ordinary drift of a versioned surface: the mods reference still says
  events and methods can change between versions, so the mod's tests keep
  running against the installed build and the mod's README names the builds
  it was tested on, as the documentation asks.
- The floor stays 2.1.291, the build the mod was written and tested against,
  not 2.1.287, the build the documentation names: `$.state` and the
  `atom`/`read`/`update` helpers this mod relies on were not checked on
  anything older.

## Amendment (2026-10-24): the module moves into the craftsman plugin

Decision 1 kept the module out of the craftsman plugin for two reasons: other
hosts read `hooks/hooks.json`, and a module that fails to load must not take
the enforcement plugin down with it. Both were measured, and neither holds.

- **Other hosts never see it.** The plugins reference says a manifest's
  `hooks` key *merges* with the default file: "The default file loads first,
  and what the manifest declares merges into it". So `.claude-plugin/plugin.json`
  names `hooks/claude-code.json`, which holds the module and nothing else,
  while `hooks/hooks.json` stays the one file every host reads, with no module.
  Codex and Grok read `hooks/hooks.json` from their own manifests
  (`scripts/native-manifests.py`), Hermes reads neither.
- **A module that fails leaves the gate running.** Measured on Claude Code
  2.1.310 with a throwaway plugin: a module that throws at import, and one that
  does not parse, both print `hooks module did not load`, and the plugin's own
  SessionStart command hook still ran; the same when the module sits in
  `hooks/hooks.json` beside the command hooks. The mods documentation says the
  same of a running module: "Command, HTTP, prompt, and agent hooks in
  settings files and in plugins' hooks/hooks.json run as before, alongside
  mods", and "A hook that fails doesn't break the session".
- **Older builds ignore it.** Claude Code 2.1.218, the minimum this plugin
  declares, loads the plugin, runs its SessionStart and UserPromptSubmit
  hooks and passes `claude plugin validate`, with the module file ignored
  silently. 2.1.286, where function hooks were still switched off by rollout,
  prints `hooks module not loaded: hooks modules are turned off ...` once per
  session and runs the command hooks.

The separation had a measured cost. The cockpit found the core through the
session binding, the repository layout, then `PATH` (decision 4), and two
field failures came from that lookup alone (CR-279, a binding naming the
plugin root of the previous version; CR-291, a Claude Code session taken for a
Codex one, so no binding at all). Inside the plugin, `$.plugin.root` is the
core.

What changes:

- **Decision 1** becomes: the module ships in the craftsman plugin
  (`mods/cockpit/`), declared by `hooks/claude-code.json`, which only Claude
  Code's manifest names; `hooks/hooks.json` holds no module.
  `tests/mods/test-mods.sh` checks both, and that no other host's manifest
  names the module file. The former `craftsman-cockpit` plugin stays in the
  marketplace for one release as an empty plugin, so that updating it removes
  the old module instead of registering `/instincts` twice.
- **Decision 4** becomes: the helper is `$.plugin.root/bin/craftsman-helper`.
  The session binding only supplies the data directory the hooks bound for the
  session; a binding for another session supplies nothing.
- **Decisions 2, 3 and 5 stand.** The new surfaces read a machine-readable
  subcommand with its own test, `craftsman-helper session status`
  (`hooks/lib/session_status.py`): a line above the prompt with the session's
  writes, open blocks, warnings and test verdict, redrawn after each write the
  hooks judge, and a line under each answer that changed them. Neither decides
  anything. The module still registers no tool.

One opening this ADR listed is closed instead: replacing the
`craftsman-test-failures` monitor with a toast. The monitor's output "reaches
Claude as notifications" (plugins components reference): its reader is the
model, which reacts to a red background run. A toast would move that
information from the model to the person, and the person already reads red
tests in the band.

## References

- [ADR-0018: Native Prompt and Agent Hooks](./0018-native-prompt-agent-hooks.md)
- [ADR-0020: Instinct Promotion With Human Review](./0020-instinct-promotion-human-review.md)
- [ADR-0029: Host Adapter Contract](./0029-host-adapter-contract.md)
- Claude Code 2.1.291 function-hook declarations (the `claude-code` module,
  laid in a loaded mod at `.claude-plugin/types/claude-code/index.d.ts`)
