# Host hook payload fixtures

Every file here was captured from the real consumer, not written from a
documentation page. A fixture answers "what does this host actually send to a
hook", which no schema and no doc excerpt can: `tool_response` for a Bash
command is a bare string on Codex and an object without `exit_code` on Claude
Code, and neither fact appears in the pages the audit cited.

## Capture method

A throwaway git project with a project-level hooks file whose every hook is
`cat >> <file>.jsonl` (plus `env | sort` for the variable names). One
non-interactive run per host, driven by a fixed prompt. The raw captures stay
outside the repository; the files here are the same objects with two
redactions, applied uniformly:

- the capture workspace path becomes `__WORKSPACE__`
- any `/Users/<name>` becomes `__HOME__`
- the project slug in a transcript path becomes `__WORKSPACE_SLUG__`, and a
  session's temporary directory becomes `__SESSION_TMP__` (from 2.1.302)

Nothing else is edited. `hook-env.*.json` lists variable NAMES only.

## claude-code/2.1.272

- Date: 2026-09-15. `claude --version`: `2.1.272 (Claude Code)`;
  `CLAUDE_CODE_EXECPATH` in the hook environment named `versions/2.1.271`.
- Command: `claude -p --dangerously-skip-permissions --model haiku
  --output-format json "<prompt>"`, hooks in `<project>/.claude/settings.json`.
- Raw sha256 (first 16): pre `3d475312182f1fbb`, post `f95bf6b33ea3f8cc`.
- Observed, and load-bearing for the hooks:
  - Bash `tool_response` = `{"stdout","stderr","interrupted","isImage",
    "noOutputExpected"}` (+ `backgroundTaskId` with `run_in_background`).
    No `exit_code`. A command exiting 3 produced PreToolUse and NO
    PostToolUse at all (it is a PostToolUseFailure).
  - Write `tool_response` = `{"type":"create","filePath","content",
    "structuredPatch","originalFile","userModified"}`; Edit =
    `{"filePath","oldString","newString","originalFile",...}`.
  - Hook env carries `CLAUDECODE=1`, `CLAUDE_CODE_SESSION_ID`,
    `CLAUDE_PROJECT_DIR`; the payload carries `prompt_id` and
    `transcript_path`.
- Second run, same day and command, hooks on `PostToolUse` and
  `PostToolUseFailure` with an empty matcher (raw sha256 first 16: post
  `51efa5d78d7ad158`, failure `6c849bbbdc87e491`). Observed:
  - A Bash command exiting 1 or 127 is a `PostToolUseFailure` with
    `error: "Exit code N\n<output>"` and `is_interrupt: false`; there is no
    PostToolUse for it. The exit code lives in that string and nowhere else.
  - A `run_in_background` Bash returns `backgroundTaskId` at once; the result
    arrives later as a `TaskOutput` PostToolUse whose `tool_response.task`
    carries `task_id`, `status: "completed"`, `exitCode` and `output`, and NOT
    the command: only the task id ties the two events together. A third run
    (real hooks, a fake `pytest` in the project) showed the limit: when the
    model does not poll with TaskOutput, the background task's end reaches
    the model as a task notification and NO hook event fires, so a
    background test run stays pending (`pending_test_tasks`) until polled.

