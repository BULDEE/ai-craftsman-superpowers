# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [4.8.1] - 2026-08-11

### Changed

- **`tests/core/test-config.sh` split into 21 section functions.** The last
  whole-file span in the top three structural offenders: complexity 102 to
  10, longest span 505 to 30 lines, 90 assertions before and after (proved
  against HEAD), shared inter-section state kept deliberate and commented.
  SH002 blocked two oversized intermediate functions during the campaign and
  both were re-split instead of suppressed. `file_lines` 505 to 577 is the
  function boilerplate paid for it, recorded in the baseline with that
  reason.

## [4.8.0] - 2026-08-11

### Changed

- **Structural debt campaign, first production run of `/craftsman:loop`.**
  The two worst production offenders in the ratchet baseline were extracted
  under their marks with behaviour intact (full suite green at every
  iteration): `hooks/session-metrics.sh` worst-span complexity 37 to 8 and
  longest span 131 to 16 lines (duration, write counter, violation counter
  and summary builder each became a function); `hooks/lib/dispatch-context.sh`
  complexity 28 to 11 and longest span 97 to 27 (one emitter function per
  context section, early returns instead of nesting). The `file_lines` rises
  (131 to 149, 97 to 110) are the function boilerplate paid for it and are
  recorded in the baseline with that reason; every other mark tightened
  one-way.

## [4.7.0] - 2026-08-11

### Added

- **`/craftsman:loop`: bounded verification loop.** The "repeat" layer on top
  of the pipeline: a loop card (goal, verify command, max iterations, stop
  conditions, escalation question), one atomic act per iteration, a full
  verify after each, and an iteration ledger. Stops on green, on two
  identical failure sets (no_progress), or on budget; always ends with a
  verdict. The verify command is the only judge and no iteration may weaken
  it. Cross-turn cadence hands off to the native `/loop` runner; in-session
  iteration is the default.
- **`tests/core/test-gate-independence.sh`.** Auto mode becomes the default
  permission mode on 2026-08-14; the hooks reference evaluates a PreToolUse
  deny before the permission system, so the only way auto mode could soften
  a gate is a hook reading `permission_mode` and deciding to. The suite now
  proves the blocking gates answer identically under `default`, `auto` and
  `bypassPermissions`, that clean content still passes, that Level 1 ignores
  the effort dial, and a static guard fails the build if any hook ever reads
  `permission_mode`.
- **`docs/guides/context-footprint.md`.** What the plugin injects per
  session and per event, how to measure it (`/usage`, plugin context cost,
  hook profiles), and which knobs reduce it, with one fixed rule: a blocking
  verdict is never traded for context savings silently.

### Changed

- **The advisory Haiku layer respects the effort dial.** At
  `CLAUDE_EFFORT=low` the headless semantic verification steps aside
  (`haiku_verify` returns before spawning anything). Deterministic Level 1-3
  gates never read the variable: hook and CI front-ends must answer the same
  verdict for the same file, and the new gate-independence tests enforce
  both sides.
- **`/craftsman:team` offers the native Workflow tool as an explicit
  opt-in.** Scripted, deterministic fan-outs (find then verify stages,
  resume cache) for pipelines whose stages are known before launch; teams
  remain the default for exploratory collaboration. Never auto-triggered.
- **`/craftsman:workflow` documents the native `/goal` mapping.** Outcome
  Contract "Done when" lines are written to be pasted into `/goal` verbatim;
  the mapping stays documentation because the Stop-hook final review is
  already the plugin's completion loop.
- **`/craftsman:challenge` states its position vs native reviewers.**
  `/code-review`, ultrareview and security-guidance hunt correctness and
  vulnerability bugs; challenge judges architecture and DDD against the
  rules engine, the violation history and CI-parity severity. Verdicts stay
  separate on purpose; no finding ingestion, no format coupling.
- **`/craftsman:metrics` publication is explicit, never a side effect.**
  Every view stays on the machine unless the user asks for a published page
  in so many words in the current session.
- **`/craftsman:debug` points long reproductions at the native Monitor
  tool** instead of sleep-and-recheck polling.
- **ADR-0028 addendum.** The fork premise is re-dated: the current harness
  documents full-conversation inheritance for forked subagents, attachments
  remain unverified, and the decision stands on the delivery contract, which
  is fork-agnostic.
- **ADR-0019 amendment.** LSP verdicts are model-plane: no hook, and
  therefore neither the precedence layer nor the rules engine, ever sees
  them, so a `supersedes:` entry targeting an LSP would drop a rule, not
  defer it. `supersedes:` stays restricted to executable analysers the
  engine invokes and parses; LSP remains the complementary Level 1.5.

## [4.6.4] - 2026-08-10

### Fixed

