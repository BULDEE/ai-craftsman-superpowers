# Copilot fixtures: DOCUMENTED, NOT CAPTURED

No GitHub Copilot consumer (CLI, VS Code, cloud agent) was available on the
machine that wrote these. Every file here is transcribed from
https://docs.github.com/en/copilot/reference/hooks-reference as read on
2026-09-15: the two envelopes (camelCase `sessionId`/`toolName`/`toolArgs`/
`toolResult`, PascalCase `session_id`/`tool_name`/`tool_input`/`tool_result`),
`toolArgs` possibly a JSON string, `tool_result.result_type` success or
failure, and the tool names `create`, `edit`, `str_replace_editor`, `bash`.

The ARGUMENT names of the file tools (`path`, `file_text`, `old_str`,
`new_str`) do NOT appear on that page: it types `toolArgs` as "unknown" and
says it is parsed from a JSON string when possible. They are the names those
tools carry in GitHub's own tool definitions and were not seen on a wire. The
page shows `resultType: "success"` for postToolUse and routes a failed tool to
`postToolUseFailure` (with `error`); `result_type: "failure"` in
`post-tool-use.bash.camel.json` is a value this adapter accepts, not one the
page documents. The page names two hook surfaces, CLI and cloud agent; VS Code
has its own hooks guide with the Claude format and its own tool names. A test
that passes on these files proves the adapter honours the documented
contract; it does not qualify a Copilot surface. The first real capture
(`copilot --help`, a `.github/hooks/*.json` with `cat >> file` on preToolUse
and postToolUse, one run on CLI, one in the cloud agent) goes to
`tests/fixtures/hosts/copilot/<version>/` and replaces this directory's
authority. Until then the healthcheck's host row says `unknown` for a raw
Copilot payload and `copilot` only for one the adapter translated.