- Third run (`subagent-stop.json` and the two transcripts): one `Agent`
  spawn that wrote src/Domain/Order.php. `SubagentStop` carries
  `transcript_path` (the PARENT's transcript, 0 writes) and
  `agent_transcript_path` (the child's, under `<session>/subagents/`, the
  writes are there), plus `agent_id`, `agent_type`, `last_assistant_message`,
  `stop_hook_active`, `background_tasks`, `session_crons`. The transcripts
  are kept with their `user` and `assistant` rows only, paths redacted. One
  more edit: a U+2014 in Claude Code's own Write tool-result text was
  replaced by a colon (repository rule; no hook reads that string).

## claude-code/2.1.302

- Date: 2026-10-18. `claude --version`: `2.1.302 (Claude Code)`. Interactive
  session, hooks added for the capture to `<project>/.claude/settings.local.json`
  (`cat > file` on `UserPromptSubmit` and on `PostToolUse` for `Bash`), then
  removed. Raw sha256 (first 16): user-prompt-submit `41b22f50eefe9989`,
  post-tool-use `2afa32a0110a33fa`.
- Why: 2.1.277 removed the `TaskOutput` tool (changelog: "Claude reads a
  background task's output file with Read instead"), so the third run under
  2.1.272 above is now the only path, and nothing polled.
- Observed, and load-bearing for the hooks:
  - `post-tool-use.bash.run-in-background.json`: unchanged shape,
    `tool_response.backgroundTaskId` set, no exit code.
  - `user-prompt-submit.task-notification.completed.json`: when the task ends,
    `UserPromptSubmit` fires with the notification as `prompt`:
    `<task-notification>` with `<task-id>` (the `backgroundTaskId`),
    `<tool-use-id>`, `<output-file>`, `<status>completed</status>` and
    `<summary>... completed (exit code 0)</summary>`. The hooks documentation
    lists scheduled tasks, background subagents and cross-session messages as
    the turns that fire `UserPromptSubmit`; a background shell task is not
    listed, so this is observed, not documented.
  - `user-prompt-submit.task-notification.failed.json`: same envelope as the
    completed capture; its `prompt` is the transcript's `queued_command`
    record for a command that exited 3 in the same session
    (`<status>failed</status>`, `... failed with exit code 3`). The completed
    capture shows that record and the hook's `prompt` are the same text.
  - The output file ends with `[exited with code N]`; not read by any hook.

## claude-code/2.1.304

- Date: 2026-10-20. `claude --version`: `2.1.304 (Claude Code)`. Headless:
  `claude -p --dangerously-skip-permissions --model haiku --setting-sources project
  --settings '{"bashEditDiffEnabled": true}' --output-format json "<prompt>"` in a
  throwaway git repository, with a project hook `cat >> <file>.jsonl` on
  `PostToolUse` for `Bash`. Raw sha256 (first 16): writes `3ddac04cd193b2e7`,
  read-only and delete `147b295e05d00538`. Redactions as above, plus the
  transcript slug.
- Why: `tool_response.bashEditDiff` (documented from 2.1.269 on
  https://code.claude.com/docs/en/hooks) lists the files a Bash command
  changed, which the write gate never saw (CR-256).
- Observed, and load-bearing for the hooks:
  - The same run without `--settings` sent no `bashEditDiff` at all, in
    bypass mode: the documented "only when Claude Code directs Claude to edit
    files through Bash" did not hold for a prompt that asked for Bash.
  - `post-tool-use.bash.edit-diff-created.json` (`printf ... > src/Domain/Order.php`):
    `changedFiles` holds the absolute path; `files[0]` carries the hunks and
    `created: true`; `moreFiles: 0`.
  - `post-tool-use.bash.edit-diff-modified.json` (`sed -i`): same shape, no
    `created`.
  - `post-tool-use.bash.edit-diff-deleted.json` (`rm`): the deleted file is
    still in `changedFiles`, with `deleted: true` in `files[0]`; a hook must
    check the file exists before judging it.
  - `post-tool-use.bash.edit-diff-read-only.json` (`ls`): no `bashEditDiff` key.
- `session-start.interactive.json`: the same version started INTERACTIVELY
  (`claude --plugin-dir <capture plugin>` under a pseudo-terminal, killed
  once the hook had fired), with a plugin hook `cat > <file>.json` on
  `SessionStart`. Raw sha256 (first 16): `575a05a9780d0393`. Redactions as
  above; `scratchpad_dir` becomes `__SESSION_TMP__/scratchpad`.
  - It carries `model` (`claude-opus-5-5`) and `scratchpad_dir`, and neither
    `prompt_id` nor `permission_mode`. The same version run headless (`-p`)
    sent no `model`, which is why no earlier capture had one.
  - `hooks/lib/host.sh` read `model` without `prompt_id` as Codex, so every
    new interactive Claude Code session was filed as Codex (CR-291).

## codex/0.154.0

- Date: 2026-09-15. `codex --version`: `codex-cli 0.154.0`. Model reported in
  the payload: `gpt-6-astra`. Project-level `.codex/hooks.json`, run with
  `codex exec --sandbox workspace-write --dangerously-bypass-hook-trust
  --ephemeral --skip-git-repo-check -o <file> - < prompt.md`. Two runs.
- Raw sha256 (first 16): run 1 pre `99c079583bd9c07b`, post `484d1f2e39a8b0eb`;
  run 2 pre `7f04d78e410d7e47`, post `3b5669024e9956c6`.
- Observed, and load-bearing for the hooks:
  - Shell commands reach hooks as `tool_name: "Bash"` (already aliased on the
    wire); patches as `tool_name: "apply_patch"` with the whole patch in
    `tool_input.command` and no `file_path`.
  - Patch grammar in the wild: `*** Begin Patch`, `*** Add File: <path>`
    (`+` lines), `*** Update File: <path>` with optional `*** Move to: <path>`
    and `@@` hunks (` `/`-`/`+` lines), `*** End Patch`. Paths were ABSOLUTE
    in this capture; the grammar also allows paths relative to `cwd`.
  - Bash `tool_response` is a bare STRING holding the output. `exit 3` with
    output gave the output only; `false` gave `""`. The exit code is not
    observable from PostToolUse on this host.
  - apply_patch `tool_response` is a string:
    `Exit code: 0\nWall time: ...\nOutput:\nSuccess. Updated the following
    files:\nA <path>\nM <path>`.
  - Payload carries `session_id`, `turn_id`, `model`, `transcript_path: null`
    and no `prompt_id`. The hook process INHERITS the parent environment: run
    from inside a Claude Code Bash tool, a Codex project hook saw 123
    variables including the parent's `CLAUDE_CODE_SESSION_ID` and
    `CLAUDECODE=1` (no `CLAUDE_PROJECT_DIR`), plus Codex's own
    `CODEX_MANAGED_BY_NPM` and `CODEX_MANAGED_PACKAGE_ROOT`. No `PLUGIN_ROOT`
    or `PLUGIN_DATA` for a project hook (plugin-bundled hooks are documented
    to receive them and the `CLAUDE_*` aliases; not captured). A first probe
    that reported "no CLAUDE_* variable" was wrong: its grep ran before the
    env was flushed. The environment therefore cannot name the host; the
    payload can (`hooks/lib/host.sh`).
  - `SessionStart` has `source: "startup"`; `Stop` has `stop_hook_active` and
    `last_assistant_message`; `SessionEnd` has `reason: "other"`.

- Bash tool environment of a Codex session (fourth run, `codex exec`, shell
  command `env`): `CODEX_SESSION_ID`, `CODEX_THREAD_ID` (equal, and equal to
  the SessionStart payload's `session_id`), `CODEX_VERSION`, `CODEX_SANDBOX`,
  `CODEX_SANDBOX_NETWORK_DISABLED`, `CODEX_CI`, `CODEX_MANAGED_BY_NPM`,
  `CODEX_MANAGED_PACKAGE_ROOT`, plus every `CLAUDE_*` of the parent Claude
  Code session this run was launched from. A skill in a Codex Bash tool can
  name its own session; a hook cannot rely on the environment.

## grok/1.0.30

- Date: 2026-09-15. `grok --version`: `grok 1.0.30 (04b7ffed98c6) [stable]`.
  Model reported in the run output: `grok-4.6-build`. Project-level
  `.grok/hooks/capture.json` (SessionStart, PreToolUse, PostToolUse,
  PostToolUseFailure, every handler `cat` to a file), the project trusted with
  `--trust`, run with `grok -p "<prompt>" --always-approve --trust
  --output-format json --no-subagents`. Four runs: a `write`, two
  `search_replace`, two shell commands.
- Raw sha256 (first 16): session-start `edd68762c34a31fa`, write pre
  `3d524631e5545ce5` / post `6f67f08a949e7ad0`, search_replace pre
  `536f80be614d421e` / post `728cca583944b37c`, bash pre `fb355ce2ad06952b`,
  bash exit 3 `40c12709552441cd`, bash pytest missing `5442b23ad06f42bb`.
- One more redaction than the two above: the transcript path holds the
  workspace URL-encoded (`%2Fprivate%2Ftmp%2F...`), replaced by
  `__WORKSPACE_ENCODED__`.
- Observed, and load-bearing for the hooks:
  - Every key is sent TWICE, camelCase and snake_case: `hookEventName`
    (lowercase, `pre_tool_use`) and `hook_event_name` (`PreToolUse`),
    `sessionId`/`session_id`, `toolName`/`tool_name`, `toolInput`/`tool_input`,
    `toolResult`/`tool_response`, `transcriptPath`/`transcript_path` (a string
    under `~/.grok/sessions/<encoded workspace>/<session>/updates.jsonl`),
    plus `cwd`, `workspaceRoot` (trailing slash), `timestamp` (ISO string),
    `permissionMode`, `toolUseId`. The snake_case half is Claude Code's
    shape, so a hook written for Claude Code reads it unchanged; the
    `workspaceRoot` + lowercase `hookEventName` pair is what names the host.
  - A creation is `tool_name: "write"` with `{file_path, content}`; an edit
    is `tool_name: "search_replace"` with `{file_path, old_string,
    new_string}` and the path RELATIVE to `cwd` when the model wrote it so
    (`"ok.txt"`). Claude's `Write`/`Edit` matchers fire on both (the user's
    `~/.claude/settings.json` `Write|Edit|MultiEdit|...` handler ran on
    `write` and on `search_replace` in the transcript's `hook_execution`
    rows), but the hook receives Grok's own name: a gate that only knew
    `Write`/`Edit` exited 0 on both.
  - Write/edit `tool_response` = `{"type": "SearchReplace", "EditsApplied":
    {old_string, new_string, tool_output_for_prompt, absolute_path, edits}}`
    for both tools.
  - A shell command is `tool_name: "run_terminal_command"` (Claude's `Bash`
    matcher fires on it); its `tool_response` = `{"type": "Bash", "output":
    [<bytes>], "output_for_prompt": "exit: N\n<text>", "exit_code": N,
    "command", "truncated", "signal", "timed_out", "current_dir",
    "output_file", "total_bytes"}`. A command exiting 3 and one exiting 1
    both produced PostToolUse WITH `exit_code`: the exit code is observable
    on this host, unlike Codex.
  - Hooks that ran, per the session's `hook_execution` rows: the global
    `~/.claude/settings.json` handlers, the project `.grok/hooks` handlers
    once trusted. Not a single handler from any Claude plugin, craftsman
    included, although `grok inspect` lists `hooks/hooks.json` of six plugins
    as `file plugin: <name>`. Same with this branch exposed as a PROJECT
    plugin (`.grok/plugins/craftsman`, `grok inspect`: "craftsman (project,
    enabled) 22 skills, 1 agents, hooks"): a `write` of an invalid Domain
    class landed, and the `--debug` log read `plugin discovered
    name=craftsman scope=project ... has_hooks=true`, then `hooks: discovery
    complete total_hooks=0` on the plugin layer and `loaded hooks
    hook_count=10` (6 global, 4 project). A one-hook control plugin could not
    be validated: a new project plugin is auto-added to the disabled list and
    `grok plugin enable` does not know project plugins. Headless `-p` only.
    Not trusted, project hooks are silently skipped (run 5: `search_replace`
    landed, no project row).
  - `SessionStart` carries `source: "new"` and no transcript path.
  - Hook environment (its hooks guide, 1.0.30): `GROK_HOOK_EVENT`,
    `GROK_HOOK_NAME`, `GROK_SESSION_ID`, `GROK_WORKSPACE_ROOT`; plugin hooks
    add `GROK_PLUGIN_ROOT`/`GROK_PLUGIN_DATA` and the `CLAUDE_PLUGIN_*`
    aliases. `GROK_HOOK_EVENT` was read by the capture script; the rest is
    documented, not captured.

### grok/1.0.41 plugin install, second call (2026-09-23)

- `grok --version`: `grok 1.0.41 (4220f3b224a6) [stable]`.
- Command, twice, on this checkout: `grok plugin install <root> --trust`.
- First call exited 0: `Installed 1 plugin(s) from <root>: craftsman`.
- Second call exited 1. The stderr is `plugin-install-second.txt`, unmodified.
  The distinctive phrase is `already installed`. `bin/craftsman-grok-install`
  treats that phrase as "the plugin is present" and still exports the gate.

### codex/0.154.0-app-server (2026-09-20)

- Same `codex --version` (`codex-cli 0.154.0`), different path in: the plugin
  installed NATIVELY (`codex plugin marketplace add <tree>` reads
  `.claude-plugin/marketplace.json`, then `codex plugin add
  craftsman@ai-craftsman-superpowers`), the session driven through Codex's
  app server. Captured by a Codex session qualifying this plugin, on an
  isolated `CODEX_HOME`.
- Raw sha256 (first 16): session-start `4da00d171117937f`. One extra
  redaction: `/Users/woprrr` becomes `__HOME__` inside the transcript path.
- What differs from the project-hook capture of 2026-09-15, and is
  load-bearing: `transcript_path` is a REAL path
  (`<codex home>/sessions/2026/09/20/rollout-<ts>-<id>.jsonl`), not null, and
  `model` reads `gpt-5.6-sol`. A detection that read a string transcript path
  as Claude Code's mark called this session claude-code, and it then wrote
  Claude Code's bridge under `~/.claude`.
- Also measured in that session, and recorded in
  `hooks/host-capabilities.json`: installing and enabling the plugin does NOT
  trust its hooks (14 handlers `trustStatus=untrusted` until reviewed);
  Codex's hook runtime distinguishes `Blocked` (exit 2 with stderr) from
  `Failed`, and reads stderr before stdout JSON; unfinished background hooks
  are cancelled at shutdown, so no async hook can force a continuation; the
  shell `tool_response` is still the bare output string with no exit code,
  while Codex's own `commandExecution` events (not visible to a hook) carry
  `exitCode`.
- Not ours, measured all the same: a file written by a shell command
  (`printf > src/Domain/Order.php`) lands with every hook enabled and
  trusted. The write gate judges write TOOLS; `docs/reference/hooks.md` says
  so.

- End to end on 2026-09-20, the branch wired as a project hooks file
  (`.grok/hooks/craftsman.json`, generated from `hooks/hooks.json`) with the
  folder trusted: the real CLI, prompted, refused a `write` of a non-final
  Domain class importing Infrastructure, refused the `search_replace` that
  dropped `final`, refused `phpstan.neon`, and put `.craft-rules.yml` to the
  user (`ask`), which `--always-approve` accepted. `run_terminal_command`
  exiting 1 wrote the failure line and revoked the evidence, so the
  verification loop is live there. Control with the folder untrusted: every
  forbidden file landed, silently, which is what an untrusted project hook
  does on this host.
  A refusal appears in Grok's own `hook_execution` rows as `failed`: that is
  how the host renders exit 2, not a broken hook. The branch exposed as a
  project PLUGIN (`.grok/plugins/craftsman`) is still listed
  `project, disabled` and contributes no hook row.

## Not captured (open)

- A Codex PLUGIN-bundled hook's environment (only a project hook was run).
- Codex `write_stdin` polling of a long command: the 12 s command produced
  one PostToolUse with the final output; no intermediate event reached the
  hook.
- Copilot CLI, VS Code and cloud: no consumer available on this machine.
- A Grok PLUGIN-bundled hook running at all: see `plugin_hooks_executed` in
  `hooks/host-capabilities.json`.