- **`/craftsman:challenge` returned nothing at all, one run in two.** The skill
  forked into `craftsman:architect`, which declared `maxTurns: 20`. When the cap
  lands on a tool call the agent loop stops there and returns no text, and Claude
  Code's forked-command handler substitutes the literal string `Command
  completed` for the missing result, then ends the turn with `shouldQuery:
  false`. No error, no partial, no retry: the user saw one line of output and a
  dead prompt. 23 of the agent's first 38 recorded runs ended that way. Every
  truncated subagent transcript on the machine was this agent, all at exactly 20
  turns with `stop_reason: tool_use`, and no other agent type ever truncated.
- **The review could not see what it was reviewing.** A forked skill receives its
  `SKILL.md` as a plain string: text arguments are appended as `ARGUMENTS:`,
  attachments are not carried, and the conversation is not carried either. A
  review invoked with seven screenshots received seven `[Image #14]` tokens and
  zero images, and one asked to look at what the user had just been discussing
  derived its scope from `git log` and reviewed a different subsystem. The skill
  now runs in the main session (ADR-0028) and fans out to reviewer subagents,
  writing their prompts, when the scope is large.
- **`craftsman:architect` reviewed a tree in which the diff did not exist.** It
  declared `isolation: worktree` while declaring no `Write` or `Edit`. A worktree
  is a clean checkout of a commit, so the uncommitted changes its injected
  `git diff HEAD` context points at are absent from it. Removed.

### Added

- Every agent declaring `maxTurns` now carries a `## Turn Budget` contract: emit
  the deliverable as soon as the evidence justifies it, reserve the last third of
  the budget for writing, name what was not covered under `NOT REVIEWED`, and
  never end on a tool call. Applied to all twelve capped agents, core and packs.
  The cap was never the whole defect, since an agent that keeps no budget for
  writing fails at any cap, so the contract is what is enforced rather than a
  number. `craftsman:architect` also moves to `maxTurns: 60`.
- `tests/core/test-turn-budget.sh` fails when a capped agent lacks the delivery
  contract, when a read-only agent declares `isolation: worktree`, and when a
  skill forks into an agent that can return nothing. Each check ships with a
  fixture proving it can go red, and the contract check was verified red against
  the real `agents/architect.md` before being restored.
- `tests/core/test-invocation-policy.sh` no longer fails merely because no skill
  forks. Zero forks is now the intended state, so the fork/model agreement check
  proves its liveness against a mismatched fixture pair instead.

## [4.6.3] - 2026-08-09

### Fixed

- **The deptrac adapter had never produced a single verdict.** It called
  `--formatter=compact`, a formatter that exists in no version of deptrac, not
  1.x, not 2.x, not 4.x. The call failed, the output was swallowed by
  `2>/dev/null` and `|| true`, and `DEPTRAC001` was never emitted once. Every
  layer violation ever reported by this plugin came from the import regex in
  `layer-validator.sh`; the architecture analysis users believed they were
  running was silently absent. Nothing caught it because no test asserted that
  the analyser produced output, only that the code path ran. The adapter now
  reads `github-actions` output, verified against deptrac 4.7.1 rather than a
  stub.
- **A project could not configure the severity of a layer verdict.** deptrac
  findings arrived under `DEPTRAC001`, so a `LAYER001: warn` in a project's
  `.craft-config.yml` had no effect on them: the doctrine was silently ignored
  the moment the tool was installed. Verdicts now carry the plugin's own
  `LAYER001` to `LAYER004` codes, so `block`, `warn` and `ignore` produce three
  different outcomes where all three previously produced `exit 2`. A violation
  matching none of the four layer pairs still reports under `DEPTRAC001` rather
  than being filed under an approximate code.

### Changed

- The symfony pack declares `vendor/bin/deptrac=LAYER001,LAYER002,LAYER003,LAYER004`
  under `supersedes:`, which makes the level precedence shipped in 4.6.2 active
  for the first time: where deptrac answers, the regex finding is deferred, and
  where deptrac is absent, times out or is configured not to check the
  boundary, `precedence_flush` re-emits it.
- `packs/symfony/static-analysis/phpstan.sh` splits its single 45-line function
  into eleven named ones. Complexity falls from 19 to 6 and the longest
  function from 68 to 21 lines.

## [4.6.2] - 2026-08-09

### Fixed

- **`/craftsman:team` gated native teams on a tool Claude Code had removed, so
  every session degraded to parallel subagent dispatch.** The skill and the
  `team-lead` agent treated a missing `TeamCreate` as proof of a broken
  environment. Claude Code deleted `TeamCreate` and `TeamDelete` in v2.1.178:
  the team is now created automatically at session start under a session-derived
  name, and the runtime lists both tools among those whose absence is expected.
  The check could therefore only ever fail, which made the degraded path the
  only reachable one and printed "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set"
  at users who had set it. Native teams now gate on that variable alone, the
  spawn step reads the existing `~/.claude/teams/<team-name>/config.json`
  instead of creating anything, and teammates are spawned with an explicit
  `name` rather than the `team_name` input the runtime ignores. `TeamCreate` is
  gone from the `team-lead` tool list.
- **`teammateMode` was documented as a requirement with two values that do not
  exist.** It gates the display only and never blocks a team. The real values
  are `in-process` (the default since v2.1.179), `auto`, `tmux` and `iterm2`;
  the skill previously demanded `"iterm"` or `"tmux"`.
- **The plugin entry in `marketplace.json` still advertised 4.5.0** while the
  marketplace root and every other version anchor had moved on.

### Added

- `tests/core/test-invocation-policy.sh` fails when a call to, or a conditional
  on, `TeamCreate` or `TeamDelete` reappears in the team skill or the
  `team-lead` agent. Prose documenting the removal stays legal. The check was
  verified red against a reintroduced call before being kept.
- **Level precedence between validation levels**, in `hooks/lib/precedence.sh`.
  A rule a Level 2/3 analyser owns is declared by its pack under `supersedes:`
  and is DEFERRED, never dropped: the Level 1 finding is held, the analyser
  emits directly and declares the codes it answered for, and `precedence_flush`
  re-emits everything left over with full severity resolution.
  No verdict is not a clean verdict, so a `sa_timeout` at 124 on a cold start,
  a crashed analyser, or one configured to ignore the rule all end with the
  regex reporting. That property is what keeps a project's tool configuration
  from silently disabling a `block` rule the machine owner declared, and it is
  why deferring was chosen over the simpler "never supersede a blocking rule":
  `TS001`, `PHP002` and `LAYER004` are all `block`, so that restriction would
  have emptied the feature instead of fixing it.
  `lang_registry.py` refuses at compile time any claim where a tool would
  outrank its own verdicts. Metrics record both outcomes, a covered rule with a
  `superseded` marker and a flushed one normally, so correction learning never
  reads "resolved" where the truth is "silenced".
  No pack declares `supersedes` yet: the mechanism ships inert, pending the
  adapter work that emits layer verdicts under the plugin's own rule codes.

## [4.6.1] - 2026-08-08

### Fixed

- **The hook/pipeline drift test compared two copies of a list that had stopped
  being the source of truth.** Both `_rules_is_advisory` and its mirror in
  `ci/craftsman-ci.sh` are fallbacks, read only when the rules engine cannot be
  sourced, and neither knows what a pack declared. A rule its owner marks `warn`
  in a manifest therefore still resolved to `block` in that degraded mode, so
  the pipeline would block a file the hooks let through. Comparing the two
  copies against each other could never see it. The suite now also checks every
  advisory rule in the registry against the CI fallback, and `rule_ids()` was
  added so callers can walk the doctrine without reading the TSV directly.

## [4.6.0] - 2026-08-08

### Added

- **Packs own the rules they enforce.** `ci/doctrine-export.sh` held every rule
  id, its section and its wording in four constants and a 38-branch case, and
  `hooks/lib/rules-engine.sh` held the advisory defaults, so a pack shipping
  `DART001` had nowhere to declare any of it. A pack now lists its rules under
  `rules.owned` in `pack.yml` with an id, a group, a sentence and a
  `default_severity`, and `hooks/lib/rule-registry.sh` compiles those manifests
  into the registry that both the exported doctrine and the severity resolution
  read.

  Rules belonging to no pack live in `rules/core.yml`: layer boundaries,
  security and structural metrics apply across every language, so attaching
  them to symfony or react would cost a React-only project its layer rules.
  That file also fixes the order sections appear in; a pack introducing a group
  of its own gets it appended.

  Two ids colliding is refused rather than resolved by load order, which would
  make the same install document two different wordings depending on discovery
  order. Core rules win outright: a third-party pack declaring `SEC001` with
  `default_severity: ignore` cannot disarm it from its own manifest, whichever
  order the manifests are read in. Lowering a rule stays in
  `.craft-config.yml`, which is reviewed user code.

- **Packs contribute their own command suggestions.** `routing-table.sh`
  matched pack names as literals, so a pack the engine had not been taught
  about never appeared however many commands it shipped. A pack declares
  `routes:` as trigger and command pairs.

## [4.5.0] - 2026-08-08

### Added

- **`ratchet.py init <file>` requires `--reason`, and records it.** A scoped
  init is the only way to raise a budget, and the entry stores numbers only, so
  a reviewer saw a figure go up with nothing about why. That is how a ratchet
  becomes a rubber stamp. Naming a directory or nothing at all stays free: that
  is adoption and `--repair`, and `init .`, `init src` and `init deep` are the
  forms three suites already use. The reason survives later `update` calls,
  which rebuilt the entry from the measurement and dropped it.

### Fixed

- **`max_fn_lines` and `complexity` measured the gap between functions, not the
  functions.** A span ran from one header to the next, charging every line
  between them to the earlier one. In a sequential script that is the whole
  file: `run_file_changed` in `tests/core/test-hooks.sh` is seven lines and
  measured 600, and the file scored 119 decision points it does not contain.
  Five of the eight `max_fn_lines` drifts open at the time were this artefact,
  and acting on them would have meant restructuring 1720 lines of working tests
  to satisfy a broken instrument.

  Spans now end where the body ends: brace-delimited on balance,
  indentation-delimited on the first line indented no deeper than the header,
  with a fallback to the previous bound. The computation can only narrow a span,
  so it cannot turn a passing file into a regression. `test-hooks.sh` drops from
  600/119 to 11/2.

## [4.4.1] - 2026-08-08

### Fixed

- **`tests/templates/test-templates.sh` was never executed.** `run-tests.sh`
  named `tests/core/`, `tests/ci/` and `tests/adapters/` file by file and
  globbed `tests/packs/`, but nothing mentioned `tests/templates/`. Sixty-eight
  assertions, four of them red, sat outside every run while the suite reported
  green and `CLAUDE.md` documented the file as a validation command. It is now
  called from `main()` like the others.

- **Four of its assertions targeted an architecture the project had left
  behind.** Section 8 opened `skills/entity`, `skills/usecase`,
  `skills/component` and `skills/hook`, one skill per scaffold type. Scaffolding
  was unified into `skills/scaffold/SKILL.md` well before this, so all four
  reported "command file not found". The section now checks the unified skill,
  and reads the template list from `packs/*/templates/` instead of repeating the
  six names: naming them in the test is how it drifted, and a pack shipping a
  seventh template would have stayed invisible. A guard against the empty case
  keeps the loop from passing vacuously.

- **`test-runner-integrity.sh` existed to catch exactly this and did not.** It
  verifies that every test file is reachable from the runner, but enumerated
  the directories to walk rather than discovering them, and `tests/templates/`
  was missing from that list. The guard now covers `tests/adapters/` and
  `tests/templates/` as well. `tests/lib/` stays out on purpose: it holds
  `test-helpers.sh`, a library the suites source rather than a suite the runner
  calls.

## [4.4.0] - 2026-08-08

### Added

- **Packs declare the languages they cover, and the engine holds no list of its
  own.** A `languages:` block in `pack.yml` names the extensions, validators,
  static-analysis tools, test commands, entry markers, protected config files,
  LSP server and metrics dialect for each language a pack contributes.
  `hooks/lib/lang-registry.sh` compiles those manifests into one flat TSV,
  cached on disk and invalidated by manifest mtime, and exposes `lang_for_file`,
  `lang_capability` and `pack_dispatch_file`. Adding the fiftieth language is
  adding a fiftieth pack, with no edit anywhere else.

  Validator functions are discovered by prefix rather than declared twice: a
  pack shipping `pack_validate_php`, `_php_layers`, `_php_persistence` and
  `_php_security` gets all four called, so a manifest cannot drift from its own
  scripts.

### Changed

- **BREAKING for pack authors: `languages:` is now required to dispatch.** A
  pack without it loads, registers its agents and knowledge, and validates
  nothing. Packs published before this release need the block added. In
  practice nothing regresses: the dispatch was a literal `case "$EXT" in
  php|ts|tsx)` duplicated across ten call sites, so a third-party pack was
  already never reached. That is the defect this release closes, and the reason
  it ships as a minor rather than a major.

- **Rule severity is resolved for warnings too.** `add_warning` wrote straight
  to the warning list, bypassing `rules_severity_for_file` and
  `craftsman-ignore` alike. SH001 was declared a blocking rule in
  `ci/doctrine-export.sh` and emitted as a warning, and no configuration in
  either direction could reach it. Warnings now flow through the same
  resolution as violations; DB001-003, PY003, SH001, SH003 and SH005 are
  declared advisory so today's behaviour is unchanged and a project can now
  promote or silence them.

- **`craftsman-ci` is faster than before this release despite doing more.**
  `_pack_yml_nested_array` read each manifest line by line, running
  `echo "$line" | grep` up to three times per line, and `pack_loader_init`
  calls it once per capability per pack. One awk pass replaces it: pack loading
  went from 2891ms to 743ms, and a full `craftsman-ci` invocation from 2257ms
  to 1597ms.

### Fixed

- **The `python` and `bash` packs never ran in CI.** `scan_paths` walked only
  `*.php`, `*.ts` and `*.tsx`, and `scan_file` returned 0 on everything else.
  PY001-005 and SH002-005 blocked on write and passed in the pipeline, while
  `README.md` and `CLAUDE.md` both claimed the two front-ends could not
  disagree. This repository is itself 124 shell scripts and 18 Python files.

- **One PHP file silenced the empty-gate guard for every other language.**
  `FILES_DISCOVERED` counted only `php|ts|tsx`, so a mixed repository reported
  `No issues found in 1 file(s)` with unvalidated Python and Bash beside it.
  Discovery now counts any extension an installed pack declares, which keeps
  "excluded by stack" distinct from "never discovered": a `.php` file under
  `stack: react` remains a legitimate pass.

- **`tests/core/test-external-packs.sh` asserted the wrong thing.** It checked
  that `pack_validate_go` was callable after loading, never that it was called
  on a `.go` file, and stayed green while the feature was dead. Replaced by
  `tests/core/test-lang-registry.sh`, which drives real fixtures through the
  hook, the pipeline and the rules engine, and pairs every assertion with a
  known-good control so a red result cannot be confused with a broken harness.

- **`test-doctrine-export.sh` reported drift that did not exist.** Its
  recursive grep matched the `__pycache__` files that now appear once
  `hooks/lib` modules import each other, and `Binary file ... matches` entered
  the rule list.

### Removed

- **The `session-init` skill.** Nothing invoked it: no hook, no manifest, and
  `disable-model-invocation: true` kept the Skill tool away. Session context is
  loaded by `hooks/session-start.sh`, which it duplicated. Its command list had
  also drifted, still advertising `/craftsman:parallel` and omitting `team`,
  `legacy`, `workflow`, `healthcheck` and `metrics`. The two test exemptions it
  carried were the symptom, not the special case, and are gone with it.

- **`cargo test`, `go test` and `rust-analyzer` are no longer recognised.**
  They were literals in the test-detection regex and the LSP probe, and no
  shipped pack claims them. A Rust or Go project therefore loses its
  deterministic verification trigger and its LSP hint until a pack for that
  language declares them. This is the visible cost of the rule that a language
  exists because a pack contributes it.

### Changed

- **The structural baseline is enforced in CI and was repaired first.** 59 of
  its 146 rows had drifted since the initial photograph, and one pointed at a
  deleted file, so touching 40% of the repository raised a RATCHET001 nobody
  could clear. A gate that is red by default teaches people to scroll past it.
  `ratchet init --repair` re-photographed the tree (168 rows, 0 drift, 23
  files that had never been covered at all), and a new `structural-ratchet`
  job checks every file a pull request touches against the committed baseline.
  The local hook stays advisory; CI is the blocking half. Loosening a budget
  is still allowed through `ratchet init <file>`, which puts the new numbers
  in the diff where a reviewer sees them.

## [4.3.3] - 2026-08-04

### Fixed

- **`ratchet.py init <path>` deleted every baseline row it was not given.**
  The command built its result from an empty dict and saved that, so scoping
  it to one file dropped the other 145 rows of `.craftsman-baseline.json`
  without a warning. The documented way to repair a single stale row was the
  fastest way to destroy the whole debt record. A whole-tree `init` still
  replaces the baseline, which is the ADR-0025 adoption path and what
  `init --repair` rebuilds; with explicit paths it now loads the baseline
  first and re-photographs only what was named.

- **The team skill never printed "No active teams running."** In
  `ls ~/.claude/teams/*.json | xargs -I{} basename {} .json || echo …` the
  `||` reads the pipeline's exit code, which is `xargs`', not `ls`'. With no
  team configured the branch was unreachable and the skill injected an empty
  line instead of the message. A `| grep .` before the `||` restores it.

## [4.3.2] - 2026-08-04

### Fixed

- **`/craftsman:challenge` was unusable outside a git repository.** The skill
  injects live context with Claude Code's `` !`command` `` syntax, which the
  harness expands *before* the skill loads. A pattern that exits non-zero
  aborts the whole invocation: the prompt is discarded and the user only sees
  `Error: Shell command failed for pattern "!`git log --oneline -10 2>/dev/null`"`.
  Of the five injected patterns, `git log` was the only one without a fallback.
  Its `2>/dev/null` silenced the message but not the exit code, which is 128
  outside a repository, so running the skill from a home directory or any
  non-versioned folder lost the prompt every time.

  The three git-backed patterns are now guarded by `git rev-parse --git-dir`
  and fall back to `no git context available`. The guard also covers a
  repository with no commits yet, where `git diff HEAD` and `git log` fail for
  a different reason. Version control is context, never a prerequisite: the
  plugin reviews code the same way in a directory that has never seen git.

### Added

- `tests/core/test-dynamic-context.sh`: executes every `` !`...` `` pattern
  declared under `skills/` in a directory with no git repository, no metrics
  database and no generated codemap, and fails on any non-zero exit. Verified
  red on the exact defect (exit 128) before being verified green on the fix.

## [4.3.1] - 2026-07-29

### Fixed

- **The plugin errored on every machine without intelephense.** The bundled
  `.lsp.json` assumed Claude Code starts a declared LSP server only when its
  binary is already installed. It does not: the declared command is spawned
  unconditionally, and a missing binary surfaces as
  `Command failed with ENOENT: intelephense --stdio` in the `/plugin` Errors
  tab. That contradicted the graceful-degradation contract (ADR-0019) the
  file was shipped under. The `.lsp.json` is removed; PHP Level 1.5 now goes
  through Anthropic's official `php-lsp` plugin, which carries the exact same
  intelephense configuration as an explicit opt-in, and the healthcheck hints
  point at the official per-language LSP plugins. ADR-0019 is amended
  accordingly, and `tests/core/test-lsp-policy.sh` fails if an `.lsp.json` or
  a manifest `lspServers` declaration ever comes back.

## [4.3.0] - 2026-07-29

The agents join the system they were supposed to be part of. Before this
release an agent was a fourth front-end without parity: it carried its own
copy of the rules, re-derived structure the plugin had already computed, and
nothing it produced fed the learning loop. Each fix below was reproduced
before it was fixed and carries a test that fails if it regresses.

### Fixed

- **The orchestrator told the model to run skills the model cannot run.**
  Sixteen of twenty-two skills carry `disable-model-invocation: true`, which
  means only the user can start them by typing the slash command first in a
  prompt. `/craftsman:workflow` nonetheless announced "Invoking
  /craftsman:design..." for four of its seven steps, and five agents listed
  locked skills in `skills:` frontmatter. Every one of those references was
  unreachable: the Skill tool answers `cannot be used with Skill tool due to
  disable-model-invocation` and the pipeline stops there. The workflow now
  hands off, printing the exact command to paste and waiting, and the nine dead
  agent references are gone.
- **`/craftsman:team` could not be started by anything except a bare prompt.**
  It was classified as a heavy review in ADR-0017 and given
  `disable-model-invocation: true`, so no orchestrator could reach it. The flag
  is dropped and the skill is model-invocable. It stays out of a fork on
  purpose: it asks the user which template to use and calls `TeamCreate` to
  spawn teammates into the session, and a fork would strand both.
- **An agent could be told to fork into itself.** `agents/architect.md`
  declared `craftsman:challenge`, which is bound to `agent: craftsman:architect`.
  Same shape in `agents/team-lead.md` for `craftsman:team`.

- **The subagent quality gate validated nothing.** Its header said "validates
  code produced by subagents against craftsman rules"; its body logged an
  agent_type and a timestamp. It now reads the subagent's transcript, runs
  every file the subagent wrote through the same pack validators as the hooks
  and CI, records each finding in the metrics DB tagged
  `subagent:<agent_type>`, and surfaces the findings to the main loop as
  additionalContext. Silence remains the pass signal, and the gate stays
  non-blocking.
- **The agent context injector never reached an agent.** The old
  `agent-structure-analyzer.sh` asked each agent to re-scan the repository,
  from a hook on `InstructionsLoaded` - a side-effects-only event whose output
  the platform ignores, aimed at an event that does not fire on agent dispatch
  anyway. Removed. Agents now start by running
  `hooks/lib/dispatch-context.sh`, which returns the resolved doctrine (same
  rules engine as hooks and CI), the HEAD-cached codemap, the top hotspots and
  the correction trends: one deterministic turn instead of a self-guided scan.
- **A review could silently run a tier below what the docs promise.**
  `challenge` declares `model: opus` and forked into an `architect` declaring
  `model: sonnet`; the platform does not document which wins. `architect`,
  `legacy-surgeon` and `team-lead` now declare `opus`, matching the reference
  table, and the invocation-policy test fails any forking skill whose bound
  agent disagrees on the model.
- **`subagent-quality-gate.sh` printed a bare counter onto its JSON channel.**
  `session_state.py increment` echoes the new value; the hook never silenced
  it, so every SubagentStop emitted a stray `1` on stdout.

### Added

- `hooks/lib/dispatch-context.sh`: single source of start-of-dispatch context
  for all 12 agents (resolved doctrine, cached codemap, hotspots, correction
  trends). The agent is a front-end of the rules engine like hooks and CI:
  it no longer carries its own copy of the rules.
- Per-agent violation metrics: the `source` column now distinguishes
  `subagent:<agent_type>` rows, so `/craftsman:metrics` can show which agent
  keeps producing which violation and agent prompts can be tuned from data.
- Agent contracts: every craftsman agent ends with an Output Contract (test
  evidence required before "done"), and every agent carries a one-line Memory
  Contract saying exactly what it may persist; reviewers persist rejected
  findings so the same false positive is not raised twice.
- `/craftsman:team` degraded mode: when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
  is absent the skill announces it once and runs the same composition through
  parallel subagent dispatches instead of failing; the healthcheck reports
  which mode the environment provides. The team-lead delegation matrix also
  gained the missing legacy row (legacy-surgeon / legacy-takeover template).
- `tests/core/test-invocation-policy.sh` crosses every agent `skills:` entry and
  every `**Invokes:**` claim with its target's invocation policy, and rejects
  self-forking bindings. Nothing checked this before, which is why sixteen
  locked skills and nine dead references coexisted with a green suite.

## [4.2.0] - 2026-07-28

An audit release. Every finding below was reproduced before it was fixed, and
each carries a test that fails when the fix is removed. The recurring shape is
one defect wearing different clothes: a control that reports success when it
did not run, and a measurement that reports a number the code does not have.

### Security

- **A cloned repository could write anywhere the developer could.**
  `ratchet.py` wrote `.craftsman-baseline.json` with `write_text`, which follows
  a symlink. A repo shipping that path as a link to `~/.claude/settings.json`
  had the target overwritten on the first edit of any supported file. Writes go
  through a sibling temp file and land with `os.replace`, which acts on the link
  and never on its target.
- **A cloned repository could switch the gates off.** `hooks.disabled` resolved
  from the project file first, so a clone could ship
  `hooks: {disabled: [config-protection, post-write-check]}` and open its first
  session with every gate silent. It now follows the `external_packs`
  asymmetry: a repository may tune what the gates check, never whether they run.
- **A psr-4 key could disarm the layer rules.** `_layer_ns_regex` escaped
  backslashes only, so a root such as `A(pp\` made every layer grep exit 2,
  which reads as "not this layer". LAYER001 to LAYER003 stopped firing
  repository-wide, in the hook and in CI.
- **A file name could address the reviewer.** Names from `git diff` and from
  `tool_input` were spliced verbatim into the Haiku review prompts. Names
  outside a plain-path charset are dropped, and the drop is reported.
- **A learned skill carried unsanitised text into the model's context.**
  `pattern_summary` and `file_pattern` are not plugin-controlled, and a newline
  in either opened a second YAML frontmatter block in the generated skill. They
  are collapsed, capped and stripped of the fence character now. The skills
  destination is confined to the project or `~/.claude`, and the rule id is
  validated on read as well as on write.

### Fixed

- **CI reported a pass on a pipeline that inspected nothing.** The default scan
  path was `src/`, so a Laravel `app/`, a monorepo `packages/` or a Next.js
  `app/` matched nothing and the run exited 0 with `files_scanned: 0`. Every
  common source root is scanned now, discovery is counted separately from
  scanning so a stack exclusion stays a legitimate pass, and an empty discovery
  fails loudly. The directory walk prunes `vendor`, `node_modules` and friends.
  An unresolved severity resolves to block instead of quietly becoming a warning.
- **Three blocking rules reported findings the code did not have.** SH002 and
  WARN-SH001 counted braces without knowing which were shell, so a function
  holding an embedded python or awk snippet never balanced and the rule fell
  back to measuring header-to-header: a 14 line function was reported as 128.
  PY001 grepped raw lines, so a docstring beginning with an English article
  matched its two-letter-name pattern and the rule blocked writes on prose.
  SH001 inspected the first 20 lines only, so a script whose header explains
  itself was told it lacked the `set -u` it declares. All four measured from a
  proper scanner now, and a function whose end cannot be located is reported as
  nothing rather than as a guess.
- **The exported doctrine covered 15 of 38 rules and described three of them
  wrong.** PHP003 was documented as "private constructor plus factory" while it
  enforces "no public setter", PHP004 as "no setters" while it enforces "no new
  DateTime()", TS002 as "readonly by default" while it enforces "no default
  export". A teammate on Codex read one rule and was blocked by another. A test
  now fails when an enforced rule has no doctrine text, when a documented rule
  never reaches the rendered file, or when the output passes the 20000 character
  limit at which harnesses truncate a context file.
- **The test suite trained the learning loop on its own fixtures.**
  `tests/run-tests.sh` set no `CLAUDE_PLUGIN_DATA`, so four months of runs
  recorded their fixtures as production violations: 3704 of 15588 violations
  sat on a path this repository does not have. `test-suite-isolation.sh` could
  not have caught it, since its signature swept `~/.claude` at maxdepth 1 and
  the databases live four levels down.
- **Session counters were decorrelated from reality.** SessionEnd re-queried
  the violations table over a window the length of the session, which counts
  every other session's rows: 236 sessions in one day reported 16236 warnings
  against 1353 actually recorded, and a quiet day under-counted instead.
  Counting is per session now, and the tallies restart at SessionStart so a
  crashed SessionEnd no longer bills the next session.
- **Level 2 and 3 could not run and said they were clean.** Every analyser was
  capped at 2 seconds, below the cold start of all of them, and `|| true`
  flattened the timeout into success. The budgets are realistic and a stopped
  analyser is announced.
- **Rules vanished in silence without python3.** Six checks shell out to it and
  each returned quietly, so the packs reported every file clean on a machine
  that has none. The absence is announced once per process and names the rules
  that did not run. `sqlite3` gets the same treatment in the metrics layer,
  where its absence previously produced an empty database and swallowed every
  insert.
- **Whole classes of file were never validated.** `post-write-check` allow-listed
  the characters a path may contain and skipped anything else without a word,
  so every Next.js App Router dynamic route, every route group and any accented
  path went unchecked. The rule is inverted to refuse only what is dangerous.
- **The test-path relaxation missed the PSR-4 convention.** It compared
  case-sensitively, so `Tests/` resolved SEC001 to block while `tests/`
  resolved it to warn.
- **Bitbucket published a green PASSED on an unreadable report**, and sent a
  negative sentinel in a NUMBER field once that was fixed. The verdict travels
  in the result field and its reason in the free-form details line.
- **A failed metrics adoption claimed success.** The marker was written whether
  or not the copy succeeded, so a full disk discarded the previous database for
  good and never retried.
- **`metrics_project_hash` hashed `$PWD`**, filing one repository under a
  different project for every subdirectory worked from, and
  `metrics_file_pattern` recorded absolute paths, including the developer's home
  directory, for every extension outside `php|ts|tsx`.

### Added

- **`adapters/`, a third front-end over the same core.** `hooks/` serves Claude
  Code, `ci/craftsman-ci.sh` serves pipelines, and `adapters/<host>/` serves
  other agent runtimes. The first is `adapters/hermes/`: a `pre_verify` hook
  that refuses a conclusion rather than a write, because blocking a write
  assumes somebody can break the loop it creates and an autonomous agent has
  nobody. It derives its scope from git rather than from the agent's
  self-report, since the host builds its changed-file list from tool names and
  a write through a shell never appears there. Opt-in by construction: a test
  fails if any hook or the plugin manifest reaches into `adapters/`.
- **Test paths degrade the rules whose premise is production code.** LOC001,
  NEST001, PARAM001, GOD001, CTRL001, SEC001 and SEC002 become warnings under
  `tests/`, `spec/`, `__tests__/`, `__mocks__/`, `fixtures/` and `factories/`.
  A long setup, a six-argument fixture builder and a credential in a fixture
  are the normal shape of a test, and blocking on them is what teaches a
  developer to reach for `craftsman-ignore`.
- **A `source` column on `violations` and `corrections`**, so the next
  contamination is a `DELETE` rather than an archaeology exercise.

## [4.1.2] - 2026-07-27

CI duration, which on this project is CI cost: the macOS matrix leg bills at
ten times the Linux rate and was 94% of the spend per run.

### Changed

- **The portable timeout polls adaptively instead of once per second.** The
  fallback added 163s to the macOS job (175s to 338s) because it slept a full
  second per call and almost every call finishes in milliseconds. It now polls
  at 50ms, backing off to 250ms after a second and 1s after ten. Measured in
  isolation over 50 fast calls: 972ms per call before, 64ms after.
- **One implementation instead of three.** `hooks/lib/portable-timeout.sh` is
  the single source; the static-analysis dispatcher, the test helpers and the
  test runner source it. Three copies of the same fallback is three chances to
  drift, and this release exists because of a difference nobody noticed.
- **The workflow cancels superseded runs.** There was no `concurrency` block,
  so pushing twice ran two full matrices, including two macOS jobs, for one
  answer that mattered.

### Added

- **A Python floor job.** The test matrix sets up 3.12 on both runners, so it
  could not see a module that only parses on 3.10+: that is exactly how
  `instincts.py` shipped broken for every Mac without homebrew and CI stayed
  green. A separate job imports every hook library under 3.9 in a few seconds.
  Removing the `__future__` import from instincts.py fails it.
- The runtime floor is now stated in both READMEs: Python 3.9, and no GNU
  coreutils required.

## [4.1.1] - 2026-07-27

Wiring the twenty unrun test suites in 4.1.0 put them on the CI matrix for the
first time, and both runners went red. Every failure was a "works on my
machine" dependency this repository had been carrying unnoticed.

### Fixed

- **Level 2 and Level 3 static analysis never ran on a stock macOS.** All five
  analyser invocations (PHPStan, deptrac, ESLint, dependency-cruiser) were
  wrapped in `timeout`, which is GNU coreutils and is not installed by default
  on macOS. The call failed with 127, the `|| true` swallowed it, and the
  plugin reported a clean gate having run nothing. `sa_timeout` uses `timeout`
  or `gtimeout` when present and falls back to a background job with a
  watchdog, so the budget holds either way. Verified by running the analyser
  path on a PATH with no coreutils: it now executes, and did not before.
- **The instinct pipeline was dead on a stock macOS.** `hooks/lib/instincts.py`
  annotated a parameter `str | None`, which Python evaluates at runtime from
  3.10; `/usr/bin/python3` on a Mac without homebrew is 3.9 and raised
  TypeError on import. `from __future__ import annotations` keeps the syntax
  and restores 3.9.
- **`sed -i ''` is BSD syntax** and GNU sed reads the empty string as the
  script, leaving the file untouched. Fixed in `test-validate-pack.sh`, which
  failed on Linux, and in `scripts/bump-version.sh`, which would have silently
  skipped a version bump for any contributor on Linux.

### Testing

- The test harness gained the same portable timeout. A subtest budget that
  silently disappears is how a hanging suite goes unbounded.
- The fallback initially broke every stdin-fed hook: bash redirects a
  background job's stdin from `/dev/null` unless it is explicitly redirected.
  `<&0` restores it.

## [4.1.0] - 2026-07-27

### Security

- **CI gate no longer fails open on a malformed report.** `adapter_compute_exit`
  parsed the report with stderr discarded, so a report that was not valid JSON
  produced an empty summary and exit 0. It now fails closed.
- **Command injection through a channel number closed.** `cache_ttl` and the
  three other values under `channels:` come from the repository's own
  `.craft-config.yml` and landed in `$(( now + ttl ))`, where bash evaluates an
  array subscript as a command: `cache_ttl: "a[$(touch${IFS}/tmp/pwned)]"`
  executed on the first cached call. Reproduced end to end, now refused at the
  config boundary and again inside `cache_set`, `cache_evict` and the circuit
  breaker.
- **Grep flag injection closed at three sites** (`rules-engine.sh`,
  `post-write-check.sh`, `craftsman-ci.sh`): a pattern beginning with `-` was
  read as an option.
- **secrets-scan fails closed.** It reported "no secrets found" for every
  condition that makes a scan produce nothing: a wrong repo root, a clone with
  no history, a grep that failed. It now proves it can enumerate tracked files,
  read their content and read history before any empty result means clean.
- **Six credential shapes added to the scan**: `sk-proj-`, AWS `ASIA`
  temporary keys, AWS secret access keys, Stripe live keys, Slack tokens, and
  every `.env` suffix rather than only `.local` and `.production`. Fixtures
  that must look real carry a per-line `secrets-scan: allow` marker instead of
  exempting `tests/` wholesale.
- **`hotspot_analysis.py` bounded.** Counting lines is lazy, but a file with no
  newline is one line: a 400MB blob took 952MB of RSS. It now shares the
  write-time gate's 2MB cap (17MB on the same input).

### Changed

- **`TS002`, `TS003` and `PHP003` default to advisory.** Each has legitimate
  exceptions a regex cannot see, and blocking a write on those only teaches
  suppression. Set them to `block` in `.craft-config.yml` where your codebase
  has no such exception.
- **`PHP002` skips a Doctrine entity.** A proxy extends the entity, so a final
  entity breaks lazy loading: the rule was asking Symfony projects to break
  their own persistence layer.
- **`TS002` skips the files a framework resolves by their default export**:
  `page`, `layout`, `route`, `middleware`, `loading`, `error`, `not-found`,
  `template`, `default`, `instrumentation`, anything under `pages/`,
  `*.stories.*`, `*.config.*` and `*.d.ts`. `TS002` and `TS003` now take a
  line-level `craftsman-ignore`, and a suppressed line no longer covers the
  rest of the file.
- **The layer rules read the project's root namespace from `composer.json`.**
  They matched `App\Domain` literally, and `App` is only the Symfony
  skeleton's default, so every project that renamed its root namespace passed
  all three layer rules by construction.

### Fixed

- **The CI quality gate no longer hangs.** Severity resolution walked from the
  file's directory up to the project root, but both stop conditions are
  absolute paths and CI is handed relative ones: `dirname` of `.` is `.` and
  the walk never ended. Both walks in `rules-engine.sh` now stop as soon as
  `dirname` stops moving.
- **CI agrees with the hook on `ignore`.** It resolved a boolean and filed
  everything that was not `block` under warnings, so a directory that had
  switched a rule off still had every finding printed in the pipeline while the
  hook stayed silent on the same file.
- **CI resolves severity per file**, so a directory-level `.craft-rules.yml`
  applies in the pipeline as it does in the hooks.
- **`consolidate-metrics.sh` reports its failures.** It discarded sqlite's
  stderr, so a locked or drifted source read as "0 rows to merge" and the run
  reported a clean consolidation while dropping the whole source. Failures are
  counted in a file (a shell counter is lost in a subshell), named, and the
  script exits non-zero telling the operator not to delete any source.
- **`pack_sync_symlinks` only removes what a pack put there.** It removed every
  symlink under `agents/` and every `skills/*/SKILL.md` in the live checkout
  and rebuilt only the loaded packs' entries, so anything else there was
  deleted and never restored.

### Testing

- **Twenty test suites the runner never called are now wired in**, including
  the entire hostile-repository security suite. The suite reported 213/0 while
  a third of the files on disk sat unexecuted. `test-runner-integrity.sh` fails
  when a test function is defined and not called, or a file is not named in the
  runner.
- **A failing subtest now says why.** All 26 wrappers discarded their output and
  told you to re-run the script yourself, which cannot work for a failure that
  only happens in the suite. They keep the output and print the failing
  assertions. Each subtest runs under a 300s timeout, so a hang is a named
  failure rather than a run that reports nothing.
- **Guard tests can no longer pass against deleted code.** Every absence
  assertion in the hostile-repository suite is gated on a positive control only
  a live tool can satisfy. With five analysis modules stubbed to `sys.exit(1)`:
  11 pass, 11 fail, where 19 used to stay green.
- **Two races removed from the circuit-breaker suite** that made it green four
  runs out of five, both on second boundaries.

### Documentation

- The model-tiering guide showed `/craftsman:metrics` printing a per-model cost
  breakdown that does not exist: the metrics database has no model, token or
  cost column. Replaced with published per-Mtok prices and a pointer to Claude
  Code's `/usage`.
- `SECURITY.md` described a plugin from two majors ago: 7 hook scripts against
  19, 8 events against 13, a RAG knowledge base and an MCP server removed in
  ADR-0024, and two audit commands that did not work.
- Three team templates spawned `architecture-reviewer`, an agent this
  repository has never shipped. They now name `architect`, and
  `test-team-templates.sh` fails on an unknown name.

## [4.0.1] - 2026-07-27

Corrects two settings that did not do what the repository believed, and removes
documentation for a subsystem 4.0.0 deleted.

### Added

- **Per-task model tiering**: every skill declares the cheapest model that can
  do its job (`haiku` for mechanical work, `sonnet` for bounded pattern
  application, `opus` for judgment that spans files) alongside its effort
  level. The tiering was documented in
  [Model Tiering Explained](docs/guides/model-tiering-explained.md) since v1 but
  never implemented: no skill declared a model, so every skill ran on whatever
  the session happened to be set to. Tiers are aliases rather than pinned model
  ids, so they follow model releases and a whole tier can be remapped with
  `ANTHROPIC_DEFAULT_*_MODEL`.

### Fixed

- **`effort` used values Claude Code does not recognise.** `effort` is Claude
  Code's own frontmatter key and accepts `low`, `medium`, `high`, `xhigh`,
  `max`. Eleven of twenty-one skills declared `quick` or `heavy`, a project
  convention that predates the key. Agents already used the real levels. The
  deep-reasoning skills now declare `xhigh`; `high` would have been a no-op
  because it is the default.
- **Skills reference** was missing `healthcheck`, `legacy`, and `workflow`, and
  carried no tier information. The table is now generated from the frontmatter
  it documents.
- **Hooks reference** documented 8 of the 13 wired events, omitting the
  `TaskCompleted` evidence gate introduced in 4.0.0 along with `SubagentStop`,
  `PostToolUseFailure`, `PreCompact`, and `PostCompact`.
- **Installation guide** walked new users through building and configuring the
  `knowledge-rag` MCP server, removed in 4.0.0 by
  [ADR-0024](docs/adr/0024-okf-knowledge-bundle.md).
- **Advanced guide** posed the scenario ADR-0024 decided (a few hundred curated
  Markdown files, technical questions, high accuracy) and answered it with the
  architecture the plugin abandoned for that case. It now teaches the decision:
  whether an embedding index is justified at all, with deterministic lookup and
  a lexical index as first-class outcomes.
- **README** claimed bash agent-hook wrappers became native Haiku-tiered
  `agent`/`prompt` hooks. ADR-0018 decided the opposite: all hooks are
  `type: command` because the native types offer no per-plugin option gating,
  which would remove the ability to disable verification. Badges also
  understated the plugin at 18+ commands and 6+ agents against 21 skills and 12
  agents, and the ADR count was four behind.
- **CI validators**: the skills validator required `name` and `model`, both
  optional per Claude Code, and read frontmatter keys from the whole file, so a
  YAML sample inside a skill body was mistaken for a declared field. The
  agent-effort test read a `plugin.json` key that does not exist and therefore
  passed vacuously; it now checks `agents/*.md`.
- **Secrets scanner** flagged its own test fixtures, failing the pipeline on
  4.0.0 and gating every other job.

## [4.0.0] - 2026-07-26

A clean break to a native-first, self-learning, security-hardened plugin.
**Requires Claude Code >= 2.1.218**; no backward compatibility with 3.x config.
The 3.9.x line stays available and frozen for older installations. Rationale:
ADRs 0016-0027. Upgrade steps: [MIGRATION.md](MIGRATION.md).

### Added

- **Structural ratchet** ([ADR-0025](docs/adr/0025-structural-ratchet.md)): a committed `.craftsman-baseline.json` holds each file's structural high-water mark (approximated complexity, file lines, longest function, import fan-out, suppression count). A file you touch may improve or stay equal, never regress. The mark tightens automatically on a green pass and only loosens through a documented `craftsman-ignore`, itself counted and ratcheted. The hook and `craftsman-ci` run the identical check; CI never writes the baseline. Untouched files and relaxed directories are never evaluated, so legacy is not punished for debt it already had. Ships advisory: set `RATCHET001: block` to make it a hard gate.
- **Correction learning closes the loop** ([ADR-0020](docs/adr/0020-instinct-promotion-human-review.md)): recurring fixed corrections (3+ across 3+ files) become candidate instincts; `/craftsman:metrics` surfaces them for human review; approval generates a learned skill with provenance. Instincts stay project-scoped until the same rule is approved in 2+ projects, then global promotion is offered. Promotion is never automatic.
- **Adversarial design panel** ([ADR-0026](docs/adr/0026-adversarial-design-panel.md)): three headless Haiku contradictors (YAGNI, invariants and aggregate boundaries, feasibility) attack the design during `/craftsman:design` Phase 2, before any code exists. Every objection must land in a retained or dismissed table.
- **Persistence craft**: `knowledge/persistence/` plus rules verified in hooks and CI: LAYER004 (raw SQL/DQL or a database client inside Domain), DB001 (`SELECT *`), DB002 (migration without `down()`), DB003 (query inside a loop). `/craftsman:design` ends with a persistence mapping per aggregate.
- **Security rules SEC001-003**: hardcoded secrets, dynamic eval/exec, and SQL built by concatenation, verified by the same validators in hooks and CI, with OKF doctrine routed automatically when one blocks.
- **Knowledge as an OKF bundle** ([ADR-0024](docs/adr/0024-okf-knowledge-bundle.md)): every concept carries [Open Knowledge Format v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog) frontmatter, and `knowledge_lookup.py` routes a rule or tag to the concepts explaining it by exact match. A quality-gate block now points at the doctrine behind the rule.
- **Level 1.5 semantic validation** ([ADR-0019](docs/adr/0019-established-tooling-first.md)): `.lsp.json` ships intelephense for PHP, activating only when the binary is already installed.
- **Deterministic verification loop** ([ADR-0023](docs/adr/0023-deterministic-verification-loop.md)): a failing test run revokes verification evidence and wakes the session on regression; a `TaskCompleted` gate requires evidence before a task is marked complete; a background monitor streams recorded test failures.
- **Situational onboarding and guided mode** ([ADR-0027](docs/adr/0027-situational-onboarding.md)): `--global` records a workshop profile once per machine; project init observes the repository then asks at most four plain-language questions. With `guided: true`, every block additionally explains its doctrine in plain language.
- **Living legacy audit**: `LEGACY-AUDIT.md` is committed and diffed between runs (RESOLVED/NEW), with a mandatory "looks bad but is actually fine" section. `tooling_detect.py` reports the quality tools a project already declares and suggests standards only when nothing is declared; nothing is ever installed.
- **Outcome Contracts**: every skill states its Outcome, its Done-when condition, and the Evidence that proves it; the validator enforces all three.
- **Cross-harness doctrine export**: `craftsman-ci export` renders the active rules as `AGENTS.md`, `.cursor/rules/craftsman.mdc`, and `.github/copilot-instructions.md`.
- **Local dashboard**: `/craftsman:metrics --dashboard` aggregates every tracked repository into a self-contained page served on localhost.
- **Context budgets and kill switches** ([ADR-0021](docs/adr/0021-context-budgets-and-kill-switches.md)): `context_budget` and `hooks.disabled` in `.craft-config.yml`, enforced at session start and in `hook-profile.sh`.

### Changed

- **All workflows are skills** ([ADR-0017](docs/adr/0017-skills-over-commands.md)): `commands/*.md` became `skills/<name>/SKILL.md`; invocations are unchanged. `/craftsman:challenge` runs as a forked skill bound to the architect agent with live context.
- **Semantic verification is headless** ([ADR-0018](docs/adr/0018-native-prompt-agent-hooks.md)): DDD verification moved from Stop (where it was dead) to PostToolUse and runs in a Haiku subprocess. Zero main-context cost; `agent_hooks: false` still disables everything.
- Metrics honour `${CLAUDE_PLUGIN_DATA}`; a legacy database is adopted by copy on first run.

### Security

Hardened against a hostile repository: opening or editing one must not execute
its code. Each fix has a test in `tests/core/test-hostile-repo.sh` that
reproduces the attack and asserts it fails.

- **Level 2 static analysis is off by default** (breaking): the gate resolved and executed `vendor/bin/phpstan` and `node_modules/.bin/eslint` from the working directory. A shell script at `vendor/bin/phpstan` in a cloned repository ran arbitrary code on the first PHP edit, with no config file and no phpstan installation involved. Running a project's analysers means running its code (eslint's flat config is executable JavaScript, phpstan's `bootstrapFiles` requires arbitrary PHP), so it is now consent: set `trust_project_tools: true` in your own global config. A repository cannot grant it to itself. A trusted phpstan additionally runs against a pinned configuration.
- **External packs are declared by the machine owner only**: `packs.external[].path` was read from the project config and its validators are sourced as shell code, so opening a cloned repository executed its code at session start. Only `~/.claude/.craft-config.yml` is honoured now.
- **No Python source splicing in the GitLab adapter**: an attacker-chosen filename reached the source text of a `python3 -c` call, giving code execution inside the CI job with its token in scope. The body travels through stdin.
- **Rule ids are constrained**: they are YAML keys from repository-controlled config and were used raw as filenames, so `../../..` escaped the rules store. Constrained at both entry points with a structural guard at the sink, which also closes injection into generated learned-skill frontmatter.
- **Dashboard output is escaped** and the server answers for exactly one file; it previously rooted at the directory holding `metrics.db`, so injected script could read the cross-project history over localhost.
- **Symlinks are refused**: git tracks symlinks as real entries, so `src/Thing.php -> ~/.ssh/id_rsa` is a legal commit and the hotspot audit followed it, reading a file outside the repository. Readers now require a regular, non-symlinked file resolving inside the project.
- **Reads are bounded**: measuring a 94 MB file cost 506 MB of memory and 4.4 seconds, and a size cap alone does not help because `getsize` on a symlink to `/dev/zero` reports 0. Source analysis declines anything past 2 MB or any non-regular file.
- **Verification verdicts are parsed by shape** before reaching the session: the headless verifiers read files the plugin did not write, and their reply was forwarded verbatim, which is an indirect prompt-injection path. Findings must look like `path:line something`, capped in count and length. Directory names are flattened for the same reason before entering an injected codemap.
- **Shipped CI template hardened**: actions pinned to verified commit SHAs and least-privilege permissions declared. Also: paths are anchored so a filename cannot be read as a flag, and the CI report uses `mktemp` instead of a predictable name.

### Removed

- `commands/` (flat command files), `output-styles/`, the v3 systemMessage-based agent hook wrappers.
- The `knowledge-rag` MCP server, its `/craftsman:knowledge` skill, the Ollama dependency, and 115 MB of dependencies. Supersedes ADR-0002 and ADR-0003.
- Support for Claude Code < 2.1.218.

## [3.9.0] - 2026-07-14

### Added
- **Global config fallback** (#4, thanks @Lucr4m). `~/.claude/.craft-config.yml` written by `/craftsman:setup` is now actually read by hooks. Resolution order: `$PWD/.craft-config.yml` > `CLAUDE_PLUGIN_OPTION_*` env vars > `~/.claude/.craft-config.yml` > hardcoded defaults. Explicit plugin options are never silently overridden by the machine-wide file, and the global file fills per-key gaps left by higher sources.
- **Global fallback test coverage.** `tests/core/test-config.sh` now sandboxes `HOME` (a developer's real global config can no longer leak into test results) and covers global-only resolution, env-over-global, PWD-over-global, and per-key fallback.

### Fixed
- **CI executable-bit check** no longer fails on sourced libraries (`hooks/lib/*`, pack validators) and bash-invoked test files discovered by the 3.8.0 dynamic script discovery. Only direct-exec entry points require the exec bit; syntax and ShellCheck coverage unchanged.
- `bump-version.sh` now exits 1 when a tracked file matches neither the old nor the new version, instead of printing a soft "may already be updated". That soft message let CLAUDE.md silently drift (stuck at 3.7.0 through the 3.8.0 release). Stale steps removed: README badge (dynamic shields.io since 3.8.0) and `test-adapters.sh` mock reports (frozen fixtures).

## [3.8.0] - 2026-07-14

### Added
- **Config protection hook** (`hooks/config-protection.sh`, PreToolUse Write|Edit). Blocks writes to single-purpose linter/formatter/architecture config files (`phpstan.neon*`, `.eslintrc*`, `eslint.config.*`, `.php-cs-fixer*`, `deptrac.y(a)ml`, `.dependency-cruiser.*`) so an agent can't silently loosen a rule instead of fixing the flagged code. `.craft-config.yml` and multi-purpose files (`pyproject.toml`, `package.json`) are intentionally excluded. Escape hatch: `CRAFTSMAN_DISABLED_HOOKS=config-protection`.
- **Hook profiles** (`hooks/lib/hook-profile.sh`). Session-level opt-out of secondary/costed hooks via `CRAFTSMAN_HOOK_PROFILE=minimal`, `CRAFTSMAN_DISABLED_HOOKS=<ids>`, and `CRAFTSMAN_HOOK_DRY_RUN=true`. Wired into the 4 agent hooks plus `post-bash-test-verify`, `tool-failure-tracker`, `subagent-quality-gate`, `file-changed`, `pre-push-verify`. Core quality gate, bias detection, and session bookkeeping deliberately do not support it.
- **Security invariant tests** (`tests/core/test-security-invariants.sh`). Sandbox + witness-marker suite proving `config-protection.sh` and `pre-write-check.sh` never execute injected code or touch files outside their contract, and fail open on malformed stdin. Plus `tests/core/test-config-protection.sh` for functional coverage; both registered in `tests/run-tests.sh`.
- **Prompt Injection Defense Baseline** in `SECURITY.md`: external content relayed by hooks (Sentry payloads, RAG documents) is data, never instructions. `CONTRIBUTING.md` gains a security review checklist (permission creep, injection surface, blast radius) for new commands/agents/skills.
- **French README** (`README.fr.md`) plus `FAQ.md`, `MIGRATION.md`, `TROUBLESHOOTING.md`, `COMMANDS-QUICK-REF.md`, and GitHub Sponsors funding config.

### Changed
- **CI hardening** (`.github/workflows/ci.yml`): all actions pinned by commit SHA, top-level `permissions: contents: read`, shell scripts discovered dynamically instead of a hardcoded list, ShellCheck blocking on real errors, new `lint-python` job (ruff, bugs-only blocking), and the test suite now runs on a `ubuntu-latest` + `macos-latest` matrix.
- **README.md** restructured: differentiators condensed, install verification collapsed, marketing tables moved to `COMMANDS-QUICK-REF.md`, supply-chain warning added, dynamic version/CI badges.
- `docs/reference/hooks.md` documents config protection, hook profiles, security invariant tests, Iron Law, and circuit breaker.
- `commands/scaffold.md` documents pack template variants.

### Removed
- Internal working documents from the public repo: `docs/roadmap-v3.6-v4.0.md`, `docs/audit-report-2026-03-30.md`, `docs/SUBMISSION-TEMPLATE.md`, `tests/BRUTAL-EVALUATION-PROMPT.md`.

## [3.7.0] - 2026-07-06

### Added
- **`/craftsman:legacy` command (the centerpiece).** Four modes for regaining control of an inherited codebase: `audit` (rank hotspots, produce `LEGACY-AUDIT.md`), `cover` (characterization net before touching), `untangle` (break dependencies), `migrate` (strangler-fig). Consumes existing analysis-tool output via `--from` (SonarQube / CodeScene / PHPStan) instead of recomputing a weaker signal. Atomic campaign state in `.craftsman/legacy-campaign.json`.
- **`legacy-surgeon` agent.** 3P agent (Sonnet, worktree) that drives a full rescue: characterize, break dependencies, strangler-fig migration, one green commit at a time.
- **`legacy-takeover` team template.** Sequential architect → legacy-surgeon → security-pentester → doc-writer for large multi-week rescues.
- **`hooks/lib/hotspot_analysis.py`.** Zero-dependency churn x complexity ranking (command-time only, read-only git log). A fallback for teams with no external analysis tool, not a competitor to one.
- **`knowledge/tooling-integration.md`.** Positions the plugin as the action layer on top of static-analysis tools: consume their reports, do not re-compute.
- **Legacy and refactoring knowledge pillars.** `legacy/{legacy-techniques,characterization-testing,strangler-fig,taking-over-legacy,communicating-tech-debt}.md` and `refactoring/{mikado-method,refactoring-campaigns,code-smells,refactoring-katas}.md`, presenting the working developer's dependency-breaking and safe-change toolbox.
- **Legacy Rescue Playbook** (`docs/guides/legacy-rescue.md`). Operational field guide chaining the whole pipeline, indexed from `docs/README.md`.

### Changed
- **`/craftsman:refactor`** gains a safety-net-first Step 0 gate and a Mikado mode; paths widened to py/sh/go/rs.
- **`/craftsman:workflow`** gains Step 0 scenario detection (greenfield / analyze-legacy / regain-control) that routes legacy work to `/craftsman:legacy`.
- **Knowledge base attribution.** Techniques are presented as generic developer practice; only the Clean series and Fowler are cited by name. Book-and-author references elsewhere were removed in favor of the technique itself.

## [3.6.0] - 2026-07-05

### Added
- **Core Knowledge Foundation.** The knowledge base gains its missing agnostic pillars so every pack, not just Symfony, inherits the full methodology (see ADR-0015). New core files under `knowledge/`:
  - `clean-architecture.md` (Dependency Rule, four circles, boundary crossing via DIP, humble object, screaming architecture, partial boundaries) and `hexagonal.md` (ports & adapters, driving/driven, composition root), grounded in the Clean series.
  - `tdd.md` (three laws, red-green-refactor, fake-it/triangulate/obvious, AAA, test naming) and `testing-strategy.md` (pyramid vs trophy, FIRST, test doubles, maintainable E2E via POM/BDD).
  - `legacy/` (`legacy-techniques.md` seams and Subclass&Override/Wrap&Sprout/Decouple-Core, `characterization-testing.md` golden master, `strangler-fig.md` branch-by-abstraction) and `refactoring/` (`mikado-method.md`, `refactoring-campaigns.md` churn x complexity hotspots).
  - New core anti-patterns: `anti-patterns/{god-object,primitive-obsession,singleton-abuse}.md`.
  - Completed the Fowler catalog in `refactoring-techniques.md` (Split Phase, Slide Statements, Replace Loop with Pipeline, Split Variable, Separate Query from Modifier).
- **DDD promoted to language-agnostic core.** `knowledge/ddd/{ddd-domain-design,ddd-cqrs-architecture}.md` rewritten framework-free (PHP + TypeScript); Symfony specifics moved to `packs/symfony/knowledge/ddd-symfony-implementation.md`.
- **SOLID canonical examples per pack** (`canonical/{php,tsx,py,bash}-solid.*`) plus a cross-language SOLID mapping table in `principles.md`.
- **Knowledge integrity test** (`tests/core/test-knowledge-integrity.sh`): file existence, deprecation stubs, zero em-dash, and resolvable `[[wiki-links]]`. Registered in the suite runner.

### Changed
- Merged `design-patterns.md` into `patterns.md` (full GoF quick-reference catalog, selection guide, anti-patterns); the old file is a deprecation stub.
- `commands/design.md`, `commands/refactor.md`, `commands/test.md`, and `agents/architect.md` now reference the new core knowledge.

### Deprecated
- `knowledge/design-patterns.md` and `packs/symfony/knowledge/ddd-{domain-design,cqrs-architecture}.md` are stubs, removed in v4.0.

### Fixed
- Removed em-dashes from three pre-existing knowledge files (`clean-code.md`, `stack-specifics.md`, `anti-patterns/sync-in-async.md`) per the copywriting rule.
- Resynchronized `ci/craftsman-ci.sh` (was 3.4.4) and `CLAUDE.md` (was 3.4.5) with the plugin version.

## [3.5.0] - 2026-06-19

### Added
- **Structural quality rules (NEST001, LOC001, GOD001, PARAM001, CTRL001).** The real-time gate previously enforced only `final`/`strict_types`/`no-any`/`no-setters`/layer imports, so the documented craftsmanship rules ("one level of indentation", "max 3 params", "no god class") were aspirational but unenforced, and deep `if/if/if` pyramids plus god classes drifted in. A new brace-aware analyzer (`hooks/lib/structural_metrics.py`, no fragile regex) feeds `hooks/lib/structural.sh`, wired into `post-write-check.sh` and the `php`/`typescript`/`python` pack validators:
  - `NEST001` control-flow nested 3+ levels deep,
  - `LOC001` method body over 50 lines,
  - `GOD001` class over 300 lines,
  - `PARAM001` non-constructor function with more than 3 parameters,
  - `CTRL001` persistence/`EntityManager` work inside a Controller (PHP).
  All five ship **advisory (warn) first** via `_rules_is_advisory` in `rules-engine.sh` so teams measure real noise before escalating; drop `NEST001`/`GOD001`/`PARAM001`/`CTRL001` from that list to let strict mode block them. Registered in the symfony/react/python `pack.yml`. The `agent-ddd-verifier` and `agent-final-review` agent hooks now also judge god-class (by responsibility cohesion, not raw LOC) and controller leaks. Covered by `tests/packs/test-structural.sh` (12 cases).

## [3.4.5] - 2026-06-09

### Fixed
- **knowledge-rag MCP server failed to connect** ("MCP error -32000: Connection closed"). The `mcpServers.knowledge-rag.args` entry used a bare relative path (`packs/ai-ml/mcp/knowledge-rag/start.mjs`), which Claude Code resolves against the current project working directory instead of the plugin root, raising `Cannot find module` and killing the process before the MCP handshake. Prefixed the path with `${CLAUDE_PLUGIN_ROOT}` so it resolves against the plugin install directory regardless of cwd.

## [3.4.4] - 2026-04-06

### Fixed
- **Hook blocking messages now visible to users** - When `post-write-check.sh` or `pre-write-check.sh` blocks a write, a human-readable violation summary is now emitted on stderr (displayed in Claude Code UI). Previously only JSON was written to stdout, resulting in an unhelpful "No stderr output" message.

## [3.4.3] - 2026-04-05

### Changed
- **Pre-push verification downgraded to warning** - `pre-push-verify.sh` no longer blocks pushes when session is unverified. Emits a warning instead. Reduces friction on trivial changes (configs, docs) while still encouraging verification for code changes.

## [3.4.2] - 2026-04-05

### Fixed
- **Auto-verify on test success** - Session now auto-sets `verified=true` when test suite passes (exit 0), eliminating the manual `craftsman-set-verified.sh` step before pushing. Detects `run-tests.sh`, `phpunit`, `jest`, `vitest`, `pytest`, `cargo test`, `go test`, and npm/pnpm/yarn test runners.

## [3.4.1] - 2026-04-05

### Fixed
- **CI hooks schema validator** - Added missing Claude Code hook events (`PostToolUseFailure`, `SubagentStop`, `PreCompact`, `PostCompact`) to `VALID_HOOK_EVENTS` in CI validation, fixing false negatives on valid hooks.json configurations.

## [3.4.0] - 2026-04-05

### Added
- **`/craftsman:workflow` - Development Pipeline Orchestrator** - Flexible 7-step methodology: design → spec → plan → implement → test → verify → commit. Supports `--from <step>` to start at any point, `--skip <step>` to bypass steps, and `[Y/skip/stop]` gates between each step. Combines structured guidance with craftsman freedom - the workflow suggests, the craftsman decides. See [ADR-0013](docs/adr/0013-workflow-orchestrator.md).
- **`/craftsman:setup --quick` - Zero-Question Auto-Setup** - Auto-detects stack (composer.json/package.json), extracts name from `git config`, and generates `.craft-config.yml` with smart defaults (strict mode, all biases ON, standard DDD paths). 30-second onboarding. Existing config protected unless `--force` is used. See [ADR-0014](docs/adr/0014-quick-setup-mode.md).
- **ADR-0013** - Flexible Workflow Orchestrator design decision
- **ADR-0014** - Quick Setup Mode design decision
- **Examples** - Quick setup example, two workflow examples (full pipeline, --from resume)

## [3.3.5] - 2026-04-05

### Fixed
- **Test suite polluting bridge file** - Tests calling `session-start.sh` overwrote `~/.claude/craftsman-session-state-path` with temp paths, corrupting the real session's bridge file. Pre-push tests then read the real verified state instead of test state. Added backup/restore around session-start and pre-push test sections, and redirect bridge to test `CLAUDE_PLUGIN_DATA` during pre-push tests.

## [3.3.4] - 2026-04-05

### Fixed
- **Pre-push hook "No stderr output"** - Added stderr message alongside JSON output so Claude Code displays a clear, actionable block reason instead of the cryptic "No stderr output" error.
- **`/craftsman:verify` never sets verified flag** - Root cause: the `set-verified` instruction was buried at line 266 of a 289-line skill file. Claude skipped it when focused on specific verification questions. Moved to "MANDATORY" section immediately after the verdict, before any optional content.
- **Symlink regression in v3.3.3** - Edit tool resolved `commands/knowledge.md` symlink target to absolute path. Restored to relative `../packs/ai-ml/commands/knowledge.md`.
- **CI secrets scanner false positive** - Removed `local paths in git history` check from scanner. Filesystem paths are not security secrets (no access granted). Current files are already validated by `scan_local_paths`. Only API keys/tokens warrant history scanning.

## [3.3.3] - 2026-04-05

### Fixed
- **Command namespace regression** - Removed explicit `name:` fields from 20 command frontmatter files. Claude Code uses the `name:` value as-is in autocomplete, bypassing automatic `craftsman:` prefix. Without `name:`, Claude Code derives from filename and correctly shows `/craftsman:setup` instead of `/setup`. Aligns with official plugin conventions (vercel, stripe and other official plugins omit `name:`).

## [3.3.2] - 2026-04-05

### Fixed
- **Absolute symlink breaking portability** - `commands/knowledge.md` used a hardcoded absolute path, making the plugin unusable on other machines. Fixed to relative `../packs/ai-ml/commands/knowledge.md`.
- **Git history sanitized** - Cleaned hardcoded local paths from git history via BFG to pass secrets scan.
- **`craftsman-ci.sh` SH002 suppressions** - Added justified `craftsman-ignore` comments for 4 long functions that are cohesive output/config blocks.

## [3.3.1] - 2026-04-05

### Removed
- **Mjolnir companion** - The Norse forge companion (persona injection, quality event reactions, `/craftsman:mjolnir` status command, and configuration toggle) has been removed. Claude Code does not expose a native companion API for plugins, making the feature purely text-based with no visual sidebar presence. The atmospheric value did not justify the added complexity.

### Improved
- **`/craftsman:plan` - Git-First Assessment (Phase 0)** - The planning skill now starts with a mandatory git-history evaluation. Before designing file-by-file task breakdowns, it checks whether the scope maps to identifiable commits that can be reverted or cherry-picked. Prevents over-engineering when a simple `git revert` achieves the same result more safely.

## [3.2.4] - 2026-04-05

### Fixed
- **Verify/push path mismatch (definitive fix)** - v3.2.3 bridge file mechanism was correct in code but Claude simplified the inline Python when executing `/craftsman:verify`, losing the bridge file lookup. Extracted path resolution into `session_state.py set-verified` command and generated `~/.claude/craftsman-set-verified.sh` wrapper at session start. Verify skill now calls one shell script instead of inline Python.

### Added
- **`set-verified` command** in `session_state.py` - auto-resolves session-state path via bridge file, sets `verified=true` atomically. Single source of truth for path resolution.
- **`craftsman-set-verified.sh` wrapper** - generated by `session-start.sh` with baked-in plugin root path. Skills call this directly, no `CLAUDE_PLUGIN_ROOT` needed.

## [3.2.3] - 2026-04-05

### Fixed
- **Session state bridge desync** - `/craftsman:verify` wrote `verified=true` to a different path than `pre-push-verify.sh` read, because `CLAUDE_PLUGIN_DATA` is unavailable in Bash tool context. Added bridge file pattern: `session-start.sh` writes the canonical path to `~/.claude/craftsman-session-state-path`, both `verify.md` and `pre-push-verify.sh` resolve via the bridge.

### Added
- **Healthcheck: session-bridge** - `hc_check_session_bridge()` verifies the bridge file exists, is non-empty, and points to a valid directory. Catches post-reinstall issues.

## [3.2.2] - 2026-04-04

### Fixed
- **Breaking plugin validation** - `skills` and `agents` fields in `plugin.json` used inline objects incompatible with Claude Code v2.1.92 schema. Removed inline definitions; Claude Code now auto-discovers from `commands/` and `agents/` directories.
- **Agent frontmatter completeness** - migrated `allowedTools`, `isolation`, and `skills` metadata from `plugin.json` into each agent's YAML frontmatter (10 files). Fixed `tools:` → `allowedTools:` in react-reviewer, symfony-reviewer, security-pentester.

## [3.2.1] - 2026-04-04

### Fixed
- **PY001 regex bug** - `[=,\s]` matched literal `s` in ERE character classes, causing false positives on `result`, `else`, `sys`. Changed to `[=,[:space:]]`.

### Changed
- **Dog-fooding compliance** - Plugin now passes its own validation rules on all Python and Bash source files.
- `pack_validate_python()` split into 6 focused sub-functions (`_check_py001`..`_check_py005`, `_check_warn_py001`)
- `yaml-parser.py` - extracted `_dispatch_yaml_line()`, added type hints, Python 3.9 compatibility (`from __future__ import annotations`)
- `metrics-query.py` - extracted `_parse_args()`, `_execute_query()`, `_print_select_results()`, added type hints
- `rules-engine.sh` - split 4 functions >30 lines, renamed `ns` → `namespace`
- `pack-loader.sh` - split 2 functions >30 lines, renamed `t` → `tool_entry`, `st` → `scaffold_type`

### Added
- `tests/core/test-dogfood.sh` - self-validation test running plugin validators against own code

## [3.2.0] - 2026-04-04

### Added
- **Python Pack** (`packs/python/`) - full language pack with 6 rules: PY001 (naming), PY002 (function length), PY003 (type hints), PY004 (bare except), PY005 (mutable defaults), WARN-PY001 (parameter count). Canonical examples and anti-pattern documentation included.
- **Bash Pack** (`packs/bash/`) - full language pack with 6 rules: SH001 (safety options), SH002 (function length), SH003 (variable naming), SH004 (eval security), SH005 (unquoted variables), WARN-SH001 (local declarations). Closes the 83% Bash codebase blind spot.
- **Knowledge: Clean Code** (`knowledge/clean-code.md`) - naming, functions, comments, error handling, SOLID reference
- **Knowledge: Refactoring Techniques** (`knowledge/refactoring-techniques.md`) - code smells catalog, composing methods, moving features, simplifying conditionals. Reference: refactoring.guru
- **Knowledge: Design Patterns** (`knowledge/design-patterns.md`) - 23 GoF patterns (creational, structural, behavioral) with Python examples and selection guide. Reference: refactoring.guru
- **Symfony Knowledge Base** - 8 new methodology documents extracted from production projects:
  - `ddd-cqrs-architecture.md` - Full DDD+CQRS layer architecture with Symfony & API Platform
  - `ddd-domain-design.md` - Entities as aggregates, value objects, domain events, bounded contexts
  - `api-platform-patterns.md` - State Providers/Processors, pagination, cache invalidation, serialization groups
  - `messenger-patterns.md` - Async processing, idempotency, retry strategy, message versioning
  - `symfony-best-practices.md` - Configuration hierarchy, services, controllers, security, testing
  - `repository-composition.md` - Interface Segregation for repositories (7 focused interfaces per aggregate)
  - `anti-patterns/anemic-domain.md` - Behavioral methods vs getter/setter entities
  - `anti-patterns/service-locator.md` - Constructor injection vs ContainerInterface::get()
- 15 new tests: 8 Python pack tests + 7 Bash pack tests
- `craftsman-ignore: SH001` support for sourced library files (validators loaded via `source` must not have `set -euo pipefail`)

### Changed
- Python validation migrated from inline code in `post-write-check.sh` to proper pack architecture (`packs/python/hooks/python-validator.sh`)
- `post-write-check.sh` now delegates to `pack_run_validators` for Python and Bash - same pattern as PHP/TypeScript
- Plugin now validates **all 4 language families** it touches: PHP, TypeScript, Python, Bash
- Knowledge base expanded from 5 to 45 documents across 5 packs + core
- Bias detector patterns made context-aware - requires imperative verb context, eliminates false positives on "quick", "fast"
- Rules engine refactored: extracted `_rules_find_directory_override`, `_rules_store_rule_fields` (SRP compliance)

### Fixed
- 4 phantom skill references in agents: `craftsman:entity`, `craftsman:usecase`, `craftsman:component`, `craftsman:hook` → unified to `craftsman:scaffold`
- 13 command skills missing `name:` field in frontmatter
- 8 agent effort level mismatches between plugin.json and .md files
- README version badge 3.0.0 → 3.2.0

## [3.1.0] - 2026-04-04

### Added
- `hooks/lib/session_state.py` - shared Python module (Clean Code compliant) with 13 commands: read, write, merge, append, increment, check-flag, record-violation, detect-patterns, pre-compact, post-compact, get-previous-violations, read-session-metrics
- **Python validation in core** (PY001: naming, PY002: function length) - the plugin now validates its own Python code
- `tests/lib/test-helpers.sh` - centralized test infrastructure (log_pass/log_fail, assertions, test_summary)
- `tests/core/test-session-state-lib.sh` - 20 unit tests for session state module
- PostCompact hook - verifies session state recovery after context compaction
- 3 new examples: refactor (extract Value Object), verify (pre-commit), healthcheck (plugin diagnostic)
- Superpowers plugin combination guide in README with recommended development flow

### Fixed
- **CRITICAL**: Non-atomic writes in `post-write-check.sh` - session-state.json could be corrupted when multiple hooks fire simultaneously. Now uses `tempfile.mkstemp() + os.rename()`.
- **Python Clean Code violations** in `session_state.py` - renamed all abbreviations (`fp`->`file_path`, `dir_b`->`directory`, `d`->`parent_directory`, etc.), extracted magic numbers to constants, split long functions
- `bias-detector.sh` output changed from raw text to JSON `{systemMessage}` format for proper Claude Code integration
- `bin/craftsman-validate` - replaced string interpolation with `jq --arg` to prevent shell injection
- ADR numbering: unified from dual scheme (0001-0009 + 001-004) to consistent 0001-0012
- Removed ADR-0013 (documentation verification) - was a process rule, not an architectural decision
- `test-adapters.sh` - version assertion matched stale v2.1.0 instead of mock report's v2.6.0

### Changed
- Migrated **all** session-state operations to shared `session_state.py` module - 8 hooks refactored, ~150 lines of inline Python eliminated
- Refactored 19 test files to use shared `test-helpers.sh`, eliminating ~400 lines of duplicated test boilerplate
- **Hook event validation refactored** - extracted hardcoded hook event list from `session-start.sh` and `test-hooks.sh` into centralized `hooks/lib/hook-events.sh` configuration. Single source of truth for all 25 valid Claude Code hook event types. Fixes Issue #4.
- **Agent metadata synchronized** - all 9 agent .md files now have `allowedTools` arrays, `isolation` fields, and consistent `effort` values matching `plugin.json`. Fixes Issue #3.
- Stale documentation counts corrected: "15 commands" → "20 skills", "5 agents" → "11 agents"
- README examples section expanded from 6 to 11 entries
- README ADRs section expanded from 11 to 12 with consistent numbering

## [3.0.0] - 2026-04-04

### BREAKING - Paradigm Shift: Passive → Proactive

The plugin now actively suggests the right command at the right time. Claude reads the routing table at session start and proposes craftsman commands when the context matches.

### Added
- **Proactive Command Discovery** - routing table injected into session-start systemMessage
- `hooks/lib/routing-table.sh` - dynamic routing table adapted to loaded packs
- `/craftsman:healthcheck` - global plugin diagnostic (system deps, config, runtime, AI/ML)
- `/craftsman:knowledge` - knowledge base management (add, sync, list, status, remove)
- Incremental indexing - hash-based sync replaces full rebuild (SHA256 per file)
- Healthcheck summary injected into session-start output
- `hooks/lib/healthcheck.sh` shared library for health checks

### Fixed
- Config key `ai` renamed to `ai-ml` in setup template to match pack directory
- All command descriptions now include explicit trigger conditions for discovery
- Removed unused `packs/ai-ml/mcp/knowledge-rag/data/` directory

### Changed
- `index-pdfs.ts` refactored to CLI with modes: sync, add, remove, status, list, rebuild
- VectorStore gains incremental methods: deleteBySource, getSourceHash, getAllSourceHashes
- DB schema migration: sources table gains `file_hash` and `file_size` columns (auto-migrated)
- session-start.sh output now includes healthcheck summary + command routing table

## [2.9.1] - 2026-04-04

### Fixed
- Conflict detector now also checks `~/.mcp.json` - a stale home-level entry with invalid path silently overrode the plugin-managed MCP server

## [2.9.0] - 2026-04-04

### Fixed
- No-op MCP server protocol mismatch: switched from Content-Length (LSP) to NDJSON framing to match MCP SDK 1.25.3
- Bootstrap error logging: `stdio: "ignore"` → `stdio: "pipe"` with try/catch - install/build failures are now visible instead of silently swallowed
- Added conflict detection: warns users when `~/.claude.json` contains a manual `knowledge-rag` MCP entry that conflicts with the plugin-managed server

## [2.8.2] - 2026-04-04

### Fixed
- knowledge-rag MCP server fails for all users with "Failed to reconnect" because `dist/` and `node_modules/` are gitignored and never built during plugin installation
- MCP server now conditional on `ai-ml` pack activation via `CLAUDE_PLUGIN_OPTION_packs` - users without `ai-ml` get a no-op MCP server (valid protocol, zero tools, zero errors)
- Auto-bootstrap: when `ai-ml` pack is enabled, `start.mjs` launcher auto-installs dependencies and builds TypeScript on first run
- Fixed stale path references in docs (`ai-pack/` → `packs/ai-ml/`)

## [2.8.1] - 2026-04-01

### Fixed
- Removed invalid `FileChanged` hook event type from hooks.json that prevented plugin from loading

## [2.8.0] - 2026-04-01

### Added
- Unified `/craftsman:scaffold` command replacing standalone entity/usecase/component/hook commands
- New `api-craftsman` agent (API Platform 4, REST/HATEOAS, OpenAPI)
- New `api-resource` and `pack` scaffold types
- New guides: command chaining, model tiering, workflow comparison
- New examples: parallel review, fullstack feature team

### Changed
- Renamed `ai-reviewer` agent to `ai-engineer`
- Team-lead agent model changed from Opus to Sonnet
- Agent count corrected to 11 (4 reviewers + 7 craftsmen)
- Removed Sentry MCP server from plugin (uses official Sentry plugin instead)

### Removed
- Phantom commands: `/craftsman:source-verify`, `/craftsman:agent-create`, `/craftsman:start`
- Duplicate Sentry channel declaration from plugin config

## [2.7.0] - 2026-03-30

### Changed
- Reorganized Key Differentiators from 10 to 6 genuine USPs
- Correction Learning System promoted to #1 differentiator
- Honest descriptions for Quality Gate levels and Bias Detector limitations
- Model Tiering, Atomic Commit, Circuit Breaker, Iron Law moved to feature sections

### Fixed
- SQL injection in metrics read functions (parameterized queries via metrics-query.py)
- test-templates.sh phantom paths (symfony-pack → packs/symfony)
- Version sync across all config files

### Added
- Test coverage for bias-detector, correction-learning, session-metrics
- YAML parser Python3 migration for rules engine reliability
- rules_explain() debug function for enterprise rule resolution tracing
- CI sources pack validators directly (DRY fix, 145 lines removed)
- FILE_PATH whitelist validation in post-write-check hooks

## [2.6.1] - 2026-03-30

### Changed
- **Native Agent Teams**: `/craftsman:team` now uses `TeamCreate` + `TaskCreate` + teammates instead of isolated `Agent` subagents
- **team-lead agent**: Added `TeamCreate`, `TaskCreate`, `TaskList`, `TaskUpdate`, `SendMessage` to allowedTools
- **team-lead agent**: Added `craftsman:team` skill and "Native Agent Teams Integration" section
- `/craftsman:team list` now shows active teams alongside templates

### Fixed
- `/craftsman:team create` spawned isolated subagents instead of coordinated teammates with shared task lists

## [2.6.0] - 2026-03-29

### Added
- **Pack Validation Script**: `scripts/validate-pack.sh` validates pack structure, references, rule ID collisions, agent conventions
- **External Pack Support**: Load packs from outside the plugin via `.craft-config.yml` `packs.external` paths
- **Pack Scaffold Type**: `/craftsman:scaffold pack` generates complete pack directory structure
- **Pack Creation Guide**: `docs/creating-packs.md` - comprehensive guide for community pack authors
- **Go Pack Skeleton**: `examples/pack-skeleton-go/` with error checking and init() detection rules
- **Rust Pack Skeleton**: `examples/pack-skeleton-rust/` with unwrap/panic detection rules
- **Python Pack Skeleton**: `examples/pack-skeleton-python/` with bare except, mutable defaults, wildcard import rules

### Changed
- **pack-loader.sh**: Now scans external pack directories from `.craft-config.yml`
- **config.sh**: Added `config_external_packs()` for parsing external pack paths

## [2.5.0] - 2026-03-29

### Added
- **Knowledge-RAG MCP Server**: Migrated from excluded ai-pack to proper packs/ai-ml/mcp/ with setup script
- **API Resource Scaffold Type**: `/craftsman:scaffold api-resource` with API Platform State Provider/Processor patterns
- **Pack-Specific Test Suites**: Separate test files for symfony, react, and ai-ml packs
- **CI Pack-Loader Integration**: craftsman-ci.sh now loads pack-specific rules

### Changed
- **Test structure reorganized**: tests/hooks/ → tests/core/ + tests/packs/ for better modularity
- **Distribution ignore updated**: Targets packs/*/mcp/*/node_modules/ instead of blanket ai-pack/
- **plugin.json**: Registers knowledge-rag MCP server for AI-ML pack users

### Removed
- Old `ai-pack/` directory (replaced by packs/ai-ml/mcp/)

## [2.4.0] - 2026-03-29

### Added
- **Core + Pack Architecture**: Loadable language packs (symfony, react, ai-ml) with `pack.yml` manifests
- **Pack Loader** (`hooks/lib/pack-loader.sh`): Discovers, validates, and loads packs based on stack config
- **Symlink Management**: Pack agents and commands auto-linked into root directories for Claude Code discovery
- **API Craftsman Agent**: New specialized agent for API Platform, REST/HATEOAS, OpenAPI in symfony pack
- **Unified Scaffold Command**: `/craftsman:scaffold <type>` loads types from active packs
- **Pack Selection in Setup**: `/craftsman:setup` now includes pack auto-detection and selection

### Changed
- **Commands consolidated** (25 → 15 core + 3 pack): Merged setup+start, unified scaffold, moved AI-ML commands to pack
- **Agents consolidated** (12 → 5 core + 6 pack): Removed duplicates, added allowedTools, team-lead Opus→Sonnet
- **post-write-check.sh refactored**: 536 → ~390 lines orchestrator delegating to pack validators
- **file-changed.sh deduplicated**: Removed ~60 lines of duplicated validators, now uses pack-loader
- **static-analysis.sh**: Reduced to thin dispatcher, wrappers moved to packs
- **Knowledge distributed**: PHP examples → symfony pack, TS examples → react pack, AI/ML → ai-ml pack
- **Templates migrated**: `symfony-pack/` → `packs/symfony/templates/`, `react-pack/` → `packs/react/templates/`

### Removed
- `architecture-reviewer` agent (absorbed by `architect`)
- `ai-reviewer` agent (absorbed by `ai-engineer`)
- `/craftsman:source-verify` command (moved to CLAUDE.md instruction)
- `/craftsman:agent-create` command (integrated into scaffold)
- `/craftsman:start` command (absorbed into setup)
- Standalone scaffold commands (entity, usecase, component, hook - unified into scaffold)
- Old `symfony-pack/`, `react-pack/` root directories

---

## [2.3.0] - 2026-03-29

### Added

- **Distribution ignore** - `.claude-plugin/ignore` reduces plugin size from 134 MB to <1 MB by excluding ai-pack/, tests/, scripts/, docs/superpowers/
- **Dependency check** - `session-start.sh` verifies python3, jq, sqlite3 at boot with clear install instructions if missing
- **Agent hooks opt-out** - `agent_hooks: false` in userConfig disables all 4 AI agent hooks (DDD verifier, Sentry, analyzer, reviewer). Saves ~$0.15-0.30/session in Haiku API costs.
- **API Cost Model** - README section documenting agent hook costs and opt-out mechanism
- **Auto-setup gate** - Improved first-run detection: checks both global (`~/.claude/.craft-config.yml`) and project config, with clear guidance to run `/craftsman:setup`

---

## [2.2.1] - 2026-03-29

### Added

- **Version bump script** - `scripts/bump-version.sh` updates all version references in one command
- **README v2.x features** - Custom Rule Engine, CI/CD Integration, Circuit Breaker, Pack Templates, Schema Validation sections
- **README missing commands** - Added `/craftsman:team`, `/craftsman:start` to commands table

### Fixed

- **SECURITY.md** - Updated commands count (22→25), hooks count (6→7), added pre-push-verify.sh, v2.x audit trail, supported versions
- **docs/reference/skills.md** - Added 3 missing commands to Quick Reference Table (`/craftsman:team`, `/craftsman:ci`, `/craftsman:start`)
- **docs/reference/hooks.md** - Added pre-push-verify.sh, Rules Engine, Schema Validation, Atomic Commits, Monorepo Safety sections
- **README Project Structure** - Added `config/`, `ci/`, `pre-push-verify.sh`, fixed hooks count 6→7

---

## [2.2.0] - 2026-03-29

### Security

- **SQL injection fix** - `metrics-db.sh` write functions now use parameterized queries via `metrics-query.py` Python helper. Eliminates injection risk from filenames/rule names containing SQL metacharacters.
- **Bitbucket adapter fix** - Replaced fragile double-nested `python3 -c` JSON encoding with single safe call using `sys.stdin.read()`.

### Added

- **Hooks schema validation** - `session-start.sh` validates `hooks.json` events against supported set at startup. Catches unsupported events before CI fails.
- **Atomic commit enforcement** - Stop hook caps file inspection at 20 files and warns when >15 files modified in a session, encouraging small focused commits.
- **Monorepo sampling** - InstructionsLoaded agent switches to directory-level analysis when Glob returns >100 files. Prevents token explosion on large codebases.
- **Key Differentiators section** - README "Why Craftsman?" marketing table with 8 unique selling points.
- **Project CLAUDE.md** - Development rules, testing commands, version sync checklist, and 10 marketing differentiators.

### Fixed

- `commands/ci.md` - Added missing `effort: medium` frontmatter field.
- README badges - Updated from v1.5.0/22 commands to v2.2.0/25 commands.
- README - Removed outdated "CI/CD not supported" line (CI has been supported since v2.1.0).

---

## [2.1.0] - 2026-03-29

### Added

- **Custom Rule Engine** - Per-project rule customization with 3-level inheritance:
  - Global (~/.claude/.craft-config.yml) → Project (.craft-config.yml) → Directory (.craft-rules.yml)
  - Short form (`PHP001: warn`) and long form (custom rules with pattern, message, severity, languages)
  - Custom rule validation on config load (bad regex = skipped with warning)
- **CI Adapter System** - Universal adapter architecture for multi-provider CI:
  - Auto-detection via env vars (GITHUB_ACTIONS, GITLAB_CI, BITBUCKET_BUILD_NUMBER)
  - 4 adapters: GitHub Actions, GitLab CI, Bitbucket Pipelines, Generic (Jenkins/CircleCI)
  - `craftsman-ci.sh ci` mode with full adapter lifecycle
  - `craftsman-ci.sh init --provider` generates CI template files
  - Unified PR/MR comment format across all providers
  - Inline file annotations (GitHub ::error, GitLab codequality, Bitbucket Reports API)
- **CI Templates** - GitLab CI, Bitbucket Pipelines, Jenkinsfile templates
- **Circuit Breaker** - Protects against external service failures:
  - 3 states: closed → open → half-open
  - Configurable threshold and cooldown per channel
  - File-based cache with TTL and LRU eviction
  - Stale cache serving during circuit open
- **Pack Template Variants**:
  - Symfony: CRUD API (API Platform simple) + Event-Sourced (Aggregate + Event Store + Projections)
  - React: Form-Heavy (multi-step wizard + Zod + useActionState) + Dashboard-Data (TanStack Table + Recharts)

### Changed

- **Config format** - Updated to v2.1 with `rules:` section for per-rule overrides and `channels:` for circuit breaker config
- **post-write-check.sh** - Refactored to use rules engine instead of hardcoded severity logic
- **craftsman-ci.sh** - Integrated rules engine, added `ci` and `init` subcommands, bumped to v2.1.0
- **channels.sh** - Rewritten with circuit breaker integration and cache orchestration
- **Sentry hook** - Now checks circuit breaker state before querying, records success/failure
- **GitHub Actions template** - Simplified to use adapter system

---

## [2.0.0] - 2026-03-28

### Added

- **Teams system** - Agent team orchestration with `/craftsman:team` (create, context, list):
  - 3 built-in templates: `code-review`, `feature`, `security-audit`
  - Interactive team builder with questionnaire or template selection
  - Codebase analysis for optimal team composition
- **CI export** - `/craftsman:ci` skill + standalone `craftsman-ci.sh` CLI:
  - Same regex rules as hooks (PHP001-005, TS001-003, LAYER001-003)
  - JSON + text output formats for CI/CD integration
  - GitHub Actions workflow template (`craftsman-quality-gate.yml`)
  - 36 CLI tests, 0 failures
- **Onboarding** - `/craftsman:start` for first-time users:
  - Auto-detect stack, scan codebase, suggest top 5 skills
  - Quick reference card with all commands
- **Pre-push verification** - `pre-push-verify.sh` blocks `git push` if `/craftsman:verify` not run
- **Workflow enforcement** - `bias-detector.sh` warns when domain modeling without `/craftsman:design`
- **TeammateIdle + TaskCompleted hooks** - New hook events in hooks.json
- **4 canonical examples** - API Platform 4 State Provider, Messenger handler, React Server Component, Compound Component
- **3 anti-patterns** - sync-in-async (Messenger), barrel imports, inline components

### Changed

- **Hooks enriched** - Structured PHPStan/ESLint/deptrac parsing with error-to-code mapping (PHPSTAN001-003, ESLINT001)
- **Correction Learning v2** - Cross-file pattern detection: project-wide and directory-level suggestions when same rule violated in 3+ files
- **craftsman-ignore multi-rules** - `// craftsman-ignore: PHP001, TS001, LAYER001` on single line
- **Session metrics** - Now tracks agent invocations, team type, and completed tasks
- **All 22 skills enriched** - `paths` field (7 skills), `effort` field (all 22), `!command` injections for runtime context
- **Scaffolders** (entity, usecase, component, hook) - Worktree isolation recommendation
- **/craftsman:plan** - TaskCreate/TaskUpdate integration + Agent tool dispatch for parallel execution
- **/craftsman:verify** - Auto-detection + real execution of tests/lint/typecheck + session state `verified=true`
- **/craftsman:debug** - WebSearch/WebFetch auto-research after 2 inconclusive investigation cycles
- **/craftsman:challenge** - Deep Review Mode with parallel reviewer agents for complex PRs
- **/craftsman:parallel** - Real Agent tool spawn with `isolation: "worktree"` and `run_in_background: true`
- **/craftsman:setup** - Auto-detection of stack + analysis tools check + pack auto-selection
- **/craftsman:metrics** - Correction trends, quality score (100-based), agent/team usage stats
- **Symfony pack** - API Platform 4 (State Provider/Processor), Messenger async handlers, Scheduler 7.4+, MapRequestPayload
- **React pack** - React 19 Server Components, useOptimistic, useTransition, Compound Components, Render Props with useSuspenseQuery
- **knowledge/stack-specifics.md** - 6 new sections (API Platform 4, Messenger, Scheduler, React 19, Composition)

### Fixed

- **8 factual inaccuracies** in packs - Messenger routing glob, Processor return type, Next.js cache leak, unsafe type cast, untyped activity fetch, missing ErrorBoundary note, pagination type, missing patterns

---

## [1.5.0] - 2026-03-28

### Added

- **7 craftsman agents** - New specialized agents for full-stack implementation:
  - `team-lead` (Opus, max effort) - orchestrator, delegates, challenges, never codes
  - `backend-craftsman` (Sonnet) - PHP/Symfony expert with Symfony.com + API Platform refs
  - `frontend-craftsman` (Sonnet) - React/TS expert with 65 Vercel best practices rules
  - `architect` (Sonnet, read-only) - DDD/Clean Architecture validation, disallowedTools: Edit,Write
  - `ai-engineer` (Sonnet) - RAG, LLM, MCP server, agent design
  - `ui-ux-director` (Sonnet) - UX, WCAG 2.1 AA, design tokens, data visualization
  - `doc-writer` (Haiku, cost-optimized) - ADRs, README, CHANGELOG, runbooks
- **Agent Teams support** - `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled in settings. Team launch prompt prepared at `.claude/team-prompts/v2-implementation.md`.

### Changed

- **5 existing reviewers enriched** - All reviewers now have `memory: project` (cross-session learning), `effort: high`, `skills` preload, and `maxTurns` (camelCase per official Claude Code docs). Fields migrated from legacy `allowed-tools`/`max-turns` to official `tools`/`maxTurns`.

---

## [1.4.0] - 2026-03-28

### Added

- **Sentry Channel integration** - Sentry MCP server bound via `channels` in plugin.json. PostToolUse agent hook queries Sentry for errors related to edited files.
- **Channel lifecycle library** - `hooks/lib/channels.sh` provides `channel_available()` and `channel_status_summary()` for gating channel usage.
- **Sentry configuration** - `sentry_org`, `sentry_project`, `sentry_token` (sensitive: true) in userConfig.
- **Corrections reporting** - InstructionsLoaded agent hook queries 30-day correction trends and suggests strictness adjustments.
- **Channel status** - InstructionsLoaded agent reports active channels at session start.

### Changed

- **config.sh** - Added `_config_resolve()` generic helper. All config functions now use it.
- **hooks.json** - Now has 8 events, 6 command hooks, 4 agent hooks (PostToolUse DDD + Sentry, InstructionsLoaded, Stop).

---

## [1.3.0] - 2026-03-28

### Added

- **Semantic Intelligence** - 3 agent hooks for semantic analysis beyond regex:
  - PostToolUse DDD verifier (Haiku) - checks layer violations, aggregate boundaries, value objects, naming
  - InstructionsLoaded project analyzer (Haiku) - builds architectural context map at session start
  - Stop final reviewer (Haiku) - validates architecture before session end (strict mode only)
- **Correction Learning System** - Detects when user fixes Claude-generated code, records patterns in metrics.db corrections table, injects trends into InstructionsLoaded.
- **Environment variable fix** - All hooks now use `CLAUDE_PLUGIN_DATA` with proper fallback.

---

## [1.2.1] - 2026-03-28

### Fixed

- **Metrics DB migration** - Added 'info' severity to violations CHECK constraint. Auto-migrates existing tables.

---

## [1.2.0] - 2026-03-28

### Added

- **3-level code validation** - Hooks now enforce code rules with progressive analysis: regex (<50ms), static analysis (<2s), and architecture validation (<2s). Rules: PHP001-005, TS001-003, LAYER001-003.
- **Blocking hooks (exit 2)** - Critical violations now **block** Claude from proceeding. Code must be fixed before continuing. Warnings remain non-blocking.
- **Pre-write validation** - New PreToolUse hook (`pre-write-check.sh`) validates layer imports BEFORE file write, preventing architecture violations at the source.
- **Session metrics** - New SessionEnd hook (`session-metrics.sh`) records session summary (blocked/warned counts) to local SQLite database.
- **`/craftsman:metrics` command** - Quality dashboard showing violations by rule, daily trends (14 days), and session history. Queries local SQLite database.
- **`craftsman-ignore` syntax** - Suppress specific rules per-line or per-file with `// craftsman-ignore: RULE_ID` comments. Suppressed violations are still tracked in metrics.
- **Metrics database** - SQLite database at `${CLAUDE_PLUGIN_DATA}/metrics.db` records all violations with project hash (privacy), rule, severity, and blocked/ignored status.
- **Static analysis wrappers** - `hooks/lib/static-analysis.sh` wraps PHPStan, ESLint, deptrac, and dependency-cruiser with graceful degradation (returns empty if tools not installed).
- **Hook test suite** - `tests/hooks/test-hooks.sh` with 12 behavioral tests covering all rules and edge cases.

### Changed

- **post-write-check.sh** - Complete rewrite from warning-only (exit 0) to blocking (exit 2) with JSON structured output, craftsman-ignore support, metrics recording, and static analysis integration.
- **hooks.json** - Now registers 4 event hooks: PreToolUse, PostToolUse, UserPromptSubmit, SessionEnd.

### Removed

- **Duplicate scripts** - Removed `scripts/bias-detector.sh` and `scripts/post-write-check.sh` (canonical copies live in `hooks/`).

---

## [1.1.1] - 2025-02-06

### Added

- **`/craftsman:setup` command** - Interactive setup wizard that was documented but never implemented. Creates `~/.claude/.craft-config.yml` with user profile, bias protection, and pack selection.
- **DISC mini-assessment** - 4-question quick test for users who don't know their DISC profile. Options: "Je connais mon DISC", "Mini-test (4 questions)", or "Passer".

### Fixed

- **Setup wizard implementation** - The wizard specification existed in `setup/wizard.md` but was never converted to an invocable command. Now properly available as `/craftsman:setup`.
- **First-run detection** - `session-init` now checks if `~/.claude/.craft-config.yml` exists and displays appropriate warnings if setup hasn't been completed.
- **Pack activation gating** - Pack-specific commands (`entity`, `usecase`, `component`, `hook`) now verify that their respective pack is enabled before proceeding. Previously all commands were available regardless of configuration.

### Changed

- **session-init** - Now displays different content based on configuration state (setup required vs configured)
- **Pack commands** - Added requirement check at the beginning of `entity.md`, `usecase.md`, `component.md`, and `hook.md`

---

## [1.1.0] - 2025-02-05

### Fixed

- **Version synchronization** - `plugin.json` and `marketplace.json` now share the same version number. This fixes an issue where Claude Code cache wouldn't update because version mismatch between the two files.

### Changed

- Commands frontmatter simplified (removed `name:` field) - Claude Code auto-generates it during installation

---

## [1.0.0] - 2025-02-04

### Added

**20 Commands with `craftsman:*` namespace**

All skills use consistent `/craftsman:*` naming convention for better discoverability and ecosystem coherence.

**Core Methodology (10)**
- `/craftsman:design` - DDD design with challenge phases
- `/craftsman:debug` - Systematic debugging (ReAct pattern)
- `/craftsman:plan` - Structured planning & execution
- `/craftsman:challenge` - Architecture review
- `/craftsman:verify` - Evidence-based verification
- `/craftsman:spec` - Specification-first (TDD/BDD)
- `/craftsman:refactor` - Systematic refactoring
- `/craftsman:test` - Pragmatic testing
- `/craftsman:git` - Safe git workflow
- `/craftsman:parallel` - Parallel agent orchestration

**Symfony/PHP (2)**
- `/craftsman:entity` - DDD entity scaffolding
- `/craftsman:usecase` - Use case with command/handler

**React/TypeScript (2)**
- `/craftsman:component` - React component scaffolding
- `/craftsman:hook` - TanStack Query hook scaffolding

**AI/ML (4)**
- `/craftsman:rag` - RAG pipeline design
- `/craftsman:mlops` - MLOps audit
- `/craftsman:agent-design` - AI agent design (3P pattern)
- `/craftsman:source-verify` - Verify AI capabilities against official docs

**Utility (1)**
- `/craftsman:session-init` - Session initialization

**5 Specialized Agents**
- `architecture-reviewer` - Clean Architecture compliance
- `security-pentester` - Security vulnerability detection
- `symfony-reviewer` - Symfony/DDD best practices
- `react-reviewer` - React patterns and hooks
- `ai-reviewer` - RAG/MLOps/Agent best practices

**Hooks System**
- `bias-detector.sh` - Cognitive bias detection (UserPromptSubmit)
- `post-write-check.sh` - Code validation for Write|Edit tools

**Knowledge Base**
- Principles (SOLID, DRY, YAGNI, KISS)
- Patterns (DDD, Clean Architecture, Microservices)
- Canonical examples (PHP entities, TS components)
- Anti-patterns (Anemic domain, Prop drilling, Any type)
- AI-specific (RAG architecture, MLOps, Vector databases, 3P pattern)

**Optional MCP Server**
- `knowledge-rag` - Semantic search over local PDFs with Ollama embeddings

### Architecture

- **Consolidated structure**: Single `/skills/` directory for all skills
- **Single `/agents/` directory**: All reviewers in one place
- **Single `/knowledge/` directory**: All reference material centralized
- **Framework packs** contain only templates (no skill duplication)

---

## Links

- [GitHub Repository](https://github.com/BULDEE/ai-craftsman-superpowers)
- [Documentation](https://github.com/BULDEE/ai-craftsman-superpowers/tree/main/docs)
- [Issue Tracker](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
