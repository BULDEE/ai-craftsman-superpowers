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
- any `/Users/<name>` becomes `/Users/__USER__`

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

## Not captured (open)

- A Codex PLUGIN-bundled hook's environment (only a project hook was run).
- Codex `write_stdin` polling of a long command: the 12 s command produced
  one PostToolUse with the final output; no intermediate event reached the
  hook.
- Copilot CLI, VS Code and cloud: no consumer available on this machine.
